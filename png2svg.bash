#!/usr/bin/env bash
# png2svg.bash
# Usage: ./png2svg.bash input1.png input2.png ...
# Requirements: exiftool must be installed

# Loop through all provided PNG files
for png_file in "$@"; do
  # Check if the file exists
  if [[ ! -f "$png_file" ]]; then
    echo "Warning: File '$png_file' not found -- skipping."
    continue
  fi

  # Extract image width and height using exiftool
  width=$(exiftool -s -s -s -ImageWidth "$png_file")
  height=$(exiftool -s -s -s -ImageHeight "$png_file")

  # Verify that dimensions were obtained
  if [[ -z "$width" || -z "$height" ]]; then
    echo "Warning: Could not determine dimensions for '$png_file' -- skipping."
    continue
  fi

  # Generate the SVG file name by replacing the .png extension with .svg
  svg_file="${png_file%.*}.svg"

  # Write the SVG content to the output file.
  # The canvas is sized to match the PNG dimensions, and the <image>
  # element links to the PNG file.
  cat <<EOF > "$svg_file"
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg
    width="$width"
    height="$height"
    viewBox="0 0 $width $height"
    version="1.1"
    xmlns="http://www.w3.org/2000/svg"
    xmlns:xlink="http://www.w3.org/1999/xlink">
  <image x="0" y="0" width="$width" height="$height" xlink:href="$png_file"/>
</svg>
EOF

  echo "Created $svg_file from $png_file"
done
