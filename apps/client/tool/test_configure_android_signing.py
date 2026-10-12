import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("configure_android_signing.py").resolve()
SAMPLE = """
android {
    namespace = "com.example.veylor"
    defaultConfig {
        applicationId = "com.example.veylor"
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
"""

class ConfigureSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "android" / "app"
        self.app.mkdir(parents=True)
        self.gradle = self.app / "build.gradle.kts"
        self.gradle.write_text(SAMPLE, encoding="utf-8")
        (self.app / "veylor-release.jks").write_bytes(b"A" * 240)
        self.env = {
            **os.environ,
            "VEYLOR_KEY_ALIAS": "veylor",
            "VEYLOR_KEY_PASSWORD": "example-not-a-real-password",
            "VEYLOR_STORE_PASSWORD": "example-not-a-real-password",
            "VEYLOR_KEYSTORE_PATH": "veylor-release.jks",
        }

    def run_script(self):
        return subprocess.run([sys.executable, str(SCRIPT)], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_injects_release_key_from_environment_without_baking_secrets(self):
        output = self.run_script()
        self.assertEqual(output.returncode, 0, output.stderr)
        content = self.gradle.read_text(encoding="utf-8")
        self.assertIn('applicationId = "com.veylor.app"', content)
        self.assertIn('signingConfig = signingConfigs.getByName("veylorRelease")', content)
        self.assertIn('System.getenv("VEYLOR_STORE_PASSWORD")', content)
        self.assertNotIn("example-not-a-real-password", content)

    def test_refuses_missing_secrets_without_modifying_native_files(self):
        self.env.pop("VEYLOR_STORE_PASSWORD")
        output = self.run_script()
        self.assertNotEqual(output.returncode, 0)
        self.assertEqual(self.gradle.read_text(encoding="utf-8"), SAMPLE)

    def test_refuses_unknown_gradle_template(self):
        self.gradle.write_text(SAMPLE.replace('signingConfig = signingConfigs.getByName("debug")', ''), encoding="utf-8")
        output = self.run_script()
        self.assertNotEqual(output.returncode, 0)
        self.assertIn("Unexpected Android Gradle template", output.stderr)

if __name__ == "__main__":
    unittest.main()
