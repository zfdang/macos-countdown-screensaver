import importlib.util
import pathlib
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('version', pathlib.Path(__file__).resolve().parents[2] / 'scripts/version.py')
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)

class VersionTests(unittest.TestCase):
    def test_date_and_commit_count_and_full_sha(self):
        # 2026-10-07 17:00 UTC is October 8 in Shanghai.
        with patch.object(version.subprocess, 'check_output', side_effect=['false\n', '42\n', '1791392400\n', 'a' * 40 + '\n']):
            result = version.metadata()
        self.assertEqual(result['version'], 'v26.10.08-42')
        self.assertEqual(result['build'], '42')
        self.assertEqual(result['bundleVersion'], '26.10.8')
        self.assertEqual(result['commit'], 'a' * 40)

    def test_shallow_history_is_rejected(self):
        with patch.object(version.subprocess, 'check_output', return_value='true\n'):
            with self.assertRaises(SystemExit):
                version.metadata()
