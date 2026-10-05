#!/usr/bin/env bash
# Exercise the actual bundled EROFS tools before downloading multi-GB ROMs.
set -euo pipefail
cd "$(dirname "$0")/.."
repository_dir=$(pwd)
export PATH="$repository_dir/bin/Linux/x86_64:$repository_dir/otatools/bin:$PATH"
export LD_LIBRARY_PATH="$repository_dir/bin/Linux/x86_64/lib64:$repository_dir/otatools/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
tools_dir="$repository_dir/bin/Linux/x86_64"
source functions.sh
mkdir -p tmp
fixture_root=$(mktemp -d "$repository_dir/tmp/image-tools.XXXXXX")
case "$fixture_root" in "$repository_dir"/tmp/image-tools.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/source/vendor/etc" "$fixture_root/images"
printf 'vendor /vendor ext4 ro,barrier=1,discard wait,logical,first_stage_mount\n' > "$fixture_root/source/vendor/etc/fstab.default"
mkfs.erofs "$fixture_root/images/vendor.img" "$fixture_root/source/vendor" > "$fixture_root/mkfs.log" 2>&1 || {
    cat "$fixture_root/mkfs.log" >&2; exit 1;
}
extract_partition "$fixture_root/images/vendor.img" "$fixture_root/images" || exit 1
test -f "$fixture_root/images/vendor/etc/fstab.default"
test -f "$fixture_root/images/config/vendor_fs_config"
python3 bin/rom_layout.py fstabs "$fixture_root/images" --format EROFS --partitions vendor
grep -q $'vendor\t/vendor\terofs\tro\twait,logical,first_stage_mount' "$fixture_root/images/vendor/etc/fstab.default"
echo 'PASS: real EROFS image creation, extraction, metadata and fstab configuration'
