#!/usr/bin/env bash
set -euo pipefail
repository_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$repository_dir/functions.sh"
mkdir -p "$repository_dir/tmp"
fixture_root=$(mktemp -d "$repository_dir/tmp/partition-extraction.XXXXXX")
case "$fixture_root" in "$repository_dir"/tmp/partition-extraction.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$fixture_root"' EXIT
checks=0
assert() {
    if ! "$@"; then printf 'FAIL: %s\n' "$*" >&2; exit 1; fi
    checks=$((checks + 1))
}

# Reproduce the failed build: no fstab.qcom and an empty packing list. Execute
# the real extraction stage against fake partition images, not pre-created dirs.
unpack_stage=$(awk '
    /^green .*Starting extract portrom partition/ { capture = 1; next }
    capture && /^rm -rf config/ { exit }
    capture { print }
' "$repository_dir/port.sh")
(
    cd "$fixture_root"
    work_dir=$PWD
    mkdir -p build/portrom/images
    for part in system product system_ext mi_ext; do
        printf image > "build/portrom/images/$part.img"
    done
    super_list=''
    port_partition='system product system_ext mi_ext'
    is_eu_rom=false portrom_type=payload
    extract_partition() {
        [[ -f "$1" ]] || return 1
        local name=${1##*/}
        mkdir -p "$2/${name%.img}"
        printf '%s\n' "${name%.img}" >> extraction.log
    }
    eval "$unpack_stage"
)
for part in system product system_ext mi_ext; do
    assert grep -Fxq "$part" "$fixture_root/extraction.log"
done

# Extractor errors and false success must retain the input and emit diagnostics.
tools_dir="$fixture_root/tools with spaces"
mkdir -p "$tools_dir"
printf '#!/bin/bash\necho erofs\n' > "$tools_dir/gettype"
chmod +x "$tools_dir/gettype"
images="$fixture_root/images with spaces"
mkdir -p "$images"
printf image > "$images/vendor.img"
if (extract.erofs() { echo 'fixture extractor failure'; return 9; }; extract_partition "$images/vendor.img" "$images") > "$fixture_root/failure.log" 2>&1; then
    printf 'FAIL: extractor failure was ignored\n' >&2; exit 1
fi
assert test -f "$images/vendor.img"
assert grep -Fq 'fixture extractor failure' "$fixture_root/failure.log"
if (extract.erofs() { return 0; }; extract_partition "$images/vendor.img" "$images") > "$fixture_root/empty.log" 2>&1; then
    printf 'FAIL: empty extractor output was accepted\n' >&2; exit 1
fi
assert test -f "$images/vendor.img"
assert grep -Fq 'Extractor did not create' "$fixture_root/empty.log"
(
    extract.erofs() { mkdir -p "$images/vendor/etc"; }
    extract_partition "$images/vendor.img" "$images"
)
assert test -d "$images/vendor/etc"
assert test ! -e "$images/vendor.img"
printf 'PASS: %d partition extraction checks\n' "$checks"
