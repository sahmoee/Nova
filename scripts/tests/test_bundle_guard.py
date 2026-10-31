from pathlib import Path
import subprocess
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[2] / 'bundleid-guard.sh'

class BundleGuardChecks(unittest.TestCase):
    def audit(self, conditional):
        with tempfile.TemporaryDirectory(prefix='nova-bundle-guard-') as temp:
            project = Path(temp) / 'Fixture.xcodeproj'
            project.mkdir()
            (project / 'project.pbxproj').write_text('PRODUCT_BUNDLE_IDENTIFIER = com.nova.app.ios;\n' + conditional)
            return subprocess.run(['bash', str(GUARD), '--project', str(project)], capture_output=True, text=True)

    def test_catalyst_qualified_identity_is_audited(self):
        result = self.audit('"PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]" = com.nova.app.mac;')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('1x  com.nova.app.mac', result.stdout)

    def test_unexpected_qualified_identity_is_rejected(self):
        result = self.audit('"PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]" = com.wrong.mac;')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('UNEXPECTED bundle id(s): com.wrong.mac', result.stdout)

if __name__ == '__main__':
    unittest.main()
