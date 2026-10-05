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
info=$(mktemp .ci-downloads/pixeldrain-info.XXXXXX)
trap 'rm -f -- "$response" "$info"' EXIT
reuse=false
case "${1:-}" in
    --reuse) reuse=true ;;
    '') ;;
    *) echo 'Usage: upload-pixeldrain.sh [--check|--reuse]' >&2; exit 1 ;;
esac
# Recovery can reuse the exact previously uploaded ROM. Account data stays local.
if [[ "$reuse" == true ]]; then
    curl --fail --silent --show-error --connect-timeout 30 --max-time 120 \
        --user ":$PIXELDRAIN_API_KEY" --output "$response" https://pixeldrain.com/api/user/files
fi
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
    file_id=''
    if [[ "$reuse" == true ]]; then
        file_id=$(python3 ci/pixeldrain.py find "$response" "$rom")
    fi
    if [[ -z "$file_id" ]]; then
        echo "Uploading $filename to Pixeldrain..."
        curl --fail --silent --show-error --retry 3 --retry-delay 15 \
            --connect-timeout 30 --max-time 7200 --user ":$PIXELDRAIN_API_KEY" \
            --upload-file "$rom" --output "$info" \
            "https://pixeldrain.com/api/file/$encoded_name"
        file_id=$(python3 ci/pixeldrain.py id "$info")
        echo "Pixeldrain returned file ID: $file_id; verifying stored content."
    else
        echo "Found the same ROM on Pixeldrain: $file_id; verifying stored content."
    fi
    # Always obtain authoritative metadata, even when PUT returns only an ID.
    curl --fail --silent --show-error --retry 3 --retry-delay 5 \
        --connect-timeout 30 --max-time 120 --user ":$PIXELDRAIN_API_KEY" \
        --output "$info" "https://pixeldrain.com/api/file/$file_id/info"
    python3 ci/pixeldrain.py verify "$info" "$rom" "$file_id" > /dev/null
    url="https://pixeldrain.com/u/$file_id"
    printf '%s  %s\n' "$filename" "$url" | tee -a "$links_file"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '\nPixeldrain: [%s](%s)\n' "$filename" "$url" >> "$GITHUB_STEP_SUMMARY"
    fi
done
