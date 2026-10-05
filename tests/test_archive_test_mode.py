import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('archive_test_mode', REPOSITORY / 'bin/archive_test_mode.py')
mode = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mode)


class ArchiveTestModeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='archive test mode ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.images = self.root / 'images'
        self.apk = self.images / 'product/priv-app/Camera/Camera.apk'
        self.jar = self.images / 'system/system/framework/services.jar'
        for path, content in ((self.apk, b'donor camera'), (self.jar, b'donor services')):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.prop = self.images / 'product/build.prop'
        self.prop.write_text('donor props')
        self.manifest = self.root / 'baseline.json'
        with contextlib.redirect_stdout(io.StringIO()):
            mode.capture(self.images, self.manifest)

    def test_records_actual_digests_and_all_partitions(self):
        self.assertEqual(mode.inventory(self.images)['product/priv-app/Camera/Camera.apk'],
                         {'size': 12, 'sha256': mode.hashlib.sha256(b'donor camera').hexdigest()})
        self.assertEqual(len(json.loads(self.manifest.read_text())['files']), 2)

    def test_props_can_change_without_changing_archives(self):
        self.prop.write_text('stock device props')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(mode.verify(self.images, self.manifest), 2)

    def test_same_size_archive_modification_is_fatal(self):
        self.apk.write_bytes(b'stock camera')
        with self.assertRaisesRegex(ValueError, 'changed: product/priv-app/Camera/Camera.apk'):
            mode.verify(self.images, self.manifest)

    def test_deleted_archive_is_fatal(self):
        self.jar.unlink()
        with self.assertRaisesRegex(ValueError, 'removed: system/system/framework/services.jar'):
            mode.verify(self.images, self.manifest)

    def test_new_archive_including_uppercase_suffix_is_fatal(self):
        (self.images / 'product/Overlay.APK').write_bytes(b'new overlay')
        with self.assertRaisesRegex(ValueError, 'added: product/Overlay.APK'):
            mode.verify(self.images, self.manifest)

    def test_device_overlay_keeps_native_files_and_excludes_archives(self):
        overlay = self.root / 'device overlay'
        for relative, content in (('product/priv-app/Camera/Camera.apk', b'old camera'),
                                  ('system/system/framework/services.jar', b'old services'),
                                  ('product/NewApp.APK', b'new app'),
                                  ('product/etc/device.xml', b'stock device xml'),
                                  ('system/system/lib64/libdevice.so', b'native lib')):
            path = overlay / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        with contextlib.redirect_stdout(io.StringIO()):
            mode.copy_overlay(overlay, self.images)
            mode.verify(self.images, self.manifest)
        self.assertEqual((self.images / 'product/etc/device.xml').read_bytes(), b'stock device xml')
        self.assertEqual((self.images / 'system/system/lib64/libdevice.so').read_bytes(), b'native lib')
        self.assertFalse((self.images / 'product/NewApp.APK').exists())

    def test_archive_symlinks_are_recorded_without_following_android_paths(self):
        link = self.images / 'product/Linked.jar'
        try:
            link.symlink_to('/system/framework/nonexistent.jar')
        except OSError:
            self.skipTest('Creating symlinks requires privileges on this host.')
        self.assertEqual(mode.inventory(self.images)['product/Linked.jar'],
                         {'symlink': '/system/framework/nonexistent.jar'})
        with contextlib.redirect_stdout(io.StringIO()):
            mode.capture(self.images, self.manifest)
        link.unlink()
        link.symlink_to('/system/framework/replacement.jar')
        with self.assertRaisesRegex(ValueError, 'changed: product/Linked.jar'):
            mode.verify(self.images, self.manifest)

    def test_missing_baseline_and_bad_manifest_stop_cli(self):
        self.manifest.unlink()
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(mode.main(['verify', str(self.images), str(self.manifest)]), 1)
        self.manifest.write_text('{"version": 99, "files": {}}')
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(mode.main(['verify', str(self.images), str(self.manifest)]), 1)

    def test_difference_stops_cli_with_no_success_message(self):
        self.jar.write_bytes(b'patched services')
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            self.assertEqual(mode.main(['verify', str(self.images), str(self.manifest)]), 1)
        self.assertNotIn('safe to pack', output.getvalue())
        self.assertIn('refusing to pack', errors.getvalue())

    def test_missing_images_are_fatal(self):
        with self.assertRaisesRegex(ValueError, 'does not exist'):
            mode.inventory(self.root / 'missing images')


if __name__ == '__main__':
    unittest.main()
