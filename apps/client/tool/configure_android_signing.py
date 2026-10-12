#!/usr/bin/env python3
"""Configure a generated Flutter Android Kotlin Gradle project for signed release.

Reads signing values from CI environment; never embeds secrets or keystore in Git.
Runs after 'flutter create --platforms=android .' has generated native files.
"""
from pathlib import Path
import os
import re
import sys

def main():
    required = ("VEYLOR_KEY_ALIAS", "VEYLOR_KEY_PASSWORD", "VEYLOR_STORE_PASSWORD", "VEYLOR_KEYSTORE_PATH")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Missing Android signing variables: " + ", ".join(missing))
    keystore = Path("android/app") / os.environ["VEYLOR_KEYSTORE_PATH"]
    if not keystore.is_file():
        raise RuntimeError("Android signing keystore not found")
    gradle = Path("android/app/build.gradle.kts")
    if not gradle.is_file():
        raise RuntimeError("Expected Flutter Android Kotlin DSL file android/app/build.gradle.kts")
    source = gradle.read_text(encoding="utf-8")
    old = 'signingConfig = signingConfigs.getByName("debug")'
    if source.count(old) != 1 or source.count("    buildTypes {") != 1:
        raise RuntimeError("Unexpected Android Gradle template; refusing unsafe patch")
    # App ID is immutable for the lifetime of a released Android application.
    app_id = re.compile(r'applicationId\s*=\s*"[^"]+"')
    if len(app_id.findall(source)) != 1:
        raise RuntimeError("Expected exactly one Android applicationId")
    source = app_id.sub('applicationId = "com.veylor.app"', source, count=1)
    signing_block = """
    signingConfigs {
        create("veylorRelease") {
            keyAlias = System.getenv("VEYLOR_KEY_ALIAS")
            keyPassword = System.getenv("VEYLOR_KEY_PASSWORD")
            storeFile = file(System.getenv("VEYLOR_KEYSTORE_PATH"))
            storePassword = System.getenv("VEYLOR_STORE_PASSWORD")
        }
    }
"""
    source = source.replace("    buildTypes {", signing_block + "\n    buildTypes {", 1)
    source = source.replace(old, 'signingConfig = signingConfigs.getByName("veylorRelease")', 1)
    gradle.write_text(source, encoding="utf-8")
    print("Android signed-release configuration applied for com.veylor.app")

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Android signing configuration refused: {error}", file=sys.stderr)
        sys.exit(1)
