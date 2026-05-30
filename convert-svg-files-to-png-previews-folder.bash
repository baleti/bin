#!/usr/bin/env bash

# Usage: ./convert-pdf-files-to-png-previews-folder.bash "/path/to/folder 1/with/svg files" /path/to/folder 2/with/svg files"

# Converts SVG files to PNG.
# Traverses project directories passed on command line, mirrors their folder structure in a new $HOME/previews folder and creates PNG image of SVG files with the same name and .svg.png suffix.
# Skips files whose preview is already up to date (matched by mtime).

# Previews serve indexing tools like voidtools everything to navigate large folder structures.
# Dependencies: fdfind, inkscape

for dir in "$@"; do
    /usr/bin/fdfind . -e svg "$dir" -x sh -c ' \
        [ -e "$HOME/previews/{.}.svg.png" ] && \
        [ $(stat -c %Y "{}") -eq $(stat -c %Y "$HOME/previews/{.}.svg.png") ] || \
        (mkdir -p "$HOME/previews/{//}"; \
        /usr/bin/inkscape --export-area-drawing --export-type=png -o "$HOME/previews/{.}.svg.png" "{}"; \
        touch -c -r "{}" "$HOME/previews/{.}.svg.png"; \
        echo "{}")' 2>/dev/null
done

# Cleanup: remove previews whose source SVG has been deleted
/usr/bin/fdfind . -e png "$HOME/previews/" -x sh -c ' \
  source_file="$(echo "{}" | sed "s|^$HOME/previews||; s|\.png$||")"; \
  [ -e "$source_file" ] || rm "{}"' 2>/dev/null
