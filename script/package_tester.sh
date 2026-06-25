#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CocoUsageBar"
DISPLAY_NAME="Coco Usage Bar"
BUNDLE_ID="com.slite.CocoUsageBar"
MIN_SYSTEM_VERSION="14.0"
SPARKLE_PUBLIC_KEY="4rcISDkst4dolr8z0BD2XUIaItwf2Wggi5GXwjKaNSw="
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
RELEASE_DIR="${RELEASE_DIR:-"$ROOT_DIR/../releases/v$APP_VERSION"}"
APP_BUNDLE="$RELEASE_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_STAGING="$RELEASE_DIR/dmg-staging"
DMG_PATH="$RELEASE_DIR/CocoUsageBar.dmg"
ZIP_PATH="$RELEASE_DIR/coco-usage-bar-$APP_VERSION.zip"
GUIDE_PATH="$RELEASE_DIR/READ ME FIRST - How to open.txt"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
fi
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="-"
  echo "No Apple Development identity found; falling back to ad-hoc signing." >&2
fi

cd "$ROOT_DIR"
swift build -c release --arch arm64 --arch x86_64
BUILD_BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BIN_DIR/$APP_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -d "$ROOT_DIR/Sources/CocoUsageBar/Resources" ]]; then
  ditto "$ROOT_DIR/Sources/CocoUsageBar/Resources" "$APP_RESOURCES"
fi

SPARKLE_FRAMEWORK="$BUILD_BIN_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  mkdir -p "$APP_FRAMEWORKS"
  cp -RP "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true
else
  echo "ERROR: Sparkle.framework not found at $SPARKLE_FRAMEWORK." >&2
  exit 1
fi

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
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>https://github.com/adrientaravant/coco-usage-bar/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>3600</integer>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT License</string>
</dict>
</plist>
PLIST

SPARKLE_FW="$APP_FRAMEWORKS/Sparkle.framework"
SPARKLE_V="$SPARKLE_FW/Versions/B"
for nested in \
  "$SPARKLE_V/XPCServices/Installer.xpc" \
  "$SPARKLE_V/XPCServices/Downloader.xpc" \
  "$SPARKLE_V/Autoupdate" \
  "$SPARKLE_V/Updater.app"; do
  [[ -e "$nested" ]] && /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$nested" >/dev/null
done
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$SPARKLE_FW" >/dev/null
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

cat >"$GUIDE_PATH" <<'GUIDE'
Coco Usage Bar - how to open it
===============================

This is an internal build signed like Slite Agent Bar: Apple Development signed,
but not Apple-notarized. macOS may warn once on first install.

1. Open the DMG.
2. Drag Coco Usage Bar.app to Applications.
3. In Applications, right-click Coco Usage Bar.app, choose Open, then confirm Open.
4. It lives in the menu bar, not the Dock.

If macOS still blocks it, run:
  xattr -dr com.apple.quarantine "/Applications/Coco Usage Bar.app"
GUIDE

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
shasum -a 256 "$DMG_PATH" >"$DMG_PATH.sha256"
shasum -a 256 "$ZIP_PATH" >"$ZIP_PATH.sha256"

printf '%s\n' "$RELEASE_DIR"
