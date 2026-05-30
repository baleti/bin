#!/usr/bin/env bash

# Dependencies: fdfind, pdftoppm (poppler-utils)
# Usage: run manually or via cron/systemd timer

# Converts PDF files to PNG.
# Traverses project directories from $PDF_DIRS, copies their folder structure in a new $HOME/previews folder and creates PNG image (of the first page) PDF files with the same name and .pdf.png suffix.
# Skips files whose preview is already up to date (matched by mtime).
# Also removes previews whose source PDF has been deleted.

# Previews serve indexing tools like voidtools everything to navigate large folder structures.

PDF_DIRS=(
    "/path/to/folder 1/with/pdf files"
    "/path/to/folder 2/with/pdf files"
)

for dir in "${PDF_DIRS[@]}"; do
    /usr/bin/fdfind . -e pdf "$dir" -x sh -c ' \
        [ -e "$HOME/previews{}.png" ] && \
        [ $(stat -c %Y "{}") -eq $(stat -c %Y "$HOME/previews{}.png") ] || \
        (mkdir -p "$HOME/previews{//}"; \
        /usr/bin/pdftoppm -singlefile -r 72 -png "{}" "$HOME/previews{}"; \
        touch -c -r "{}" "$HOME/previews{}.png"; \
        echo "{}")' 2>/dev/null
done

# Cleanup: remove previews whose source PDF has been deleted
/usr/bin/fdfind . -e png "$HOME/previews/" -x sh -c ' \
  source_file="$(echo "{}" | sed "s|^$HOME/previews||; s|\.png$||")"; \
  [ -e "$source_file" ] || rm "{}"' 2>/dev/null
