#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XCODE_PROJECT="TrackerSweep.xcodeproj"
export XCODE_TARGET="TrackerSweep"
export XCODE_SCHEME="TrackerSweep"

set -euo pipefail
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version


set -euo pipefail
python3 -m venv build/check-env
build/check-env/bin/python -m pip -q install PyYAML==6.0.3
build/check-env/bin/python tools/check_pbxproj.py
build/check-env/bin/python tools/check_sources.py
build/check-env/bin/python tools/check_ci.py


set -euo pipefail
mkdir -p dist
xcodebuild \
  -project "$XCODE_PROJECT" \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  ARCHS=arm64 \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee dist/build.log


set -euo pipefail
APP="build/Build/Products/Release-iphoneos/${XCODE_TARGET}.app"
if [ ! -d "$APP" ]; then
  echo "=== 编译失败 ==="
  grep -nE "(error|错误):" dist/build.log | head -40 || true
  exit 1
fi
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist"
ls -l "$APP/AppIcon60x60@2x.png" 2>/dev/null || echo "(图标已编入 Assets.car)"
rm -rf Payload && mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "dist/${XCODE_TARGET}-unsigned.ipa" Payload
rm -rf Payload
ls -lh dist/*.ipa
shasum -a 256 dist/*.ipa > dist/TrackerSweep-unsigned.ipa.sha256
python3 tools/write_build_provenance.py

