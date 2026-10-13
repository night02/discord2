#!/usr/bin/env python3
"""Make LiveKit Noise Filter 0.2.1 Android plugin compile against API 36.

Android's androidx.core 1.18+ requires compileSdk 36. The upstream v0.2.1
noise-filter plugin uses an older compileSdk; this script changes ONLY its
compileSdk setting in the local disposable build cache after flutter pub get.

The script validates the exact expected dependency version and fails closed
if upstream layouts change, so it cannot silently alter another plugin.
Target/min SDK levels are not changed.
"""
import json
import pathlib
import re
import sys
from urllib.parse import urlparse, unquote


def project_root(config_path: pathlib.Path, package: dict) -> pathlib.Path:
    root = package.get("rootUri", "")
    url = urlparse(root)
    if url.scheme == "file":
        return pathlib.Path(unquote(url.path))
    if url.scheme or not root:
        raise ValueError("Unexpected Flutter package URI")
    return (config_path.parent / root).resolve()


def update_gradle(text: str) -> str:
    patterns = [
        # Groovy or Kotlin Gradle DSL.
        r"(?m)^(?P<indent>\s*)compileSdk\s*=\s*(?P<level>\d+)\b",
        r"(?m)^(?P<indent>\s*)compileSdkVersion\s*\(?\s*(?P<level>\d+)\s*\)?",
    ]
    for pattern in patterns:
        matches = list(re.finditer(pattern, text))
        if not matches:
            continue
        if len(matches) != 1:
            raise ValueError("Ambiguous compileSdk declarations")
        match = matches[0]
        sdk = int(match.group("level"))
        if sdk >= 36:
            return text
        return text[:match.start("level")] + "36" + text[match.end("level"):]
    raise ValueError("Missing expected compileSdk property in LiveKit noise filter plugin")


def prepare(config: pathlib.Path) -> str:
    data = json.loads(config.read_text(encoding="utf-8"))
    matches = [p for p in data["packages"] if p["name"] == "livekit_noise_filter"]
    if len(matches) != 1:
        raise ValueError("LiveKit noise filter was not resolved by flutter pub get")
    path = project_root(config, matches[0]).resolve()
    if path.name != "livekit_noise_filter-0.2.1":
        raise ValueError(f"Unexpected LiveKit noise filter version: {path.name}")
    gradle = path / "android" / "build.gradle"
    if not gradle.is_file():
        raise ValueError(f"Missing Android noise filter Gradle module: {gradle}")
    before = gradle.read_text(encoding="utf-8")
    after = update_gradle(before)
    if before != after:
        gradle.write_text(after, encoding="utf-8")
    return str(gradle)


if __name__ == "__main__":
    try:
        config_path = pathlib.Path(__file__).resolve().parents[1] / ".dart_tool" / "package_config.json"
        result = prepare(config_path)
        print(f"LiveKit noise filter Android compileSdk verified >=36: {result}")
    except Exception as exc:
        print(f"Cannot safely configure LiveKit noise filter Android plugin: {exc}", file=sys.stderr)
        sys.exit(1)
