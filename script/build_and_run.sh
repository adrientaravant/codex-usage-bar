#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CocoUsageBar"
DISPLAY_NAME="Coco Usage Bar"
BUNDLE_ID="com.slite.CocoUsageBar"
MIN_SYSTEM_VERSION="14.0"
CONFIGURATION="${CONFIGURATION:-release}"
SPARKLE_PUBLIC_KEY="4rcISDkst4dolr8z0BD2XUIaItwf2Wggi5GXwjKaNSw="
DEFAULT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-${DEFAULT_VERSION:-0.0.0-dev}}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  DETECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
  CODESIGN_IDENTITY="${DETECTED_IDENTITY:--}"
fi

if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  CONFIGURATION="debug"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build -c "$CONFIGURATION"
BUILD_BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
if [[ -d "$ROOT_DIR/Sources/CocoUsageBar/Resources" ]]; then
  ditto "$ROOT_DIR/Sources/CocoUsageBar/Resources" "$APP_RESOURCES"
fi
chmod +x "$APP_BINARY"

SPARKLE_FRAMEWORK="$BUILD_BIN_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  mkdir -p "$APP_FRAMEWORKS"
  cp -RP "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true
else
  echo "WARNING: Sparkle.framework not found at $SPARKLE_FRAMEWORK; app will not launch if it links Sparkle." >&2
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
  <string>$VERSION</string>
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
  <false/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT License</string>
</dict>
</plist>
PLIST

SPARKLE_FW="$APP_FRAMEWORKS/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  SPARKLE_V="$SPARKLE_FW/Versions/B"
  for nested in \
    "$SPARKLE_V/XPCServices/Installer.xpc" \
    "$SPARKLE_V/XPCServices/Downloader.xpc" \
    "$SPARKLE_V/Autoupdate" \
    "$SPARKLE_V/Updater.app"; do
    [[ -e "$nested" ]] && /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$nested" >/dev/null
  done
  /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$SPARKLE_FW" >/dev/null
fi
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build)
    ;;
  run)
    open_app
    ;;
  --print-snapshot|print-snapshot)
    "$APP_BINARY" --print-snapshot
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--print-snapshot|--debug|--logs|--verify]" >&2
    exit 2
    ;;
esac
