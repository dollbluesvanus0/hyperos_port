#!/bin/bash
set -euo pipefail

repository_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$repository_dir/functions.sh"
mkdir -p "$repository_dir/tmp"
fixture_root=$(mktemp -d "$repository_dir/tmp/mi-ext-merge.XXXXXX")
# Only clean up the fixture directory created inside this checkout.
case "$fixture_root" in "$repository_dir"/tmp/mi-ext-merge.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$fixture_root"' EXIT
checks=0
assert() {
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

images="$fixture_root/images with spaces"
mkdir -p "$images"/{mi_ext/{etc,system/{app,lib64},system_ext/priv-app,product/app},system/system/app,system_ext,product/etc,config}
printf 'base\n' > "$images/system/system/app/shared.apk"
printf 'keep\n' > "$images/system/system/app/base.apk"
printf 'donor\n' > "$images/mi_ext/system/app/shared.apk"
printf 'hidden\n' > "$images/mi_ext/system/.hidden"
printf 'library\n' > "$images/mi_ext/system/lib64/library.so"
printf 'extension\n' > "$images/mi_ext/system_ext/priv-app/extension.apk"
printf 'product\n' > "$images/mi_ext/product/app/product.apk"
printf '# keep this comment\nro.keep=base\nro.shared=base\nro.shared=duplicate' > "$images/product/etc/build.prop"
printf '# donor comment\r\n#ro.disabled=true\r\nro.shared=donor\r\nro.mi.os.version.incremental=OS3.0.1.0.TEST\r\nro.new=value=with=equals' > "$images/mi_ext/etc/build.prop"
printf 'system/system/app/shared.apk 0 0 0644\nsystem/system/app/base.apk 0 0 0644\n' > "$images/config/system_fs_config"
printf '/system/system/app/shared\\.apk u:object_r:old_file:s0\n' > "$images/config/system_file_contexts"
printf 'mi_ext/system/app/shared.apk 1000 2000 0755 capabilities=0x1\nmi_ext/system_ext/priv-app/extension.apk 0 0 0644\nmi_ext/product/app/product.apk 0 0 0644\n' > "$images/config/mi_ext_fs_config"
printf '/mi_ext/system/app/shared\\.apk u:object_r:system_file:s0\n/mi_ext/system(/.*)? u:object_r:system_file:s0\n/mi_ext/system_ext/priv-app/extension\\.apk u:object_r:system_file:s0\n/mi_ext/product/app/product\\.apk u:object_r:system_file:s0\n' > "$images/config/mi_ext_file_contexts"

merge_mi_ext "$images"
assert grep -Fxq donor "$images/system/system/app/shared.apk"
assert grep -Fxq keep "$images/system/system/app/base.apk"
assert test -f "$images/system/system/.hidden"
assert test -f "$images/system/system/lib64/library.so"
assert test -f "$images/system_ext/priv-app/extension.apk"
assert test -f "$images/product/app/product.apk"
assert test ! -e "$images/system/system/system"
for partition in system system_ext product; do
    assert test ! -e "$images/mi_ext/$partition"
done
assert test -f "$images/mi_ext/etc/build.prop"
assert grep -Fxq '# keep this comment' "$images/product/etc/build.prop"
assert grep -Fxq ro.keep=base "$images/product/etc/build.prop"
assert grep -Fxq ro.shared=donor "$images/product/etc/build.prop"
assert test "$(grep -c '^ro.shared=' "$images/product/etc/build.prop")" -eq 1
assert grep -Fxq ro.new=value=with=equals "$images/product/etc/build.prop"
assert grep -Fxq ro.mi.os.version.incremental=OS3.0.1.0.TEST "$images/product/etc/build.prop"
assert test "$(grep -c '^ro.disabled=' "$images/product/etc/build.prop" || true)" -eq 0
assert grep -Fxq 'system/system/app/shared.apk 1000 2000 0755 capabilities=0x1' "$images/config/system_fs_config"
assert test "$(grep -c '^system/system/app/shared.apk ' "$images/config/system_fs_config")" -eq 1
assert grep -Fxq 'system_ext/priv-app/extension.apk 0 0 0644' "$images/config/system_ext_fs_config"
assert grep -Fxq 'product/app/product.apk 0 0 0644' "$images/config/product_fs_config"
assert grep -Fxq '/system/system/app/shared\.apk u:object_r:system_file:s0' "$images/config/system_file_contexts"
assert grep -Fxq '/system/system(/.*)? u:object_r:system_file:s0' "$images/config/system_file_contexts"
assert test "$(grep -Fc '/system/system/app/shared\.apk ' "$images/config/system_file_contexts")" -eq 1
assert grep -Fxq '/system_ext/priv-app/extension\.apk u:object_r:system_file:s0' "$images/config/system_ext_file_contexts"
assert grep -Fxq '/product/app/product\.apk u:object_r:system_file:s0' "$images/config/product_file_contexts"

# Repeating the merge must not duplicate properties or change the result.
cp "$images/product/etc/build.prop" "$fixture_root/expected.prop"
merge_mi_ext "$images"
assert cmp "$fixture_root/expected.prop" "$images/product/etc/build.prop"

# The mi_ext property merge runs after copying its product tree.
images="$fixture_root/product overlay"
mkdir -p "$images/mi_ext"/{product/etc,etc}
printf 'ro.shared=tree\nro.tree=keep\n' > "$images/mi_ext/product/etc/build.prop"
printf 'ro.shared=mi_ext\n' > "$images/mi_ext/etc/build.prop"
merge_mi_ext "$images"
assert grep -Fxq ro.shared=mi_ext "$images/product/etc/build.prop"
assert grep -Fxq ro.tree=keep "$images/product/etc/build.prop"

# Empty/missing property files and absent mi_ext remain valid inputs.
printf '' > "$images/mi_ext/etc/build.prop"
cp "$images/product/etc/build.prop" "$fixture_root/expected.prop"
merge_mi_ext "$images"
assert cmp "$fixture_root/expected.prop" "$images/product/etc/build.prop"
assert merge_mi_ext "$fixture_root/no mi_ext"

# A copy failure must not remove the donor files.
images="$fixture_root/copy failure"
mkdir -p "$images/mi_ext/system/app"
printf 'keep\n' > "$images/mi_ext/system/app/keep.apk"
if (cp() { return 1; }; merge_mi_ext "$images") >/dev/null 2>&1; then
    printf 'FAIL: merge succeeded after a failed copy\n' >&2
    exit 1
fi
assert test -f "$images/mi_ext/system/app/keep.apk"

# Exercise the real donor extraction loop with image tools stubbed out. The base
# partition list deliberately omits mi_ext; payload, EU and fastboot all need it.
unpack_stage=$(awk '
    /^green .*Starting extract portrom partition/ { capture = 1; next }
    capture && /^rm -rf config/ { exit }
    capture { print }
' "$repository_dir/port.sh")
assert test -n "$unpack_stage"
for format in payload eu fastboot; do
    stage="$fixture_root/unpack $format"
    mkdir -p "$stage/build/portrom/images"/{system,system_ext,product}
    (
        cd "$stage"
        work_dir=$PWD
        super_list='system product system_ext'
        is_eu_rom=false
        portrom_type=$format
        [[ "$format" == eu ]] && is_eu_rom=true
        python3() {
            [[ "$1" == bin/lpunpack.py && "$2" == -p && "$3" == mi_ext_a ]] || return 1
            printf 'image\n' > "$5/mi_ext_a.img"
        }
        extract_partition() {
            [[ "$1" == "$work_dir/build/portrom/images/mi_ext.img" ]] || return 1
            printf 'extracted\n' > "$work_dir/extraction.log"
            mkdir -p "$2/mi_ext"/{etc,system/app}
            printf 'donor\n' > "$2/mi_ext/system/app/donor.apk"
            printf 'ro.stage=donor\n' > "$2/mi_ext/etc/build.prop"
        }
        eval "$unpack_stage"
        merge_mi_ext "$work_dir/build/portrom/images"
    )
    assert grep -Fxq extracted "$stage/extraction.log"
    assert test -f "$stage/build/portrom/images/system/system/app/donor.apk"
    assert grep -Fxq ro.stage=donor "$stage/build/portrom/images/product/etc/build.prop"
done

printf 'PASS: %d checks\n' "$checks"
