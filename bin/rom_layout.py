#!/usr/bin/env python3
"""Validate extracted ROM trees and configure their actual Android fstabs."""

import argparse
from pathlib import Path
import re


SUPER_PARTITIONS = ('system', 'system_ext', 'product', 'mi_ext', 'vendor', 'odm',
                    'system_dlkm', 'product_dlkm', 'vendor_dlkm', 'odm_dlkm')


def partitions(images):
    images = Path(images)
    result = [name for name in SUPER_PARTITIONS if (images / name).is_dir()]
    missing = {'system', 'system_ext', 'product', 'vendor'} - set(result)
    if missing:
        raise ValueError('Missing extracted partitions: ' + ', '.join(sorted(missing)))
    return result


def validate(images, base_images):
    images, base_images = Path(images), Path(base_images)
    partitions(images)
    required = [base_images / 'system/system/build.prop',
                images / 'system/system/build.prop', images / 'product/etc/build.prop',
                images / 'vendor/build.prop']
    for path in required:
        if not path.is_file() or not path.stat().st_size:
            raise ValueError('Missing or empty extracted ROM property file: ' + str(path))
    system_props = (images / 'system/system/build.prop').read_text(encoding='utf-8')
    for key in ('ro.system.build.version.release', 'ro.system.build.version.sdk'):
        if not re.search(r'^' + re.escape(key) + r'=\S+', system_props, re.MULTILINE):
            raise ValueError('Missing donor system property: ' + key)
    print('Required stock/donor ROM files are present.')


def fstab_fields(line):
    fields = line.split('#', 1)[0].split()
    return fields if len(fields) >= 5 and fields[2] in ('ext4', 'erofs') else None


def partition_name(fields):
    return re.sub(r'_[ab]$', '', fields[0].rsplit('/', 1)[-1])


def configure_fstab(text, pack_format, names):
    lines = text.splitlines(keepends=True)
    entries = [fstab_fields(line) for line in lines]
    wanted = 'erofs' if pack_format == 'EROFS' else 'ext4'
    existing = {(f[0], f[1]) for f in entries if f and f[2] == wanted}
    result = []
    for line, fields in zip(lines, entries):
        if not fields or partition_name(fields) not in names or fields[2] == wanted:
            result.append(line)
            continue
        key = (fields[0], fields[1])
        if key not in existing:
            replacement = fields.copy()
            replacement[2] = wanted
            flags = fields[3].split(',')
            if wanted == 'erofs':
                # Keep generic mount options, avoiding EXT4 journal/discard flags.
                flags = [flag for flag in flags if flag in ('nosuid', 'nodev', 'noexec', 'noatime',
                         'nodiratime', 'relatime', 'strictatime', 'lazytime', 'sync', 'dirsync')
                         or flag.startswith(('context=', 'fscontext=', 'defcontext=', 'rootcontext='))]
                replacement[3] = ','.join(['ro'] + flags)
            else:
                replacement[3] = ','.join(flag for flag in flags
                                         if not flag.startswith(('cache_strategy=', 'readahead=', 'dax')))
                replacement[3] = replacement[3] or 'ro'
            result.append('\t'.join(replacement) + '\n')
            existing.add(key)
        # EROFS can fall back to an existing EXT4 image at the same mount point.
        # EXT4 repacking replaces EROFS rows, which the AVB helper removes later.
        if wanted == 'erofs':
            if result and not result[-1].endswith('\n'):
                result[-1] += '\n'
            result.append(line)
    return ''.join(result)


def configure_fstabs(root, pack_format, names):
    root = Path(root).resolve(strict=True)
    found = []
    for path in sorted(root.rglob('fstab*')):
        if not path.is_file() or path.is_symlink():
            continue
        text = path.read_text(encoding='utf-8')
        if not any(fstab_fields(line) for line in text.splitlines()):
            continue
        found.append(path)
        configured = configure_fstab(text, pack_format, set(names))
        if configured != text:
            path.write_text(configured, encoding='utf-8', newline='\n')
        print('Configured ' + pack_format + ' mounts in: ' + str(path))
    if not found:
        print('No filesystem fstab in ' + str(root) + '; keeping stock ramdisk mount configuration.')
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    listing = commands.add_parser('partitions')
    listing.add_argument('images', type=Path)
    checking = commands.add_parser('validate')
    checking.add_argument('images', type=Path)
    checking.add_argument('--base-images', type=Path, required=True)
    fstabs = commands.add_parser('fstabs')
    fstabs.add_argument('root', type=Path)
    fstabs.add_argument('--format', choices=('EXT', 'EROFS'), required=True)
    fstabs.add_argument('--partitions', nargs='+', choices=SUPER_PARTITIONS, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'partitions':
            print(' '.join(partitions(args.images)))
        elif args.command == 'validate':
            validate(args.images, args.base_images)
        else:
            configure_fstabs(args.root, args.format, args.partitions)
    except (OSError, ValueError) as exc:
        parser.exit(1, 'ROM layout error: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()
