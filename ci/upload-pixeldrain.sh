#!/usr/bin/env bash
# Pixeldrain PUT API: https://pixeldrain.com/api
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${PIXELDRAIN_API_KEY:-}" ]]; then
    echo 'Add the PIXELDRAIN_API_KEY repository secret, or disable Upload to Pixeldrain.' >&2
    exit 1
fi

# Check authentication before spending hours building a ROM. Do not log user data.
if [[ "${1:-}" == --check ]]; then
    curl --fail --silent --show-error --connect-timeout 30 --max-time 60 \
        --user ":$PIXELDRAIN_API_KEY" --output /dev/null https://pixeldrain.com/api/user
    exit 0
fi

shopt -s nullglob
roms=(out/*.zip)
(( ${#roms[@]} > 0 )) || { echo 'No ROM ZIP to upload.' >&2; exit 1; }
mkdir -p .ci-downloads
response=$(mktemp .ci-downloads/pixeldrain-response.XXXXXX)
trap 'rm -f -- "$response"' EXIT
links_file=pixeldrain-links.txt
: > "$links_file"

for rom in "${roms[@]}"; do
    filename=$(basename "$rom")
    encoded_name=$(python3 - "$filename" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
)
    echo "Uploading $filename to Pixeldrain..."
    curl --fail --silent --show-error --retry 3 --retry-delay 15 \
        --connect-timeout 30 --max-time 7200 --user ":$PIXELDRAIN_API_KEY" \
        --upload-file "$rom" --output "$response" \
        "https://pixeldrain.com/api/file/$encoded_name"
    file_id=$(python3 - "$response" "$rom" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
file_id = result.get('id', '')
if result.get('success') is not True or not re.fullmatch(r'[A-Za-z0-9_-]+', file_id):
    sys.exit('Pixeldrain did not return a successful upload and file ID.')
rom = Path(sys.argv[2])
if result.get('size') != rom.stat().st_size:
    sys.exit('Pixeldrain file size does not match the local ROM.')
digest = hashlib.sha256()
with rom.open('rb') as stream:
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(block)
if result.get('hash_sha256') != digest.hexdigest():
    sys.exit('Pixeldrain SHA256 does not match the local ROM.')
print(file_id)
PY
)
    url="https://pixeldrain.com/u/$file_id"
    printf '%s  %s\n' "$filename" "$url" | tee -a "$links_file"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '\nPixeldrain: [%s](%s)\n' "$filename" "$url" >> "$GITHUB_STEP_SUMMARY"
    fi
done
