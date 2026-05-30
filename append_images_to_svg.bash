#!/usr/bin/env bash

########################################
# USAGE:
#   ./inline_template_placer.sh image1.png image2.jpg ...
#
# REQUIREMENTS:
#   - ImageMagick must be installed for 'identify'.
#   - The script writes the final SVG to 'output.svg' in the current directory.
########################################

# Inline Inkscape template.  (Added xmlns:xlink for <image> compatibility)
# Adjust width/height/viewBox as needed or per your template’s specs.
INLINE_TEMPLATE='<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!-- Created with Inkscape (http://www.inkscape.org/) -->

<svg
   width="1920"
   height="1080"
   viewBox="0 0 1920 1080"
   version="1.1"
   id="svg1"
   inkscape:version="1.4 (86a8ad7, 2024-10-11)"
   xml:space="preserve"
   xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
   xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
   xmlns="http://www.w3.org/2000/svg"
   xmlns:svg="http://www.w3.org/2000/svg"
   xmlns:xlink="http://www.w3.org/1999/xlink">
  <sodipodi:namedview
       id="namedview1"
       pagecolor="#ffffff"
       bordercolor="#eeeeee"
       borderopacity="1"
       inkscape:showpageshadow="0"
       inkscape:pageopacity="0"
       inkscape:pagecheckerboard="0"
       inkscape:deskcolor="#202020"
       inkscape:document-units="px"
       showgrid="false" />
  <defs id="defs1">
    <rect x="772.70084" y="359.90819" width="603.76435" height="239.44912" id="rect2" />
    <rect x="552.34889" y="176.28156" width="611.10941" height="292.33359" id="rect1" />
  </defs>
  <inkscape:templateinfo>
    <inkscape:name>default</inkscape:name>
    <inkscape:date>2025-01-10</inkscape:date>
  </inkscape:templateinfo>
</svg>
'

OUTPUT_SVG="binder.svg"

# Write the inline template to the output file
echo "$INLINE_TEMPLATE" > "$OUTPUT_SVG"

# Optional vertical gap between images (in px). Increase if you want more spacing.
VERTICAL_OFFSET=10

# Initialize the running total height
total_height=0

# Loop through all images passed as arguments
for image_path in "$@"; do

  # Ensure the file exists
  if [[ ! -f "$image_path" ]]; then
    echo "Warning: '$image_path' not found — skipping."
    continue
  fi

  # Grab image dimensions using ImageMagick
  width=$(identify -format "%w" "$image_path" 2>/dev/null)
  height=$(identify -format "%h" "$image_path" 2>/dev/null)

  # If dimensions cannot be found, skip this image
  if [[ -z "$width" || -z "$height" ]]; then
    echo "Warning: Could not read dimensions for '$image_path' — skipping."
    continue
  fi

  # Construct an <image> element at y = total_height
  IMAGE_ELEMENT="<image x=\"0\" y=\"$total_height\" width=\"$width\" height=\"$height\" xlink:href=\"$image_path\" />"

  # Insert before the closing </svg> tag
  sed -i "/<\/svg>/i $IMAGE_ELEMENT" "$OUTPUT_SVG"

  # Add the image’s height + optional offset for the next image
  total_height=$((total_height + height + VERTICAL_OFFSET))

done
