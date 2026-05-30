#!/usr/bin/env sh
curl -s https://api.github.com/repos/antonmedv/fx/releases/latest | gron | grep 'browser_download_url' | cut -d'"' -f2 | grep 'fx_linux_amd64' | xargs curl -L -o $HOME/bin/fx && chmod +x $HOME/bin/fx
# curl -s https://api.github.com/repos/JakubMelka/PDF4QT/releases/latest | gron | grep 'browser_download_url' | cut -d'"' -f2 | grep 'AppImage$' | xargs curl -L -o $HOME/bin/PDF4QT.AppImage && chmod +x $HOME/bin/PDF4QT.AppImage
curl -s https://api.github.com/repos/mgdm/htmlq/releases/latest | gron | grep 'browser_download_url' | cut -d'"' -f2 | grep 'linux.tar.gz$' | xargs curl -L | tar -xz -C $HOME/bin
