#!/usr/bin/env python3
"""Download the supplied HyperOS 2 camera and replace the old system app."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import parse_qs, urlencode, urlsplit
import xml.etree.ElementTree as ET
import zipfile

DEFAULT_URL = 'https://drive.google.com/file/d/1a_I20XHYjxNOn5mudIoenHCRaqGPAb93/view'


def download_url(url):
    parts = urlsplit(url)
    if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or any(c.isspace() for c in url):
        raise ValueError('The camera URL must use HTTPS.')
    if parts.hostname == 'drive.google.com':
        match = re.fullmatch(r'/file/d/([A-Za-z0-9_-]+)(?:/view)?/?', parts.path)
        file_id = match.group(1) if match else parse_qs(parts.query).get('id', [''])[0]
        if not re.fullmatch(r'[A-Za-z0-9_-]+', file_id):
            raise ValueError('Invalid Google Drive file link.')
        query = {'id': file_id, 'export': 'download', 'confirm': 't'}
        resource_key = parse_qs(parts.query).get('resourcekey')
        if resource_key:
            query['resourcekey'] = resource_key[0]
        return 'https://drive.usercontent.google.com/download?' + urlencode(query)
    return url


def validate_apk(path):
    with zipfile.ZipFile(path) as apk:
        names = set(apk.namelist())
        if not {'AndroidManifest.xml', 'classes.dex'} <= names:
            raise ValueError('The download is not an Android APK (manifest/dex missing).')
        damaged = apk.testzip()
        if damaged:
            raise ValueError('Corrupted APK entry: ' + damaged)


def download_camera(url, output):
    output = Path(output)
    source = download_url(url)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.MiuiCamera-', suffix='.apk', dir=output.parent)
    os.close(fd)
    temporary = Path(temporary)
    try:
        subprocess.run(['curl', '--fail', '--location', '--show-error', '--silent',
                        '--retry', '3', '--connect-timeout', '30', '--max-time', '600',
                        '--output', str(temporary), source], check=True)
        validate_apk(temporary)
        temporary.chmod(0o644)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256()
    with output.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    print('MiuiCamera APK SHA256: ' + digest.hexdigest())


def remove_app(path):
    if path.is_symlink():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def install_camera(apk, images):
    apk = Path(apk)
    images = Path(images).resolve()
    validate_apk(apk)  # Reject failed/HTML downloads before changing the ROM.
    if not (images / 'product').is_dir():
        raise ValueError('The unpacked product partition is missing.')
    app_roots = [images / part / kind for part in ('product', 'system/system', 'system_ext')
                 for kind in ('app', 'priv-app')]
    old_apps = []
    for app_root in app_roots:
        if app_root.is_dir():
            if not app_root.resolve().is_relative_to(images):
                raise ValueError('Camera app path escapes the images directory.')
            old_apps.extend(app for app in app_root.iterdir()
                            if app.is_dir() and (app.name == 'MiuiCamera' or (app / 'MiuiCamera.apk').is_file()))
    destination = images / 'product/priv-app/MiuiCamera'
    if not destination.parent.resolve().is_relative_to(images):
        raise ValueError('Camera destination escapes the images directory.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.MiuiCamera-new-', dir=destination.parent))
    backup = None
    try:
        # Keep the original signed APK intact. extractNativeLibs=false: ARM64
        # libraries are already stored inside this APK; old oat/lib files must go.
        stage.chmod(0o755)
        shutil.copyfile(apk, stage / 'MiuiCamera.apk')
        (stage / 'MiuiCamera.apk').chmod(0o644)
        if destination.exists() or destination.is_symlink():
            backup = Path(tempfile.mkdtemp(prefix='.MiuiCamera-old-', dir=destination.parent))
            backup.rmdir()
            os.replace(destination, backup)
        try:
            os.replace(stage, destination)
        except OSError:
            if backup is not None:
                os.replace(backup, destination)
                backup = None
            raise
        for old_app in old_apps:
            if old_app != destination:
                remove_app(old_app)
        permissions = images / 'product/etc/permissions'
        if not permissions.resolve().is_relative_to(images):
            raise ValueError('Camera permission path escapes the images directory.')
        permissions.mkdir(parents=True, exist_ok=True)
        permission_file = permissions / 'privapp-permissions-miuicamera.xml'
        if permission_file.is_symlink():
            permission_file.unlink()
        root = ET.parse(permission_file).getroot() if permission_file.exists() else ET.Element('permissions')
        if root.tag != 'permissions':
            raise ValueError('Invalid camera privileged-permission XML.')
        camera = root.find("privapp-permissions[@package='com.android.camera']")
        if camera is None:
            camera = ET.SubElement(root, 'privapp-permissions', {'package': 'com.android.camera'})
        if camera.find("permission[@name='android.permission.TURN_SCREEN_ON']") is None:
            ET.SubElement(camera, 'permission', {'name': 'android.permission.TURN_SCREEN_ON'})
        ET.ElementTree(root).write(permission_file, encoding='utf-8', xml_declaration=True)
        permission_file.chmod(0o644)
    finally:
        remove_app(stage)
        if backup is not None:
            remove_app(backup)
    print('Installed downloaded MiuiCamera: ' + str(destination / 'MiuiCamera.apk'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    download = commands.add_parser('download')
    download.add_argument('output', type=Path)
    download.add_argument('--url', default=DEFAULT_URL)
    install = commands.add_parser('install')
    install.add_argument('apk', type=Path)
    install.add_argument('images', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'download':
            download_camera(args.url, args.output)
        else:
            install_camera(args.apk, args.images)
    except (OSError, ValueError, ET.ParseError, zipfile.BadZipFile, subprocess.CalledProcessError) as exc:
        parser.exit(1, 'MiuiCamera replacement failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()
