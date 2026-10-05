#!/usr/bin/env bash
# Reproduce publishing a ZIP created by the root-run ROM packer.
set -euo pipefail
cd "$(dirname "$0")/.."
repository_dir=$(pwd)
[[ "$(uname -s)" == Linux && "$(id -u)" != 0 ]] || {
    echo 'Run this check as the Linux Actions runner, with sudo available.' >&2
    exit 1
}
mkdir -p tmp
fixture_root=$(mktemp -d "$repository_dir/tmp/output-permissions.XXXXXX")
case "$fixture_root" in "$repository_dir"/tmp/output-permissions.*) ;; *) exit 1 ;; esac
trap 'sudo rm -rf -- "$fixture_root"' EXIT
mkdir -p "$fixture_root/out"
printf 'fixture ROM data\n' > "$fixture_root/input.txt"
(cd "$fixture_root" && zip -q out/test.zip input.txt)
sudo chown -R root:root "$fixture_root/out"
sudo chmod 755 "$fixture_root/out"
test ! -w "$fixture_root/out"
publish_stage=$(awk '
    /^# Allow the runner to validate/ { capture = 1; next }
    capture && /^df -h \./ { exit }
    capture { print }
' ci/build.sh)
test -n "$publish_stage"
(
    cd "$fixture_root"
    roms=(out/*.zip)
    eval "$publish_stage"
    test -s out/SHA256SUMS
    (cd out && sha256sum --check SHA256SUMS)
)
echo 'PASS: checksums published from a root-owned ROM output directory'
