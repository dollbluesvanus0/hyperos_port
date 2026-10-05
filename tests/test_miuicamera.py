import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

REPOSITORY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('miuicamera', REPOSITORY / 'bin/miuicamera.py')
camera = importlib.util.module_from_spec(spec)
spec.loader.exec_module(camera)


def write_apk(path, payload=b'new camera'):
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('AndroidManifest.xml', b'fixture manifest')
        archive.writestr('classes.dex', payload)
        archive.writestr('lib/arm64-v8a/libCamera.so', b'fixture library')


class CameraReplacementTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='camera tests ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.apk = self.root / 'downloaded camera.apk'
        write_apk(self.apk)
        self.images = self.root / 'images'
        (self.images / 'product').mkdir(parents=True)

    def install(self):
        with contextlib.redirect_stdout(io.StringIO()):
            camera.install_camera(self.apk, self.images)

    def old_app(self, relative):
        app = self.images / relative
        (app / 'oat/arm64').mkdir(parents=True)
        (app / 'MiuiCamera.apk').write_bytes(b'old camera')
        (app / 'oat/arm64/MiuiCamera.odex').write_bytes(b'old odex')
        return app

    def test_public_drive_link_uses_download_endpoint(self):
        url = camera.download_url(camera.DEFAULT_URL + '?usp=drive_link')
        self.assertEqual(url, 'https://drive.usercontent.google.com/download?id=1a_I20XHYjxNOn5mudIoenHCRaqGPAb93&export=download&confirm=t')

    def test_invalid_url_fails(self):
        for url in ('http://example.com/camera.apk', 'https://drive.google.com/file/d/../view',
                    'https://user:password@example.com/camera.apk', 'https://example.com/bad name.apk'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                camera.download_url(url)

    def test_html_page_fails_before_replacing_old_app(self):
        old = self.old_app('product/priv-app/MiuiCamera')
        self.apk.write_text('<html>Google Drive confirmation</html>', encoding='utf-8')
        with self.assertRaises(zipfile.BadZipFile):
            self.install()
        self.assertEqual((old / 'MiuiCamera.apk').read_bytes(), b'old camera')

    def test_zip_without_dex_is_rejected(self):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            archive.writestr('AndroidManifest.xml', 'fixture')
        with self.assertRaises(ValueError):
            self.install()

    def test_replaces_camera_and_removes_old_oat(self):
        old = self.old_app('product/priv-app/MiuiCamera')
        (old / 'lib').mkdir()
        (old / 'lib/old.so').write_bytes(b'old lib')
        self.install()
        self.assertEqual((old / 'MiuiCamera.apk').read_bytes(), self.apk.read_bytes())
        self.assertFalse((old / 'oat').exists())
        self.assertFalse((old / 'lib').exists())
        self.assertEqual(sorted(p.name for p in old.iterdir()), ['MiuiCamera.apk'])

    def test_removes_duplicates_preserves_other_apps_and_permissions(self):
        duplicate = self.old_app('system/system/app/MiuiCamera')
        other = self.images / 'product/priv-app/CameraTools'
        other.mkdir(parents=True)
        (other / 'CameraTools.apk').write_bytes(b'keep')
        permission_dir = self.images / 'product/etc/permissions'
        permission_dir.mkdir(parents=True)
        original = permission_dir / 'privapp-permissions-product.xml'
        original.write_text('<permissions/>', encoding='utf-8')
        self.install()
        self.assertFalse(duplicate.exists())
        self.assertEqual((other / 'CameraTools.apk').read_bytes(), b'keep')
        self.assertEqual(original.read_text(encoding='utf-8'), '<permissions/>')
        xml = ET.parse(permission_dir / 'privapp-permissions-miuicamera.xml')
        node = xml.find("privapp-permissions[@package='com.android.camera']/permission")
        self.assertEqual(node.attrib['name'], 'android.permission.TURN_SCREEN_ON')

    def test_missing_product_partition_fails(self):
        (self.images / 'product').rmdir()
        with self.assertRaises(ValueError):
            self.install()

    def test_preserves_existing_camera_grants_without_duplicates(self):
        permissions = self.images / 'product/etc/permissions'
        permissions.mkdir(parents=True)
        path = permissions / 'privapp-permissions-miuicamera.xml'
        path.write_text('<permissions><privapp-permissions package="com.android.camera">'
                        '<permission name="android.permission.SYSTEM_CAMERA"/>'
                        '</privapp-permissions></permissions>', encoding='utf-8')
        self.install()
        self.install()
        node = ET.parse(path).find("privapp-permissions[@package='com.android.camera']")
        self.assertEqual([p.attrib['name'] for p in node],
                         ['android.permission.SYSTEM_CAMERA', 'android.permission.TURN_SCREEN_ON'])

    def test_repeated_install_is_clean(self):
        self.install()
        self.install()
        self.assertEqual([p.name for p in (self.images / 'product/priv-app').iterdir()], ['MiuiCamera'])

    def test_invalid_download_does_not_replace_previous_download(self):
        previous = self.apk.read_bytes()
        def html_download(args, check):
            Path(args[args.index('--output') + 1]).write_text('<html>Error</html>', encoding='utf-8')
        with patch.object(camera.subprocess, 'run', side_effect=html_download), self.assertRaises(zipfile.BadZipFile):
            camera.download_camera(camera.DEFAULT_URL, self.apk)
        self.assertEqual(self.apk.read_bytes(), previous)
        self.assertFalse(list(self.root.glob('.MiuiCamera-*')))

    def test_network_error_is_fatal(self):
        previous = self.apk.read_bytes()
        with patch.object(camera.subprocess, 'run', side_effect=subprocess.CalledProcessError(22, 'curl')):
            with self.assertRaises(subprocess.CalledProcessError):
                camera.download_camera(camera.DEFAULT_URL, self.apk)
        self.assertEqual(self.apk.read_bytes(), previous)

    def test_successful_download_is_verified_and_published(self):
        output = self.root / 'downloads/MiuiCamera.apk'
        def apk_download(args, check):
            self.assertEqual(args[-1], camera.download_url(camera.DEFAULT_URL))
            write_apk(Path(args[args.index('--output') + 1]))
        with patch.object(camera.subprocess, 'run', side_effect=apk_download), contextlib.redirect_stdout(io.StringIO()):
            camera.download_camera(camera.DEFAULT_URL, output)
        camera.validate_apk(output)
        self.assertFalse(list(output.parent.glob('.MiuiCamera-*')))


if __name__ == '__main__':
    unittest.main()
