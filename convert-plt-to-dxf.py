# python3 -m venv venv
# source venv/bin/activate
# pip install PyMuPDF Pillow ezdxf
# fd -e plt -x python3 convert-plt-to-dxf.py

import sys
import os
from ezdxf.addons.hpgl2 import api as hpgl2

def convert_plt_to_dxf(file_path):
    try:
        with open(file_path, "rb") as fp:
            data = fp.read()
        doc = hpgl2.to_dxf(data, color_mode=hpgl2.ColorMode.ACI)
        output_file = os.path.splitext(file_path)[0] + ".dxf"
        doc.saveas(output_file)
        print(f"Converted {file_path} to {output_file}")
    except Exception as e:
        print(f"Failed to convert {file_path}: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 convert.py <path_to_plt_file>")
        sys.exit(1)

    plt_file_path = sys.argv[1]
    if not os.path.isfile(plt_file_path):
        print(f"File not found: {plt_file_path}")
        sys.exit(1)

    convert_plt_to_dxf(plt_file_path)
