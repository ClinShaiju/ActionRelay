#!/usr/bin/env bash
# Build an UNSIGNED ActionRelay.ipa (macOS only). CI uses this; run locally to
# reproduce. The output is not installable until signed by Feather with your
# distribution cert + the two .mobileprovision files (PROJECT.md §9).
#
# Usage: build_unsigned_ipa.sh [spec.yml] [output.ipa]
#   spec   - XcodeGen spec (default project.yml; project.idevice.yml links idevice)
#   output - .ipa filename (default ActionRelay-unsigned.ipa)
set -euo pipefail
cd "$(dirname "$0")/.."

SPEC="${1:-project.yml}"
OUT="${2:-ActionRelay-unsigned.ipa}"

command -v xcodegen >/dev/null || { echo "need xcodegen: brew install xcodegen"; exit 1; }

xcodegen generate --spec "$SPEC"

xcodebuild build \
  -project ActionRelay.xcodeproj \
  -scheme ActionRelay \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS=""

APP="build/Build/Products/Release-iphoneos/ActionRelay.app"
[ -d "$APP" ] || { echo "build produced no .app at $APP"; exit 1; }

rm -rf Payload "$OUT"
mkdir Payload
cp -R "$APP" Payload/
zip -qry "$OUT" Payload
rm -rf Payload
echo "wrote $OUT"
