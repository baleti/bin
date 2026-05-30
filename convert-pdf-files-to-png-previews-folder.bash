#!/usr/bin/env bash

# Usage: ./convert-pdf-files-to-png-previews-folder.bash "/path/to/folder 1/with/svg files" /path/to/folder 2/with/svg files"

# Converts PDF files to PNG.
# Traverses project directories passed on command line, mirrors their folder structure in a new $HOME/previews folder and creates PNG image of PDF files with the same name and .pdf.png suffix.
# Skips files whose preview is already up to date (matched by mtime).
# Also removes previews whose source PDF has been deleted.

# Previews serve indexing tools like voidtools everything to navigate large folder structures.
# Dependencies: fdfind, pdftoppm (poppler-utils)

for dir in "$@"; do
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
