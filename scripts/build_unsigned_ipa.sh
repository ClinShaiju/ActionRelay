#!/usr/bin/env bash
# Build an UNSIGNED ActionRelay.ipa (macOS only). CI uses this; run locally to
# reproduce. The output is not installable until signed by Feather with your
# distribution cert + the two .mobileprovision files (PROJECT.md §9).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "need xcodegen: brew install xcodegen"; exit 1; }

xcodegen generate

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

rm -rf Payload ActionRelay-unsigned.ipa
mkdir Payload
cp -R "$APP" Payload/
zip -qry ActionRelay-unsigned.ipa Payload
rm -rf Payload
echo "wrote ActionRelay-unsigned.ipa"
