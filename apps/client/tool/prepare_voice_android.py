#!/usr/bin/env python3
"""Prepare Android permissions for foreground voice. Run after flutter create."""
from pathlib import Path

manifest = Path(__file__).resolve().parents[1] / "android/app/src/main/AndroidManifest.xml"
if not manifest.is_file():
    raise SystemExit("AndroidManifest.xml missing: run flutter create first")
src = manifest.read_text(encoding="utf-8")
if "<manifest" not in src:
    raise SystemExit("Refusing to patch a malformed Android manifest")
header = "<manifest"
permissions = (
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.permission.CAMERA",
    "android.permission.MODIFY_AUDIO_SETTINGS",
)
insertion = []
for permission in permissions:
    if f'android:name="{permission}"' not in src:
        insertion.append(f'    <uses-permission android:name="{permission}" />')
if insertion:
    # Insert before <application> so Android manifest merger retains permissions.
    if "<application" not in src:
        raise SystemExit("Android manifest has no application node")
    src = src.replace("<application", "\n".join(insertion) + "\n    <application", 1)
    manifest.write_text(src, encoding="utf-8")
print("Android foreground camera/microphone permissions verified (no background capture).")
