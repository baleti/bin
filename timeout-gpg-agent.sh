#!/usr/bin/env sh
"/mnt/c/Program Files (x86)/GnuPG/bin/gpgconf.exe" --kill gpg-agent
"/mnt/c/Program Files (x86)/GnuPG/bin/gpg-agent.exe"
"/mnt/c/Program Files (x86)/GnuPG/bin/gpg-connect-agent.exe" /bye
"/mnt/c/Program Files (x86)/GnuPG/bin/gpg.exe" --card-status >/dev/null 2>&1
pkill -f "socat UNIX-LISTEN:/home/user/.gnupg/S.gpg-agent"
pkill -f "socat UNIX-LISTEN:/home/user/.gnupg/S.gpg-agent.ssh"
/home/user/bin/socat-wsl2-ssh-pageant.sh
/usr/bin/pass close
# useful if you accidentally invoked gpg-agent on wsl
pkill gpg
