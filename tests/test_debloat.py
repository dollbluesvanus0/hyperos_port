import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPOSITORY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('debloat', REPOSITORY / 'bin/debloat.py')
debloat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(debloat)


class DonorDebloatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='donor debloat tests ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.images = self.root / 'donor images'
        self.images.mkdir()

    def app(self, relative, apk='app.apk'):
        directory = self.images / relative
        directory.mkdir(parents=True)
        (directory / apk).write_bytes(b'fixture APK')
        return directory

    def clean(self):
        with contextlib.redirect_stdout(io.StringIO()) as log:
            removed = debloat.debloat(self.images)
        return removed, log.getvalue()

    def test_removes_every_listed_app_from_all_four_locations(self):
        names = debloat.load_names()
        expected = []
        for app_root in debloat.APP_ROOTS:
            for name in names:
                relative = app_root + '/' + name
                self.app(relative, name + '.apk')
                expected.append(relative)
        removed, log = self.clean()
        self.assertEqual(set(removed), set(expected))
        self.assertTrue(all(not (self.images / relative).exists() for relative in expected))
        self.assertIn('Removed donor app: product/app/VoiceTrigger', log)
        self.assertIn('Removed donor app: system/system/app/Chrome64', log)

    def test_removes_hash_architecture_and_hotword_variants(self):
        for name in ('MIUINotes_123abc', 'YouTube-arm64', 'MSA.cn',
                     'HotwordEnrollmentXGoogleHEXAGON_WIDEBAND', 'SogouInput', 'iflytekInput'):
            self.app('product/priv-app/' + name)
        removed, _ = self.clean()
        self.assertEqual(len(removed), 6)

    def test_apk_basename_identifies_renamed_data_app(self):
        app = self.app('product/data-app/com.miui.notes-123abc', 'MIUINotes.apk')
        removed, _ = self.clean()
        self.assertEqual(removed, ['product/data-app/com.miui.notes-123abc'])
        self.assertFalse(app.exists())

    def test_removes_standalone_apks(self):
        app_root = self.images / 'system/system/app'
        app_root.mkdir(parents=True)
        apk = app_root / 'BasicDreams.apk'
        apk.write_bytes(b'fixture APK')
        self.assertEqual(self.clean()[0], ['system/system/app/BasicDreams.apk'])
        self.assertFalse(apk.exists())

    def test_removes_whole_app_with_old_oat_and_libraries(self):
        app = self.app('product/app/MIUINotes')
        (app / 'oat/arm64').mkdir(parents=True)
        (app / 'oat/arm64/MIUINotes.odex').write_bytes(b'old oat')
        (app / 'lib/arm64').mkdir(parents=True)
        (app / 'lib/arm64/libnotes.so').write_bytes(b'old lib')
        self.clean()
        self.assertFalse(app.exists())

    def test_preserves_unlisted_apps_nested_assets_and_other_partitions(self):
        keep = ('product/app/DriveTools', 'product/app/MapsProvider',
                'product/priv-app/MiuiCamera', 'product/priv-app/MIUISecurityCenter',
                'product/app/SomeAnalyticsCore', 'product/app/HealthService',
                'system/system/priv-app/MIUINotes', 'system_ext/app/MSA', 'vendor/app/YouTube')
        for relative in keep:
            self.app(relative)
        tools = self.images / 'product/app/DriveTools'
        (tools / 'assets').mkdir()
        (tools / 'assets/Drive.apk').write_bytes(b'keep asset')
        (tools.parent / 'Drive.txt').write_text('keep text', encoding='utf-8')
        self.assertEqual(self.clean()[0], [])
        self.assertTrue(all((self.images / relative / 'app.apk').exists() for relative in keep))
        self.assertTrue((tools / 'assets/Drive.apk').exists())
        self.assertTrue((tools.parent / 'Drive.txt').exists())

    def test_missing_apps_and_repeated_cleanup_succeed(self):
        self.assertEqual(self.clean()[0], [])
        self.app('product/data-app/MIUINotes')
        self.assertEqual(len(self.clean()[0]), 1)
        self.assertEqual(self.clean()[0], [])

    def test_removes_app_link_without_following_its_target(self):
        outside = self.root / 'outside app'
        outside.mkdir()
        apk = outside / 'MSA.apk'
        apk.write_bytes(b'keep outside')
        link = self.images / 'product/app/MSA'
        link.parent.mkdir(parents=True)
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError as exc:
            self.skipTest('Creating symlinks is unavailable: ' + str(exc))
        self.assertEqual(self.clean()[0], ['product/app/MSA'])
        self.assertFalse(link.is_symlink())
        self.assertEqual(apk.read_bytes(), b'keep outside')

    def test_rejects_redirected_app_root_before_any_deletion(self):
        keep = self.app('product/app/MSA')
        outside = self.root / 'outside apps'
        outside.mkdir()
        (outside / 'MIUINotes.apk').write_bytes(b'keep outside')
        link = self.images / 'product/data-app'
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError as exc:
            self.skipTest('Creating symlinks is unavailable: ' + str(exc))
        with self.assertRaises(ValueError):
            self.clean()
        self.assertTrue(keep.exists())
        self.assertTrue((outside / 'MIUINotes.apk').exists())

    def test_invalid_root_and_removal_failure_stop_cli(self):
        result = subprocess.run([sys.executable, str(REPOSITORY / 'bin/debloat.py'),
                                 str(self.images / 'missing')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Donor debloat failed:', result.stderr)
        self.app('product/app/MSA')
        with patch.object(debloat.shutil, 'rmtree', side_effect=OSError('fixture permission error')):
            with self.assertRaises(OSError):
                self.clean()

    def test_packaged_lists_and_cleanup_cli_work_without_current_directory_dependency(self):
        self.app('system/system/app/BasicDreams')
        result = subprocess.run([sys.executable, str(REPOSITORY / 'bin/debloat.py'), str(self.images)],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Removed donor app: system/system/app/BasicDreams', result.stdout)


if __name__ == '__main__':
    unittest.main()
