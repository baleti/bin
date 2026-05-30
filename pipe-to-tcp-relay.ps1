# pipe-to-tcp-relay.ps1
# Optimized bidirectional relay for TLS passthrough with diagnostics
param(
    [string]$PipeName = "revit-ballet-roslyn-server-relay",
    [string]$TargetIP = "127.0.0.1",
    [int]$TargetPort = 23717
)

# Setup diagnostics logging
$script:LogPath = "$env:APPDATA\revit-ballet\runtime\diagnostics\pipe-relay.log"
$script:DiagDir = Split-Path -Parent $script:LogPath
if (-not (Test-Path $script:DiagDir)) {
    New-Item -ItemType Directory -Path $script:DiagDir -Force | Out-Null
}

function Write-RelayLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logLine = "[$timestamp] [$Level] $Message"

    # Write to console
    switch ($Level) {
        "ERROR" { Write-Host $logLine -ForegroundColor Red }
        "WARN"  { Write-Host $logLine -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
        default { Write-Host $logLine }
    }

    # Write to file
    try {
        Add-Content -Path $script:LogPath -Value $logLine -ErrorAction SilentlyContinue
    } catch {
        # Ignore file write errors
    }
}

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.IO.Pipes;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;

public class RelayStats
{
    public long Stream1ToStream2Bytes { get; set; }
    public long Stream2ToStream1Bytes { get; set; }
    public string Direction1Status { get; set; }
    public string Direction2Status { get; set; }
}

public class StreamRelay
{
    public static async Task<RelayStats> RelayBidirectional(Stream stream1, Stream stream2)
    {
        var stats = new RelayStats();
        // 8KB buffers to match TLS record size and avoid buffering issues
        var buffer1 = new byte[8192];
        var buffer2 = new byte[8192];

        var cts = new CancellationTokenSource();

        // Stream1 -> Stream2
        var task1 = Task.Run(async () =>
        {
            long totalBytes = 0;
            string status = "Unknown";
            try
            {
                while (!cts.Token.IsCancellationRequested)
                {
                    int bytesRead = await stream1.ReadAsync(buffer1, 0, buffer1.Length, cts.Token);

                    if (bytesRead == 0)
                    {
                        status = "EOF";
                        break;
                    }

                    await stream2.WriteAsync(buffer1, 0, bytesRead, cts.Token);
                    // CRITICAL: Flush immediately for TLS - buffering causes incomplete transfers
                    await stream2.FlushAsync(cts.Token);
                    totalBytes += bytesRead;
                }
            }
            catch (OperationCanceledException)
            {
                status = "Cancelled";
            }
            catch (Exception ex)
            {
                status = string.Format("Exception: {0}", ex.GetType().Name);
            }

            stats.Direction1Status = status;
            cts.Cancel(); // Signal other direction to stop
            return totalBytes;
        });

        // Stream2 -> Stream1
        var task2 = Task.Run(async () =>
        {
            long totalBytes = 0;
            string status = "Unknown";
            try
            {
                while (!cts.Token.IsCancellationRequested)
                {
                    int bytesRead = await stream2.ReadAsync(buffer2, 0, buffer2.Length, cts.Token);

                    if (bytesRead == 0)
                    {
                        status = "EOF";
                        break;
                    }

                    await stream1.WriteAsync(buffer2, 0, bytesRead, cts.Token);
                    // CRITICAL: Flush immediately for TLS - buffering causes incomplete transfers
                    await stream1.FlushAsync(cts.Token);
                    totalBytes += bytesRead;
                }
            }
            catch (OperationCanceledException)
            {
                status = "Cancelled";
            }
            catch (Exception ex)
            {
                status = string.Format("Exception: {0}", ex.GetType().Name);
            }

            stats.Direction2Status = status;
            cts.Cancel(); // Signal other direction to stop
            return totalBytes;
        });

        // Wait for BOTH tasks to complete (don't close streams prematurely)
        try
        {
            await Task.WhenAll(task1, task2);
        }
        catch
        {
            // Expected when tasks are cancelled
        }

        // CRITICAL: Ensure all buffered data is flushed before closing streams
        // This is especially important for TLS which may have data in encryption buffers
        try
        {
            await stream1.FlushAsync(cts.Token);
            await stream2.FlushAsync(cts.Token);
        }
        catch
        {
            // Ignore flush errors during shutdown
        }

        // Small delay to ensure network buffers are sent
        await Task.Delay(50);

        // Get results
        stats.Stream1ToStream2Bytes = (task1.Status == TaskStatus.RanToCompletion) ? task1.Result : 0;
        stats.Stream2ToStream1Bytes = (task2.Status == TaskStatus.RanToCompletion) ? task2.Result : 0;

        cts.Dispose();
        return stats;
    }
}
"@

Write-RelayLog "=== Relay Starting ===" "INFO"
Write-RelayLog "Pipe: \\.\pipe\$PipeName <-> ${TargetIP}:${TargetPort}" "INFO"
Write-RelayLog "Log file: $script:LogPath" "INFO"
Write-RelayLog "TLS-optimized mode (8KB buffers, immediate flush)" "INFO"

$script:SessionCount = 0
$script:TotalBytesToTarget = 0
$script:TotalBytesFromTarget = 0

while ($true) {
    $pipe = $null
    $tcpClient = $null
    $sessionId = ++$script:SessionCount
    $sessionStart = Get-Date

    try {
        # CRITICAL: Increase max instances from 1 to 254 (max allowed)
        # This prevents "All pipe instances are busy" errors
        Write-RelayLog "[Session $sessionId] Creating named pipe server..." "INFO"
        $pipe = New-Object System.IO.Pipes.NamedPipeServerStream(
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            254,  # Max concurrent connections
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::Asynchronous,
            8192,  # Input buffer size (8KB) - matches TLS/npiperelay expectations
            8192   # Output buffer size (8KB)
        )

        Write-RelayLog "[Session $sessionId] Waiting for pipe connection on \\.\pipe\$PipeName" "INFO"
        $pipeWaitStart = Get-Date
        $pipe.WaitForConnection()
        $pipeWaitMs = ((Get-Date) - $pipeWaitStart).TotalMilliseconds
        Write-RelayLog "[Session $sessionId] Pipe client connected (waited ${pipeWaitMs}ms)" "SUCCESS"

        # Connect to TCP target
        Write-RelayLog "[Session $sessionId] Connecting to TCP ${TargetIP}:${TargetPort}..." "INFO"
        $tcpConnectStart = Get-Date
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.NoDelay = $true  # Disable Nagle's algorithm for lower latency
        $tcpClient.ReceiveTimeout = 30000  # 30 second timeout
        $tcpClient.SendTimeout = 30000
        $tcpClient.Connect($TargetIP, $TargetPort)
        $tcpStream = $tcpClient.GetStream()
        $tcpConnectMs = ((Get-Date) - $tcpConnectStart).TotalMilliseconds
        Write-RelayLog "[Session $sessionId] TCP connected (${tcpConnectMs}ms)" "SUCCESS"

        # Start bidirectional relay
        Write-RelayLog "[Session $sessionId] Starting bidirectional relay..." "INFO"
        $relayStart = Get-Date
        $relayTask = [StreamRelay]::RelayBidirectional($pipe, $tcpStream)

        # Wait for completion with timeout (60 seconds of inactivity detection)
        $lastActivity = Get-Date
        $timeoutSeconds = 60
        $completed = $false

        try {
            while (-not $completed) {
                # Check if task completed
                if ($relayTask.Wait(1000)) {  # Wait 1 second
                    $completed = $true
                    Write-RelayLog "[Session $sessionId] Relay task completed normally" "SUCCESS"
                    break
                }

                # Check for timeout (task still running after 60 seconds)
                $inactiveSeconds = ((Get-Date) - $relayStart).TotalSeconds
                if ($inactiveSeconds -gt $timeoutSeconds) {
                    Write-RelayLog "[Session $sessionId] TIMEOUT after ${inactiveSeconds}s - relay hung, forcing cleanup" "ERROR"
                    # Force close the streams to unblock the relay
                    try { $pipe.Close() } catch {}
                    try { $tcpStream.Close() } catch {}
                    # Give it a moment to detect the closure
                    Start-Sleep -Milliseconds 500
                    if (-not $relayTask.IsCompleted) {
                        Write-RelayLog "[Session $sessionId] Relay still hung after forced close, abandoning" "ERROR"
                    }
                    break
                }
            }
        } catch {
            Write-RelayLog "[Session $sessionId] Relay task exception: $($_.Exception.Message)" "ERROR"
            if ($_.Exception.InnerException) {
                Write-RelayLog "[Session $sessionId] Inner exception: $($_.Exception.InnerException.Message)" "ERROR"
            }
        }

        $relayMs = ((Get-Date) - $relayStart).TotalMilliseconds

        # Get statistics (if available)
        $sessionDuration = ((Get-Date) - $sessionStart).TotalMilliseconds

        if ($relayTask.IsCompleted -and -not $relayTask.IsFaulted) {
            $stats = $relayTask.Result
            $script:TotalBytesToTarget += $stats.Stream1ToStream2Bytes
            $script:TotalBytesFromTarget += $stats.Stream2ToStream1Bytes

            Write-RelayLog "[Session $sessionId] === Relay Complete (${sessionDuration}ms total) ===" "SUCCESS"
            Write-RelayLog "[Session $sessionId]   Pipe->TCP: $($stats.Stream1ToStream2Bytes) bytes ($($stats.Direction1Status))" "INFO"
            Write-RelayLog "[Session $sessionId]   TCP->Pipe: $($stats.Stream2ToStream1Bytes) bytes ($($stats.Direction2Status))" "INFO"
            Write-RelayLog "[Session $sessionId]   Relay duration: ${relayMs}ms" "INFO"
        } else {
            Write-RelayLog "[Session $sessionId] === Relay Incomplete (${sessionDuration}ms total) ===" "WARN"
            Write-RelayLog "[Session $sessionId]   Task state: Completed=$($relayTask.IsCompleted), Faulted=$($relayTask.IsFaulted), Canceled=$($relayTask.IsCanceled)" "WARN"
            if ($relayTask.IsFaulted -and $relayTask.Exception) {
                Write-RelayLog "[Session $sessionId]   Exception: $($relayTask.Exception.Message)" "ERROR"
            }
        }

        # Log cumulative statistics every 10 sessions
        if ($sessionId % 10 -eq 0) {
            Write-RelayLog "[STATS] Total sessions: $sessionId, To target: $script:TotalBytesToTarget bytes, From target: $script:TotalBytesFromTarget bytes" "INFO"
        }

    }
    catch {
        $sessionDuration = ((Get-Date) - $sessionStart).TotalMilliseconds
        Write-RelayLog "[Session $sessionId] ERROR after ${sessionDuration}ms: $($_.Exception.Message)" "ERROR"
        Write-RelayLog "[Session $sessionId] Exception type: $($_.Exception.GetType().FullName)" "ERROR"
        if ($_.Exception.InnerException) {
            Write-RelayLog "[Session $sessionId] Inner exception: $($_.Exception.InnerException.Message)" "ERROR"
            Write-RelayLog "[Session $sessionId] Inner type: $($_.Exception.InnerException.GetType().FullName)" "ERROR"
        }
        # Log stack trace for debugging
        Write-RelayLog "[Session $sessionId] Stack trace: $($_.Exception.StackTrace)" "ERROR"
    }
    finally {
        Write-RelayLog "[Session $sessionId] Cleanup: Closing connections..." "INFO"
        # Cleanup
        if ($tcpClient) {
            try {
                $tcpClient.Close()
                Write-RelayLog "[Session $sessionId] TCP client closed" "INFO"
            } catch {
                Write-RelayLog "[Session $sessionId] Error closing TCP: $($_.Exception.Message)" "WARN"
            }
        }
        if ($pipe) {
            try {
                if ($pipe.IsConnected) {
                    $pipe.Disconnect()
                    Write-RelayLog "[Session $sessionId] Pipe disconnected" "INFO"
                }
                $pipe.Dispose()
                Write-RelayLog "[Session $sessionId] Pipe disposed" "INFO"
            } catch {
                Write-RelayLog "[Session $sessionId] Error closing pipe: $($_.Exception.Message)" "WARN"
            }
        }

        # Small delay before accepting next connection
        Start-Sleep -Milliseconds 50
        Write-RelayLog "[Session $sessionId] Ready for next connection" "INFO"
    }
}
