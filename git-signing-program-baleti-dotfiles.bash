#!/bin/bash

pass close

DECRYPT='gpg -d ~/.password-store/.coffin/coffin.tar.gpg | tar -xO ./baleti-git-ssh-signing-key.gpg | gpg -d'

# git calls us as: <prog> --status-fd=2 -bsau <keyid>  (sign)
#              or: <prog> --verify ...                   (verify)

if [[ " $* " == *" -bsau "* ]]; then
    /usr/bin/sq sign --signer-file <(eval "$DECRYPT") --detached --armor --output - -
else
    exec gpg "$@"
fi
