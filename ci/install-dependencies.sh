#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
    echo 'Run this installer with sudo on Linux x86_64.' >&2
    exit 1
}
apt-get update
apt-get install -y --no-install-recommends \
    aria2 python3 python3-protobuf busybox zip unzip p7zip-full \
    openjdk-21-jre-headless zstd bc android-sdk-libsparse-utils \
    xmlstarlet openssl e2fsprogs zipalign curl
chmod +x bin/Linux/x86_64/* otatools/bin/*
