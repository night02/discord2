#!/usr/bin/env python3
"""Create a valid Windows ICO from Veylor's checked-in PNG (stdlib only).
Run AFTER flutter create and BEFORE flutter build windows. Does not alter users' files.
"""
from pathlib import Path
import struct

client = Path(__file__).resolve().parents[1]
source = client / "assets" / "veylor_logo.png"
destination = client / "windows" / "runner" / "resources" / "app_icon.ico"
png = source.read_bytes()
signature = b"\x89PNG\r\n\x1a\n"
if not png.startswith(signature) or len(png) < 100:
    raise SystemExit("Veylor logo PNG is missing or invalid.")
w, h = struct.unpack_from(">II", png, 16)
if (w, h) != (128, 128):
    raise SystemExit(f"Expected 128x128 source, got {w}x{h}.")
# Windows supports PNG-compressed images inside ICO since Vista.
header = struct.pack("<HHH", 0, 1, 1)
entry = struct.pack("<BBBBHHII", 128, 128, 0, 0, 1, 32, len(png), 22)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(header + entry + png)
print(f"Veylor icon written to {destination} ({len(png)} PNG bytes)")
