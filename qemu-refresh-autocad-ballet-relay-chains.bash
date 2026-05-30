#!/usr/bin/env bash

# remove/add relay chains depending on current number of autocad sessions
# based on sessions registered by autocad-ballet server in runtime folder
# this was way more complicated than I expected and I would just keep empty ones running instead if I knew ahead of time

sessions_file=$HOME/autocad-ballet/runtime/network/sessions

# remove stale entries
# check listening ports and PIDs on the host match entries in sessions file
listening_pairs=$(powershell.exe -Command 'Get-NetTCPConnection -State Listen | Select-Object -Property LocalPort,OwningProcess | ForEach-Object { "$($_.LocalPort):$($_.OwningProcess)" }' 2>/dev/null)
grep -v '^#' "$sessions_file" | grep -v '^$' | while IFS=, read -r sid port host pid rest; do
  echo "$listening_pairs" | grep -qw "${port}:${pid}" || sed -i "/^$sid,/d" "$sessions_file"
done

session_ports=$(grep -v '^#' $sessions_file | grep -v '^$' | cut -d',' -f2)
ssh_ports="33591 33592 33593"

# cleanup old relays
ps -eo cmd | grep -oP 'pipe-to-tcp-relay.ps1.*-TargetPort\s+\K\d+' | grep -vwFf <(echo "$session_ports") | xargs -I{} pkill -f "pipe-to-tcp-relay.ps1.*-TargetPort\s+{}"
ps -eo cmd | grep -oP '^socat.*autocad-ballet-roslyn-server-relay-\K\d+' | grep -vwFf <(echo "$session_ports") | xargs -I{} pkill -f "socat.*autocad-ballet-roslyn-server-relay-{}"
for ssh_port in $ssh_ports; do
    ssh -p $ssh_port user@127.0.0.1 "ps eww -eo cmd | grep TAG=autocad-ballet | grep -oP 'TCP-LISTEN:\K\d+' | grep -vwFf <(echo '$session_ports') | xargs -I{} pkill -f 'socat TCP-LISTEN:{}'"
done

# start new relays if not already setup
for session_port in $session_ports; do
    pgrep -f "pipe-to-tcp-relay.ps1.*$session_port" >/dev/null || powershell.exe -ExecutionPolicy Bypass -File $HOME/bin/pipe-to-tcp-relay.ps1 -PipeName autocad-ballet-roslyn-server-relay-$session_port -TargetPort "$session_port" &
    pgrep -f "socat VSOCK-LISTEN:$session_port" >/dev/null || socat VSOCK-LISTEN:$session_port,fork EXEC:"/home/user/bin/npiperelay.exe -ep -s //./pipe/autocad-ballet-roslyn-server-relay-$session_port",nofork &
    for ssh_port in $ssh_ports; do
        ssh -p $ssh_port user@127.0.0.1 "( pgrep -f '^socat TCP-LISTEN:$session_port' || TAG=autocad-ballet socat TCP-LISTEN:$session_port,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:2:$session_port ) >/dev/null 2>&1 &"
    done
done
