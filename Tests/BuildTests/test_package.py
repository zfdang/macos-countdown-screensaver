import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = pathlib.Path(__file__).resolve().parents[2]


class PackageTests(unittest.TestCase):
    def test_release_version_and_icon_are_packaged_in_both_bundles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'dist').mkdir()
            metadata = {'version': 'v26.10.08-5', 'bundleVersion': '26.10.8',
                        'build': '5', 'commit': 'a' * 40, 'date': '26.10.08'}
            (root / 'dist/build-info.json').write_text(json.dumps(metadata))
            (root / 'Assets').mkdir()
            icon = (REPOSITORY / 'Assets/Countdown.icns').read_bytes()
            self.assertEqual(icon[:4], b'icns')
            self.assertEqual(int.from_bytes(icon[4:8], 'big'), len(icon))
            (root / 'Assets/Countdown.icns').write_bytes(icon)
            for name in ['README.md', 'LICENSE']:
                (root / name).write_text(name)
            for bundle in ['Countdown.saver', 'Countdown Preview.app']:
                (root / bundle / 'Contents').mkdir(parents=True)
            subprocess.run([sys.executable, str(REPOSITORY / 'scripts/package-info.py'),
                            str(root), 'arm64'], cwd=root, check=True)
            for bundle in ['Countdown.saver', 'Countdown Preview.app']:
                with self.subTest(bundle=bundle):
                    contents = root / bundle / 'Contents'
                    info = plistlib.loads((contents / 'Info.plist').read_bytes())
                    self.assertEqual(info['CountdownReleaseVersion'], metadata['version'])
                    self.assertEqual(info['CFBundleShortVersionString'], '26.10.8')
                    self.assertEqual(info['CFBundleVersion'], '5')
                    self.assertEqual(info['CountdownGitCommit'], metadata['commit'])
                    self.assertEqual((contents / 'Resources' / info['CFBundleIconFile']).read_bytes(), icon)
