#!/usr/bin/env bash
# Download + extract the pinned idevice xcframework into vendor/ (not committed —
# 213 MB). Provides IDevice.xcframework with lockdown/RSD/tunnel/heartbeat/
# syslog_relay FFI. See docs/integration.md.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="v0.1.64"
SHA256="b8250402a23c850f80b9be1d4add309aae6c935ee6a797b73616e4d8f170be5d"
ASSET="idevice-xcframework-${VERSION}.zip"
URL="https://github.com/jkcoxson/idevice/releases/download/${VERSION}/${ASSET}"

mkdir -p vendor
if [ -d "vendor/IDevice.xcframework" ]; then
  echo "vendor/IDevice.xcframework already present"; exit 0
fi

echo "Downloading ${ASSET}…"
curl -fL "$URL" -o "vendor/${ASSET}"

echo "Verifying sha256…"
echo "${SHA256}  vendor/${ASSET}" | sha256sum -c -

echo "Extracting…"
unzip -q "vendor/${ASSET}" -d vendor/_x
# The zip contains swift/IDevice.xcframework
mv vendor/_x/swift/IDevice.xcframework vendor/IDevice.xcframework
rm -rf vendor/_x "vendor/${ASSET}"
echo "vendor/IDevice.xcframework ready"
