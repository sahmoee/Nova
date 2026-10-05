import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release", pathlib.Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.app = self.root / "Products/Applications/Fixture.app"
        self.info = {"CFBundleVersion": "34", "CFBundleShortVersionString": "1.0", "CFBundleIdentifier": "fixture.app", "CFBundleExecutable": "Fixture", "DTXcodeBuild": "27A266a", "DTPlatformName": "iphoneos"}
        self.write(self.app)
    def tearDown(self): self.temp.cleanup()
    def write(self, path, changes=None, mac=False):
        executable = path / ("Contents/MacOS" if mac else "") / "Fixture"
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_bytes(b"fixture")
        executable.chmod(0o755)
        path = path / ("Contents" if mac else "")
        path.mkdir(parents=True, exist_ok=True)
        (path / "Info.plist").write_bytes(plistlib.dumps(self.info | (changes or {})))
    @patch.object(release.subprocess, "run")
    def testValidArchiveChecksSignature(self, run):
        release.validate_archive(self.root, ["27A266a"])
        run.assert_called_once()
    def testEmbeddedVersionMismatch(self):
        self.write(self.app / "PlugIns/Widget.appex", {"CFBundleVersion": "33"})
        with self.assertRaisesRegex(ValueError, "build numbers"): release.validate_archive(self.root, ["27A266a"])
    def testUnapprovedToolchain(self):
        with self.assertRaisesRegex(ValueError, "unapproved"): release.validate_archive(self.root, ["27A999"])
    def testSimulatorRejected(self):
        self.write(self.app, {"DTPlatformName": "iphonesimulator"})
        with self.assertRaisesRegex(ValueError, "Simulator"): release.validate_archive(self.root, ["27A266a"])
    def testMissingVersionRejected(self):
        self.write(self.app, {"CFBundleVersion": ""})
        with self.assertRaisesRegex(ValueError, "Missing"): release.validate_archive(self.root, ["27A266a"])
    @patch.object(release.subprocess, "run")
    def testMacBundleLayout(self, run):
        (self.app / "Info.plist").unlink()
        self.write(self.app, {"DTPlatformName": "macosx"}, mac=True)
        release.validate_archive(self.root, ["27A266a"])
        run.assert_called_once()

    def testMalformedVersions(self):
        for value in [34, "-1", "1.2.3.4", "one", "1\n"]:
            self.write(self.app, {"CFBundleVersion": value})
            with self.assertRaisesRegex(ValueError, "Invalid app version"):
                release.validate_archive(self.root, ["27A266a"])

    def testInvalidBundleIdentifier(self):
        self.write(self.app, {"CFBundleIdentifier": "fixture app"})
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            release.validate_archive(self.root, ["27A266a"])

    def testDuplicateBundleIdentifier(self):
        self.write(self.app / "PlugIns/Widget.appex")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            release.validate_archive(self.root, ["27A266a"])

    def testSupportedPlatformsCannotHideSimulator(self):
        self.write(self.app, {"CFBundleSupportedPlatforms": ["iPhoneSimulator"]})
        with self.assertRaisesRegex(ValueError, "Simulator"):
            release.validate_archive(self.root, ["27A266a"])

    def testMissingPlatform(self):
        self.write(self.app, {"DTPlatformName": ""})
        with self.assertRaisesRegex(ValueError, "platform"):
            release.validate_archive(self.root, ["27A266a"])

    def testMissingExecutable(self):
        (self.app / "Fixture").unlink()
        with self.assertRaisesRegex(ValueError, "executable"):
            release.validate_archive(self.root, ["27A266a"])

    def testExecutableTraversal(self):
        self.write(self.app, {"CFBundleExecutable": "../Fixture"})
        with self.assertRaisesRegex(ValueError, "executable"):
            release.validate_archive(self.root, ["27A266a"])

    def testMetadataSymlinkCannotEscape(self):
        outside = self.root.parent / (self.root.name + "-outside.plist")
        try:
            outside.write_bytes(plistlib.dumps(self.info))
            (self.app / "Info.plist").unlink()
            (self.app / "Info.plist").symlink_to(outside)
            with self.assertRaisesRegex(ValueError, "escapes"):
                release.validate_archive(self.root, ["27A266a"])
        finally: outside.unlink(missing_ok=True)

    def testMetadataMustBeDictionary(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(["invalid"]))
        with self.assertRaisesRegex(ValueError, "dictionary"):
            release.validate_archive(self.root, ["27A266a"])

    def testOutputPaths(self):
        for value in ["relative", str(release.ROOT / "build"), str(self.root / ".." / "build")]:
            with self.assertRaises(ValueError): release.validate_output(value)
        with patch.dict(release.os.environ, {"SOWENS_BUILD_VOLUME_UUID": "fixture"}), patch.object(release.pathlib.Path, "is_mount", return_value=True), patch.object(release.subprocess, "check_output", return_value=plistlib.dumps({"VolumeUUID": "fixture", "FilesystemType": "apfs"})):
            self.assertEqual(release.validate_output(str(self.root)), self.root.resolve())

    def testOutputSymlinkToSource(self):
        link = self.root / "source"
        link.symlink_to(release.ROOT, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "source repository"):
            release.validate_output(str(link / "build"))

    def testSchemePaths(self):
        for value in ["../main", "foo/bar", "foo\\bar", "", "\n", ".."]:
            with self.assertRaisesRegex(ValueError, "scheme"): release.validate_scheme(value)
        self.assertEqual(release.validate_scheme("The SESH."), "The SESH.")

if __name__ == "__main__": unittest.main()
