import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).parent / "prepare_noise_android.py"
spec = importlib.util.spec_from_file_location("prepare_noise_android", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class NoiseFilterAndroidTests(unittest.TestCase):
    def test_gradle_formats(self):
        examples = {
            "android {\n compileSdk = 34\n}\n": "compileSdk = 36",
            "android {\n compileSdkVersion 34\n}\n": "compileSdkVersion 36",
            "android {\n compileSdkVersion(34)\n}\n": "compileSdkVersion(36)",
            "android {\n compileSdk = 36\n}\n": "compileSdk = 36",
        }
        for before, expected in examples.items():
            with self.subTest(example=before):
                after = mod.update_gradle(before)
                self.assertIn(expected, after)
                self.assertEqual(after, mod.update_gradle(after))

    def test_reject_missing_ambiguous_sdk(self):
        with self.assertRaises(ValueError):
            mod.update_gradle("android {\n targetSdk = 34\n}\n")
        with self.assertRaises(ValueError):
            mod.update_gradle("compileSdk = 34\ncompileSdk = 35\n")

    def test_patch_only_expected_plugin(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            config = root / "client" / ".dart_tool" / "package_config.json"
            config.parent.mkdir(parents=True)
            package = root / "packages" / "livekit_noise_filter-0.2.1"
            android = package / "android"
            android.mkdir(parents=True)
            gradle = android / "build.gradle"
            gradle.write_text("android {\n compileSdk = 34\n targetSdk = 27\n}\n")
            config.write_text(json.dumps({"packages": [{
                "name": "livekit_noise_filter",
                "rootUri": package.as_uri(),
                "packageUri": "lib/"
            }]}))
            self.assertEqual(mod.prepare(config), str(gradle))
            self.assertIn("compileSdk = 36", gradle.read_text())
            self.assertIn("targetSdk = 27", gradle.read_text())
            config.write_text(json.dumps({"packages": [{
                "name": "livekit_noise_filter",
                "rootUri": (root / "packages" / "livekit_noise_filter-0.3.0").as_uri(),
                "packageUri": "lib/"
            }]}))
            with self.assertRaises(ValueError):
                mod.prepare(config)


if __name__ == "__main__":
    unittest.main()
