import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('rom_layout', REPOSITORY / 'bin/rom_layout.py')
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)


class RomLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='rom layout tests ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.images = self.root / 'images'
        self.base = self.root / 'stock images'
        for directory in ('system/system', 'system_ext', 'product/etc', 'vendor/etc'):
            (self.images / directory).mkdir(parents=True)
        (self.base / 'system/system').mkdir(parents=True)
        (self.base / 'system/system/build.prop').write_text('ro.system.build.version.release=14\n')
        (self.images / 'system/system/build.prop').write_text(
            'ro.system.build.version.release=15\nro.system.build.version.sdk=35\n')
        (self.images / 'product/etc/build.prop').write_text('ro.product.product.name=diting\n')
        (self.images / 'vendor/build.prop').write_text('ro.product.vendor.device=venus\n')

    def test_partitions_follow_actual_trees_without_fstab(self):
        (self.images / 'mi_ext').mkdir()
        (self.images / 'vendor_dlkm').mkdir()
        (self.images / 'config').mkdir()
        (self.images / 'boot.img').write_bytes(b'boot image')
        self.assertEqual(layout.partitions(self.images),
                         ['system', 'system_ext', 'product', 'mi_ext', 'vendor', 'vendor_dlkm'])

    def test_missing_donor_core_partition_is_fatal(self):
        (self.images / 'system_ext').rmdir()
        with self.assertRaisesRegex(ValueError, 'system_ext'):
            layout.partitions(self.images)

    def test_complete_layout_passes(self):
        with contextlib.redirect_stdout(io.StringIO()):
            layout.validate(self.images, self.base)

    def test_missing_or_empty_props_stop_before_patching(self):
        prop = self.images / 'system/system/build.prop'
        prop.unlink()
        with self.assertRaisesRegex(ValueError, 'property file'):
            layout.validate(self.images, self.base)
        prop.touch()
        with self.assertRaisesRegex(ValueError, 'property file'):
            layout.validate(self.images, self.base)

    def test_empty_sdk_is_rejected(self):
        (self.images / 'system/system/build.prop').write_text(
            'ro.system.build.version.release=15\nro.system.build.version.sdk=\n')
        with self.assertRaisesRegex(ValueError, 'version.sdk'):
            layout.validate(self.images, self.base)

    def test_erofs_added_for_each_mount_in_mixed_fstab(self):
        original = ('# retain comment\n'
                    'system /system_root erofs ro wait,logical,first_stage_mount\n'
                    'product /product ext4 ro,barrier=1,discard wait,logical,first_stage_mount\n'
                    '/dev/block/mapper/vendor_a /vendor ext4 ro,nosuid,nodev,data=ordered wait,logical\n'
                    '/dev/block/by-name/userdata /data f2fs rw,noatime wait,check\n')
        result = layout.configure_fstab(original, 'EROFS', {'system', 'product', 'vendor'})
        self.assertIn('product\t/product\terofs\tro\twait,logical,first_stage_mount\n', result)
        self.assertIn('/dev/block/mapper/vendor_a\t/vendor\terofs\tro,nosuid,nodev\twait,logical\n', result)
        self.assertIn('product /product ext4 ro,barrier=1,discard wait,logical,first_stage_mount\n', result)
        self.assertIn('/dev/block/by-name/userdata /data f2fs rw,noatime wait,check\n', result)
        self.assertTrue(result.startswith('# retain comment\n'))
        self.assertEqual(layout.configure_fstab(result, 'EROFS', {'system', 'product', 'vendor'}), result)

    def test_existing_erofs_alternative_is_not_duplicated(self):
        original = ('system /system_root erofs ro wait,logical\n'
                    'system /system_root ext4 ro,barrier=1 wait,logical\n')
        self.assertEqual(layout.configure_fstab(original, 'EROFS', {'system'}), original)

    def test_ext4_repacking_preserves_mount_from_erofs_only_fstab(self):
        original = 'system /system_root erofs ro,cache_strategy=readaround wait,logical\n'
        expected = 'system\t/system_root\text4\tro\twait,logical\n'
        self.assertEqual(layout.configure_fstab(original, 'EXT', {'system'}), expected)

    def test_ext4_repacking_uses_existing_ext4_alternative(self):
        original = ('system /system_root erofs ro wait,logical\n'
                    'system /system_root ext4 ro,barrier=1 wait,logical\n')
        expected = 'system /system_root ext4 ro,barrier=1 wait,logical\n'
        self.assertEqual(layout.configure_fstab(original, 'EXT', {'system'}), expected)

    def test_unselected_partitions_are_unchanged(self):
        original = 'vendor /vendor ext4 ro,barrier=1 wait,logical\n'
        self.assertEqual(layout.configure_fstab(original, 'EROFS', {'system'}), original)

    def test_discovers_default_hardware_and_odm_fstab_names(self):
        paths = [self.images / 'vendor/etc/fstab.default',
                 self.images / 'vendor/etc/fstab.sm8350', self.images / 'odm/etc/fstab.hardware']
        for path in paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('product /product ext4 ro,barrier=1 wait,logical\n')
        script = self.images / 'vendor/etc/fstab_notes.txt'
        script.write_text('This is not a filesystem table.\n')
        with contextlib.redirect_stdout(io.StringIO()):
            found = layout.configure_fstabs(self.images, 'EROFS', ['product'])
        self.assertEqual(set(found), set(paths))
        self.assertTrue(all('\terofs\t' in p.read_text() for p in paths))
        self.assertEqual(script.read_text(), 'This is not a filesystem table.\n')

    def test_no_image_fstab_keeps_stock_ramdisk_configuration(self):
        with contextlib.redirect_stdout(io.StringIO()) as log:
            found = layout.configure_fstabs(self.images, 'EROFS', ['system'])
        self.assertEqual(found, [])
        self.assertIn('keeping stock ramdisk', log.getvalue())


if __name__ == '__main__':
    unittest.main()
