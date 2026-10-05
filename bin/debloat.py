#!/usr/bin/env python3
"""Remove listed Chinese/global donor apps before packing the ROM images."""

import argparse
from pathlib import Path
import shutil


APP_ROOTS = ('product/app', 'product/priv-app', 'product/data-app', 'system/system/app')
LIST_DIRECTORY = Path(__file__).resolve().with_name('debloat')
# These names describe families whose ROM directory names have attached suffixes.
PREFIX_FAMILIES = ('HotwordEnrollment', 'Sogou', 'iflytek')


def load_names():
    names = set()
    for filename in ('china.txt', 'global.txt'):
        for line in (LIST_DIRECTORY / filename).read_text(encoding='utf-8').splitlines():
            name = line.strip()
            if not name or name.startswith('#'):
                continue
            if name in ('.', '..') or '/' in name or '\\' in name:
                raise ValueError('Invalid app name in ' + filename + ': ' + name)
            names.add(name)
    if not names:
        raise ValueError('The donor app removal lists are empty.')
    return names


def matches_name(name, names):
    if name.endswith('.apk'):
        name = name[:-4]
    return (name in names
            or any(name.startswith(app + separator) for app in names for separator in ('_', '-', '.'))
            or any(app in names and name.startswith(app) for app in PREFIX_FAMILIES))


def debloat(images):
    images = Path(images).resolve(strict=True)
    if not images.is_dir():
        raise ValueError('The unpacked donor images directory is missing.')
    names = load_names()
    app_roots = [images / relative for relative in APP_ROOTS]
    # Validate every root before deleting anything. Partition/root links must
    # not redirect cleanup into another directory, even inside the image tree.
    for app_root in app_roots:
        if app_root.resolve() != app_root:
            raise ValueError('Donor app root is a symlink: ' + str(app_root))
        if app_root.exists() and not app_root.is_dir():
            raise ValueError('Donor app root is not a directory: ' + str(app_root))
    removed = []
    for app_root in app_roots:
        if not app_root.is_dir():
            continue
        for app in sorted(app_root.iterdir()):
            if not app.is_symlink() and not app.is_dir() and app.suffix != '.apk':
                continue
            # Inspect APK basenames only at the app directory's top level.
            # Never follow an app symlink or search arbitrary nested folders.
            apk_matches = (not app.is_symlink() and app.is_dir()
                           and any(matches_name(apk.name, names) for apk in app.glob('*.apk')))
            if not matches_name(app.name, names) and not apk_matches:
                continue
            if app.is_symlink() or app.is_file():
                app.unlink()
            else:
                shutil.rmtree(app)
            relative = app.relative_to(images).as_posix()
            removed.append(relative)
            print('Removed donor app: ' + relative)
    print('Donor debloat: removed ' + str(len(removed)) + ' app entries.')
    return removed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('images', type=Path, help='Unpacked donor images directory')
    args = parser.parse_args()
    try:
        debloat(args.images)
    except (OSError, ValueError) as exc:
        parser.exit(1, 'Donor debloat failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()
