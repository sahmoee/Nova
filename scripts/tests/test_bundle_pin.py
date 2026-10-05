import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("bundle_pin", Path(__file__).parents[1] / "pin_bundle_id.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

PROJECT = {"objects": {
    "app": {"isa": "PBXNativeTarget", "name": "Nova-iOS", "buildConfigurationList": "list"},
    "list": {"buildConfigurations": ["APPDEBUG", "APPRELEASE"]},
    "APPDEBUG": {"name": "Debug", "buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "app.old"}},
    "APPRELEASE": {"name": "Release", "buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "app.old"}},
}}
TEXT = """\t\tAPPDEBUG /* Debug */ = {
\t\t\tbuildSettings = { PRODUCT_BUNDLE_IDENTIFIER = app.old; };
\t\t};
\t\tAPPRELEASE /* Release */ = {
\t\t\tbuildSettings = { PRODUCT_BUNDLE_IDENTIFIER = app.old; };
\t\t};
\t\tWIDGETDEBUG /* Debug */ = {
\t\t\tbuildSettings = { PRODUCT_BUNDLE_IDENTIFIER = app.widget; };
\t\t};
"""


class BundlePinChecks(unittest.TestCase):
    def test_only_target_configurations_are_changed(self):
        updated, changes = module.pin(PROJECT, TEXT, "Nova-iOS", "app.new")
        self.assertEqual(updated.count("PRODUCT_BUNDLE_IDENTIFIER = app.new;"), 2)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = app.widget;", updated)
        self.assertEqual(len(changes), 2)

    def test_nonexistent_target_is_rejected(self):
        with self.assertRaises(ValueError):
            module.pin(PROJECT, TEXT, "Missing", "app.new")

    def test_identifier_cannot_inject_project_settings(self):
        with self.assertRaises(ValueError):
            module.pin(PROJECT, TEXT, "Nova-iOS", "app.new; OTHER = value")

    def test_missing_configuration_is_rejected(self):
        with self.assertRaises(ValueError):
            module.pin(PROJECT, TEXT.replace("APPDEBUG", "OTHER"), "Nova-iOS", "app.new")

    def test_duplicate_declaration_is_rejected(self):
        with self.assertRaises(ValueError):
            module.pin(PROJECT, TEXT.replace("app.old;", "app.old; PRODUCT_BUNDLE_IDENTIFIER = duplicate;", 1),
                       "Nova-iOS", "app.new")


if __name__ == "__main__":
    unittest.main()
