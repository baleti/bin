#!/usr/bin/env bash

# remove/add relay chains depending on current number of revit sessions based on sessions registered by revit-ballet server in runtime folder

sessions_file=$HOME/revit-ballet/runtime/network/sessions

# remove stale entries in sessions file
# check listening ports and PIDs on the host match entries in sessions file
listening_pairs=$(powershell.exe -Command 'Get-NetTCPConnection -State Listen | Select-Object -Property LocalPort,OwningProcess | ForEach-Object { "$($_.LocalPort):$($_.OwningProcess)" }' 2>/dev/null)
grep -v '^#' "$sessions_file" | grep -v '^$' | while IFS=, read -r sid port host pid rest; do
  echo "$listening_pairs" | grep -qw "${port}:${pid}" || sed -i "/^$sid,/d" "$sessions_file"
done

session_ports=$(grep -v '^#' $sessions_file | grep -v '^$' | cut -d',' -f2)
ssh_ports="33591 33592 33593"

# cleanup old relays
ps eww -eo cmd | grep TAG=revit-ballet | grep -oP 'socat VSOCK-LISTEN:\K\d+' | grep -vwFf <(echo "$session_ports") | xargs -I{} pkill -f "socat VSOCK-LISTEN:{}"
for ssh_port in $ssh_ports; do
    ssh -p $ssh_port user@127.0.0.1 "ps eww -eo cmd | grep TAG=revit-ballet | grep -oP 'TCP-LISTEN:\K\d+' | grep -vwFf <(echo '$session_ports') | xargs -I{} pkill -f 'socat TCP-LISTEN:{}'"
done

# start new relays if not running already
for session_port in $session_ports; do
    pgrep -f "socat VSOCK-LISTEN:$session_port" >/dev/null || TAG=revit-ballet socat VSOCK-LISTEN:$session_port,fork TCP:127.0.0.1:$session_port &
    for ssh_port in $ssh_ports; do
        ssh -p $ssh_port user@127.0.0.1 "( pgrep -f '^socat TCP-LISTEN:$session_port' || TAG=revit-ballet socat TCP-LISTEN:$session_port,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:2:$session_port ) >/dev/null 2>&1 &"
    done
done
