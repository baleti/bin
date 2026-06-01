#!/usr/bin/env sh
setsid nohup socat UNIX-LISTEN:"/home/user/.gnupg/S.gpg-agent,fork" EXEC:"/home/user/bin/wsl2-ssh-pageant.exe -gpgConfigBasepath 'C:/Users/<username>/AppData/Local/gnupg' --gpg S.gpg-agent" & >/dev/null
setsid nohup socat UNIX-LISTEN:"/home/user/.gnupg/S.gpg-agent.ssh,fork,unlink-early" EXEC:"/home/user/bin/wsl2-ssh-pageant.exe" & >/dev/null
