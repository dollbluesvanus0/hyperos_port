#!/usr/bin/env python3
"""Keep extracted APK/JAR files intact in diagnostic ROM builds."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys


def is_archive(name):
    return Path(name).suffix.lower() in ('.apk', '.jar')


def inventory(images):
    images = Path(images)
    if not images.is_dir():
        raise ValueError(f'Image directory does not exist: {images}')
    files = {}
    for directory, directories, names in os.walk(images, followlinks=False):
        # Record archive symlinks without following Android absolute targets.
        names += [name for name in directories if (Path(directory) / name).is_symlink()]
        for name in names:
            if not is_archive(name):
                continue
            path = Path(directory) / name
            relative = path.relative_to(images).as_posix()
            if path.is_symlink():
                files[relative] = {'symlink': os.readlink(path)}
            elif path.is_file():
                digest = hashlib.sha256()
                with path.open('rb') as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(chunk)
                files[relative] = {'size': path.stat().st_size, 'sha256': digest.hexdigest()}
            else:
                raise ValueError(f'APK/JAR is not a regular file or symlink: {relative}')
    return files


def capture(images, manifest):
    files = inventory(images)
    Path(manifest).write_text(json.dumps({'version': 1, 'files': files},
                                        indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(f'TEST MODE: recorded {len(files)} APK/JAR files before patches.')
    return len(files)


def verify(images, manifest):
    baseline = json.loads(Path(manifest).read_text(encoding='utf-8'))
    if baseline.get('version') != 1 or not isinstance(baseline.get('files'), dict):
        raise ValueError('Invalid APK/JAR baseline manifest.')
    expected = baseline['files']
    actual = inventory(images)
    changes = []
    for name in sorted(expected.keys() | actual.keys()):
        if name not in expected:
            changes.append('added: ' + name)
        elif name not in actual:
            changes.append('removed: ' + name)
        elif expected[name] != actual[name]:
            changes.append('changed: ' + name)
    if changes:
        details = '\n'.join(changes[:20])
        raise ValueError(f'TEST MODE: {len(changes)} APK/JAR differences; refusing to pack.\n{details}')
    print(f'TEST MODE: verified {len(actual)} APK/JAR files unchanged; safe to pack.')
    return len(actual)


def copy_overlay(source, images):
    """Retain device native/config overlays while excluding archive replacements."""
    source, images = Path(source), Path(images)
    if not source.is_dir() or not images.is_dir():
        raise ValueError('Device overlay and image directories must exist.')
    shutil.copytree(source, images, dirs_exist_ok=True, symlinks=True,
                    ignore=lambda directory, names: [name for name in names if is_archive(name)])
    print('TEST MODE: copied device overlay without APK/JAR files.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('capture', 'verify'):
        subparser = commands.add_parser(command)
        subparser.add_argument('images', type=Path)
        subparser.add_argument('manifest', type=Path)
    overlay = commands.add_parser('overlay')
    overlay.add_argument('source', type=Path)
    overlay.add_argument('images', type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == 'overlay':
            copy_overlay(args.source, args.images)
        elif args.command == 'capture':
            capture(args.images, args.manifest)
        else:
            verify(args.images, args.manifest)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
