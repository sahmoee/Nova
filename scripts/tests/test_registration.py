import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("registration", Path(__file__).parents[1] / "verify_registration.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture(ios=True, tv=True, grouped=True):
    objects = {
        "project": {"isa": "PBXProject", "mainGroup": "root"},
        "root": {"isa": "PBXGroup", "children": ["group"]},
        "group": {"isa": "PBXGroup", "path": "Nova", "children": ["file"] if grouped else []},
        "file": {"isa": "PBXFileReference", "path": "Shared.swift"},
        "iosBuild": {"isa": "PBXBuildFile", "fileRef": "file"},
        "tvBuild": {"isa": "PBXBuildFile", "fileRef": "file"},
        "iosPhase": {"isa": "PBXSourcesBuildPhase", "files": ["iosBuild"] if ios else []},
        "tvPhase": {"isa": "PBXSourcesBuildPhase", "files": ["tvBuild"] if tv else []},
        "ios": {"isa": "PBXNativeTarget", "name": "Nova-iOS", "buildPhases": ["iosPhase"]},
        "tv": {"isa": "PBXNativeTarget", "name": "Nova-tvOS", "buildPhases": ["tvPhase"]},
    }
    return {"rootObject": "project", "objects": objects}


class RegistrationChecks(unittest.TestCase):
    def test_shared_source(self):
        self.assertEqual(module.validate(fixture(), {"Nova/Shared.swift"}), [])

    def test_missing_tv_membership(self):
        self.assertEqual(module.validate(fixture(tv=False), {"Nova/Shared.swift"}),
                         ["Nova/Shared.swift: missing from Nova-tvOS Sources"])

    def test_missing_group_reference(self):
        self.assertEqual(len(module.validate(fixture(grouped=False), {"Nova/Shared.swift"})), 2)

    def test_ios_only_source(self):
        project = fixture(tv=False)
        project["objects"]["file"].update(path="Nova/App/CarPlayDelegate.swift", sourceTree="SOURCE_ROOT")
        self.assertEqual(module.validate(project, {"Nova/App/CarPlayDelegate.swift"}), [])

    def test_inactive_copies_are_not_required(self):
        self.assertEqual(module.validate(fixture(), {"Nova/QACore/QAIdentity.swift"}), [])

    def test_new_unregistered_file_is_rejected(self):
        self.assertEqual(len(module.validate(fixture(), {"Nova/NewFeature.swift"})), 2)

    def test_relative_parent_segments(self):
        project = fixture()
        project["objects"]["file"]["path"] = "Services/../Shared.swift"
        self.assertEqual(module.validate(project, {"Nova/Shared.swift"}), [])


if __name__ == "__main__":
    unittest.main()
