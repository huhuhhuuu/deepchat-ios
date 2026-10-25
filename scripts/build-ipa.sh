#!/bin/bash
#
# DeepChat · 一键打包 IPA（需要 macOS + Xcode 15 以上）
#
# 用法：
#   ./scripts/build-ipa.sh                       # 自动签名，生成到 build/ipa
#   TEAM_ID=ABCDE12345 ./scripts/build-ipa.sh    # 指定开发者团队
#   METHOD=ad-hoc ./scripts/build-ipa.sh         # 导出方式：app-store / ad-hoc / development
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="DeepChat.xcodeproj"
SCHEME="DeepChat"
CONFIG="Release"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/DeepChat.xcarchive"
EXPORT_DIR="$BUILD_DIR/ipa"
METHOD="${METHOD:-development}"
TEAM="${TEAM_ID:-}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "✗ 打包 IPA 需要 macOS 与 Xcode，请在 Mac 上运行此脚本。" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "✗ 未找到 xcodebuild，请先安装 Xcode（App Store）并执行: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

echo "==> 清理旧产物"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 生成工程文件（新增 Swift 文件后会自动收录）"
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/gen_xcode_project.py || true
fi

SIGN_ARGS=()
if [[ -n "$TEAM" ]]; then
  SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM")
fi

echo "==> 归档 (Archive)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  "${SIGN_ARGS[@]}" \
  -allowProvisioningUpdates \
  archive

echo "==> 生成 ExportOptions.plist"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>${METHOD}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
	<key>destination</key>
	<string>export</string>
	$( [[ -n "$TEAM" ]] && printf '<key>teamID</key>\n\t<string>%s</string>' "$TEAM" )
</dict>
</plist>
PLIST

echo "==> 导出 IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

echo ""
echo "✅ 完成："
find "$EXPORT_DIR" -name "*.ipa" -maxdepth 1 -print
