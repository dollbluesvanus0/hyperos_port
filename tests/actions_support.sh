#!/usr/bin/env bash
set -euo pipefail

repository_dir=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$repository_dir/tmp"
fixture_root=$(mktemp -d "$repository_dir/tmp/actions-support.XXXXXX")
case "$fixture_root" in "$repository_dir"/tmp/actions-support.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$fixture_root"' EXIT
checks=0
assert() {
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

# Exercise the actual filename detection block with modern and legacy OTA names.
detection=$(sed -n '/^if \[ "$(echo $baserom |grep _multi_)"/,/^blue "正在检测ROM底包"/p' "$repository_dir/port.sh" | sed '$d')
for pair in \
    venus_global-ota_full-OS2.0.3.0.zip:venus \
    diting-ota_full-OS2.0.211.0.zip:diting \
    miui_VENUSGlobal_OS2.0.3.0.zip:VENUSGlobal \
    xiaomi.eu_multi_VENUS_OS2.0.3.0.zip:VENUS; do
    baserom=${pair%:*}
    eval "$detection"
    assert test "$device_code" = "${pair#*:}"
done

worker_settings=$(sed -n '/^payload_worker_args=()/,/^fi/p' "$repository_dir/port.sh")
GITHUB_ACTIONS=true
eval "$worker_settings"
assert test "${payload_worker_args[*]}" = '--workers 2'
GITHUB_ACTIONS=false
eval "$worker_settings"
assert test "${#payload_worker_args[@]}" = 0

# Cleanup must be opt-in and limited to CI-owned downloads, including symlinks.
source <(sed -n '/^ci_remove_downloaded_rom() {/,/^}/p' "$repository_dir/port.sh")
work_dir="$fixture_root"
mkdir -p "$work_dir/.ci-downloads/base"
archive="$work_dir/.ci-downloads/base/stock.zip"
printf stock > "$archive"
GITHUB_ACTIONS=true PORT_CI_CLEANUP=false ci_remove_downloaded_rom "$archive"
assert test -f "$archive"
GITHUB_ACTIONS=false PORT_CI_CLEANUP=true ci_remove_downloaded_rom "$archive"
assert test -f "$archive"
printf local > "$work_dir/local.zip"
GITHUB_ACTIONS=true PORT_CI_CLEANUP=true ci_remove_downloaded_rom "$work_dir/local.zip"
assert test -f "$work_dir/local.zip"
ln -s "$work_dir/local.zip" "$work_dir/.ci-downloads/base/link.zip"
GITHUB_ACTIONS=true PORT_CI_CLEANUP=true ci_remove_downloaded_rom "$work_dir/.ci-downloads/base/link.zip"
assert test -f "$work_dir/local.zip"
GITHUB_ACTIONS=true PORT_CI_CLEANUP=true ci_remove_downloaded_rom "$archive"
assert test ! -e "$archive"

# Run the Actions helper with fake downloads/build tools; no ROM network traffic.
mkdir -p "$fixture_root/harness/ci" "$fixture_root/harness/bin" "$fixture_root/tools"
cp "$repository_dir/ci/build.sh" "$fixture_root/harness/ci/"
cp "$repository_dir/ci/upload-pixeldrain.sh" "$fixture_root/harness/ci/"
cp "$repository_dir/bin/port_config" "$fixture_root/harness/bin/"
cat > "$fixture_root/harness/port.sh" <<'SH'
#!/usr/bin/env bash
[[ "$1" == .ci-downloads/base/venus_global-ota_full-test.zip ]] || exit 20
[[ "$2" == .ci-downloads/donor/diting-ota_full-test.zip ]] || exit 21
[[ "$PORT_CI_CLEANUP" == true ]] || exit 22
case "${TEST_FAILURE:-}" in build) exit 23 ;; no_output) exit 0 ;; esac
mkdir -p out
printf 'fixture output' > out/test.zip
SH
cat > "$fixture_root/tools/aria2c" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in --dir=*) directory=${arg#*=} ;; --out=*) filename=${arg#*=} ;; esac
done
printf 'fixture input' > "$directory/$filename"
SH
cat > "$fixture_root/tools/unzip" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == -Z1 ]]; then
    [[ "${TEST_FAILURE:-}" != no_payload ]] && echo payload.bin || echo wrong.bin
elif [[ "$2" == out/* && "${TEST_FAILURE:-}" == bad_output ]]; then
    exit 24
fi
SH
cat > "$fixture_root/tools/uname" <<'SH'
#!/usr/bin/env bash
[[ "$1" == -m ]] && echo x86_64 || echo Linux
SH
cat > "$fixture_root/tools/sudo" <<'SH'
#!/usr/bin/env bash
[[ "$1" == chown ]] && exit 0
exec "$@"
SH
cat > "$fixture_root/tools/python3" <<'SH'
#!/usr/bin/env bash
set -o pipefail
"${PYTHON_FOR_TESTS:-/usr/bin/python3}" "$@" | tr -d '\r'
SH
chmod +x "$fixture_root/tools/"*
export PATH="$fixture_root/tools:$PATH" GITHUB_ACTIONS=true
export BASE_ROM_URL='https://example.com/venus_global-ota_full-test.zip?token=value'
export DONOR_ROM_URL='https://example.com/diting-ota_full-test.zip'
export REPACK_WITH_EXT4=false PACK_METHOD=super
helper="$fixture_root/harness/ci/build.sh"
bash "$helper" > "$fixture_root/helper.log" 2>&1 || {
    cat "$fixture_root/helper.log" >&2
    exit 1
}
assert test -s "$fixture_root/harness/out/SHA256SUMS"
assert grep -Fxq repack_with_ext4=false "$fixture_root/harness/bin/port_config"
assert grep -Fxq pack_method=super "$fixture_root/harness/bin/port_config"
for failure in build no_output no_payload bad_output; do
    rm -rf "$fixture_root/harness/out"
    assert bash -c '! TEST_FAILURE="$1" bash "$2" > "$3" 2>&1' _ "$failure" "$helper" "$fixture_root/helper.log"
done
assert bash -c '! BASE_ROM_URL="http://example.com/stock.zip" bash "$1" > "$2" 2>&1' _ "$helper" "$fixture_root/helper.log"
assert bash -c '! PACK_METHOD="invalid" bash "$1" > "$2" 2>&1' _ "$helper" "$fixture_root/helper.log"

# Verify Pixeldrain responses, checksum matching and secret-free output offline.
cat > "$fixture_root/tools/curl" <<'SH'
#!/usr/bin/env bash
while (( $# )); do
    case "$1" in
        --output) response=$2; shift ;;
        --upload-file) rom=$2; shift ;;
        --user) [[ "$2" == :fixture-api-key ]] || exit 25; shift ;;
    esac
    shift
done
[[ "${TEST_FAILURE:-}" == http ]] && exit 22
[[ "$response" == /dev/null ]] && exit 0
size=$(wc -c < "$rom" | tr -d ' ')
hash=$(sha256sum "$rom" | cut -d ' ' -f 1)
case "${TEST_FAILURE:-}" in
    bad_hash) hash=invalid ;;
    bad_size) size=0 ;;
    no_id) printf '{"success":true}' > "$response"; exit 0 ;;
    api) printf '{"success":false,"value":"writing"}' > "$response"; exit 0 ;;
esac
printf '{"success":true,"id":"Ab1234xy","size":%s,"hash_sha256":"%s"}' "$size" "$hash" > "$response"
SH
chmod +x "$fixture_root/tools/curl"
upload_helper="$fixture_root/harness/ci/upload-pixeldrain.sh"
mkdir -p "$fixture_root/harness/out"
printf 'fixture ROM' > "$fixture_root/harness/out/test.zip"
export PIXELDRAIN_API_KEY=fixture-api-key GITHUB_STEP_SUMMARY="$fixture_root/summary.md"
bash "$upload_helper" --check
bash "$upload_helper" > "$fixture_root/upload.log" 2>&1
assert grep -Fq https://pixeldrain.com/u/Ab1234xy "$fixture_root/harness/pixeldrain-links.txt"
assert grep -Fq https://pixeldrain.com/u/Ab1234xy "$GITHUB_STEP_SUMMARY"
assert bash -c '! grep -Fq fixture-api-key "$1"' _ "$fixture_root/upload.log"
for failure in http api no_id bad_hash bad_size; do
    assert bash -c '! TEST_FAILURE="$1" bash "$2" > "$3" 2>&1' _ "$failure" "$upload_helper" "$fixture_root/upload.log"
done
assert bash -c '! PIXELDRAIN_API_KEY="" bash "$1" > "$2" 2>&1' _ "$upload_helper" "$fixture_root/upload.log"
printf 'PASS: %s Actions support checks\n' "$checks"
