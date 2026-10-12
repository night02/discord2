#!/usr/bin/env python3
"""Install the Veylor brand icon in Flutter-created Android launcher resources."""
from pathlib import Path
import shutil
import struct

client = Path(__file__).resolve().parents[1]
logo = client / "assets" / "veylor_logo.png"
raw = logo.read_bytes()
if not raw.startswith(b"\x89PNG\r\n\x1a\n") or struct.unpack_from(">II", raw, 16) != (128, 128):
    raise SystemExit("Expected official 128x128 PNG logo.")
base = client / "android" / "app" / "src" / "main" / "res"
sizes = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
for size in sizes:
    directory = base / ("mipmap-" + size)
    if not directory.is_dir():
        raise SystemExit("Flutter Android launcher directory missing: " + str(directory))
    shutil.copyfile(logo, directory / "ic_launcher.png")
print("Official Veylor launcher icon applied to " + str(len(sizes)) + " Android densities.")
