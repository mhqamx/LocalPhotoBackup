#!/usr/bin/env bash
set -euo pipefail

APP_NAME="IPhoneBackup"
DISPLAY_NAME="iPhone / iPad 相册备份"
BUNDLE_ID="com.local.IPhoneBackup"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
TMP_DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.tmp.dmg"

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME"
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$DMG_ROOT" "$DMG_PATH" "$TMP_DMG_PATH"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCameraUsageDescription</key>
  <string>用于访问通过 USB 连接的 iPhone 或 iPad 相册内容并导出到你选择的位置。</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>用于读取 iPhone 或 iPad 相册中的照片和视频。</string>
  <key>NSRemovableVolumesUsageDescription</key>
  <string>用于将照片和视频导出到移动硬盘或 U 盘。</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDRW \
  "$TMP_DMG_PATH"

hdiutil convert "$TMP_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

rm -rf "$DMG_ROOT" "$TMP_DMG_PATH"

echo "Created $DMG_PATH"
