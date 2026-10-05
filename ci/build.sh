#!/usr/bin/env bash
# Run from a fresh Linux checkout; workflow inputs are passed as environment data.
set -euo pipefail

cd "$(dirname "$0")/.."
repository_dir=$(pwd)
[[ "${GITHUB_ACTIONS:-}" == true && "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
    echo 'This helper requires a Linux x86_64 GitHub Actions runner.' >&2
    exit 1
}

case "${REPACK_WITH_EXT4:-true}" in true|false) ;; *) echo 'Invalid EXT4 setting.' >&2; exit 1 ;; esac
case "${PACK_METHOD:-aosp}" in aosp|super) ;; *) echo 'Invalid pack method.' >&2; exit 1 ;; esac
export REPACK_WITH_EXT4="${REPACK_WITH_EXT4:-true}" PACK_METHOD="${PACK_METHOD:-aosp}"

# Preserve Xiaomi filenames for codename detection, but reject paths/shell syntax.
rom_filename() {
    python3 - "$1" <<'PY'
import re
import sys
from urllib.parse import urlsplit

url = sys.argv[1]
parts = urlsplit(url)
name = parts.path.rsplit('/', 1)[-1]
if (parts.scheme != 'https' or not parts.hostname or parts.username or parts.password
        or any(c.isspace() for c in url)
        or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.zip', name)):
    sys.exit('Expected an HTTPS OTA URL with a plain .zip filename.')
print(name)
PY
}

base_filename=$(rom_filename "${BASE_ROM_URL:?BASE_ROM_URL is required}")
donor_filename=$(rom_filename "${DONOR_ROM_URL:?DONOR_ROM_URL is required}")

python3 - <<'PY'
import os
from pathlib import Path

path = Path('bin/port_config')
settings = {'repack_with_ext4': os.environ['REPACK_WITH_EXT4'],
            'pack_method': os.environ['PACK_METHOD']}
lines = path.read_text(encoding='utf-8').splitlines()
for key, value in settings.items():
    if sum(line.startswith(key + '=') for line in lines) != 1:
        raise SystemExit('Missing or duplicate config key: ' + key)
    lines = [key + '=' + value if line.startswith(key + '=') else line for line in lines]
path.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
PY

download_rom() {
    local url=$1 directory=$2 filename=$3
    mkdir -p "$directory"
    aria2c --dir="$directory" --out="$filename" --continue=true \
        --auto-file-renaming=false --file-allocation=none \
        --max-tries=5 --retry-wait=15 --connect-timeout=30 --timeout=60 \
        --split=8 --max-connection-per-server=8 -- "$url"
    unzip -tq "$directory/$filename"
    unzip -Z1 "$directory/$filename" > "$directory/contents.txt"
    if ! grep -Fxq 'payload.bin' "$directory/contents.txt"; then
        echo "Expected payload.bin in $filename (official OTA ZIP required)." >&2
        exit 1
    fi
}

download_rom "$BASE_ROM_URL" .ci-downloads/base "$base_filename"
download_rom "$DONOR_ROM_URL" .ci-downloads/donor "$donor_filename"
df -h .

export PATH="$repository_dir/bin/Linux/x86_64:$repository_dir/otatools/bin:$PATH"
export LD_LIBRARY_PATH="$repository_dir/bin/Linux/x86_64/lib64:$repository_dir/otatools/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# port.sh releases only these downloaded archives and redundant extracted trees.
sudo env GITHUB_ACTIONS=true PORT_CI_CLEANUP=true LANG=C.UTF-8 \
    PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
    bash port.sh ".ci-downloads/base/$base_filename" ".ci-downloads/donor/$donor_filename"

# The original script has some nonfatal paths: never report success without a ZIP.
shopt -s nullglob
roms=(out/*.zip)
if (( ${#roms[@]} == 0 )); then
    echo 'No output ROM ZIP was produced.' >&2
    exit 1
fi
for rom in "${roms[@]}"; do
    unzip -tq "$rom"
done
(cd out && sha256sum -- *.zip > SHA256SUMS)
sudo chown -R "$(id -u):$(id -g)" out
df -h .
