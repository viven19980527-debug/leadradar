#!/usr/bin/env bash
# build-ipa.sh — 在任何一台 Mac 上一条命令出 .ipa
#
# 用法：
#   bash scripts/build-ipa.sh                    # 只出未签名 ipa（Sideloadly 后续签）
#   TEAM_ID=ABCDE12345 bash scripts/build-ipa.sh # 顺便用你的开发者证书签名导出
#
# 前置：装 Xcode（App Store 或 developer.apple.com 下载），并执行一次
#   sudo xcodebuild -license accept
#   sudo xcode-select -s /Applications/Xcode.app
set -euo pipefail

cd "$(dirname "$0")/.."
PROJ="TrackerSweep"
SCHEME="TrackerSweep"
OUT="dist"
mkdir -p "$OUT"

echo "==> Xcode 版本"
xcodebuild -version

echo "==> 结构自检"
python3 tools/check_pbxproj.py || { echo "工程文件有问题，先修"; exit 1; }

echo "==> 编译（Release / iphoneos / 不签名）"
xcodebuild \
  -project "$PROJ.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee "$OUT/build.log"

APP="build/Build/Products/Release-iphoneos/$PROJ.app"
if [ ! -d "$APP" ]; then
  echo
  echo "!! 没有产物。看这些行："
  grep -nE "(error|错误):" "$OUT/build.log" | head -30
  exit 1
fi

echo "==> 打包未签名 ipa"
rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "$OUT/$PROJ-unsigned.ipa" Payload
rm -rf Payload
ls -lh "$OUT/$PROJ-unsigned.ipa"

# ---- 可选：真机签名导出 ----
if [ -n "${TEAM_ID:-}" ]; then
  echo "==> 用 TEAM_ID=$TEAM_ID 归档并导出已签名 ipa"
  cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>development</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>compileBitcode</key><false/>
    <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
EOF
  xcodebuild \
    -project "$PROJ.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -archivePath "$OUT/$PROJ.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates \
    archive 2>&1 | tee "$OUT/archive.log"

  xcodebuild -exportArchive \
    -archivePath "$OUT/$PROJ.xcarchive" \
    -exportPath "$OUT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -allowProvisioningUpdates 2>&1 | tee "$OUT/export.log"

  ls -lh "$OUT"/*.ipa
fi

echo
echo "==> 完成"
echo "  未签名: $OUT/$PROJ-unsigned.ipa   → 用 Sideloadly / AltStore 签并安装"
[ -n "${TEAM_ID:-}" ] && echo "  已签名: $OUT/$PROJ.ipa"
