#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CPaperNative"
DISPLAY_NAME="C-Paper"
BUNDLE_ID="com.yimingwu.CPaperNative"
VERSION="6.0.3"
MIN_SYSTEM_VERSION="14.0"
CONFIGURATION="${CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ROOT="${TMPDIR:-/tmp}/cpaper-native-dmg-$VERSION"
STAGING_DIR="$BUILD_ROOT/dmg_staging"
DMG_RW="$BUILD_ROOT/$DISPLAY_NAME.rw.dmg"
DMG_BACKGROUND="$BUILD_ROOT/dmg-background.png"
DMG_MOUNT="/Volumes/$DISPLAY_NAME"
CLEAN_APP_DIR="$BUILD_ROOT/clean_app"
CLEAN_APP_BUNDLE="$CLEAN_APP_DIR/$APP_NAME.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_OUT="$DIST_DIR/C-Paper-Native-$VERSION-standalone-$(date +%Y%m%d).dmg"

source "$ROOT_DIR/scripts/lib/native_dmg_helpers.sh"

stop_running_app
rm -rf "$BUILD_ROOT" "$APP_BUNDLE" "$DMG_OUT"
mkdir -p "$DIST_DIR" "$BUILD_ROOT"

echo "[1/5] Building Swift $CONFIGURATION binary..."
cd "$PACKAGE_DIR"
SWIFT_BINARY="$(find "$PACKAGE_DIR/.build" -path "*/$CONFIGURATION/$APP_NAME" -type f -perm -111 | head -1 || true)"
if [ "${SKIP_SWIFT_BUILD:-0}" = "1" ] && [ -n "$SWIFT_BINARY" ] && [ -x "$SWIFT_BINARY" ]; then
  echo "Skipping Swift build and reusing current binary: $SWIFT_BINARY"
elif [ -n "$SWIFT_BINARY" ] && [ -x "$SWIFT_BINARY" ] && ! find "$PACKAGE_DIR/macos/Sources" -type f -newer "$SWIFT_BINARY" | grep -q .; then
  echo "Reusing current Swift binary: $SWIFT_BINARY"
else
  swift build -c "$CONFIGURATION" --product "$APP_NAME"
  SWIFT_BINARY="$(find "$PACKAGE_DIR/.build" -path "*/$CONFIGURATION/$APP_NAME" -type f -perm -111 | head -1 || true)"
fi
if [ -z "$SWIFT_BINARY" ] || [ ! -x "$SWIFT_BINARY" ]; then
  echo "Missing Swift binary for configuration: $CONFIGURATION" >&2
  exit 1
fi

echo "[2/5] Assembling app bundle..."
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$SWIFT_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ -f "$ROOT_DIR/assets/icon.icns" ]; then
  ditto --noextattr --norsrc "$ROOT_DIR/assets/icon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "[3/5] Signing app bundle ad hoc..."
clear_bundle_metadata "$APP_BUNDLE"
rm -rf "$CLEAN_APP_DIR"
mkdir -p "$CLEAN_APP_DIR"
ditto --noextattr --norsrc "$APP_BUNDLE" "$CLEAN_APP_BUNDLE"
rm -rf "$APP_BUNDLE"
ditto --noextattr --norsrc "$CLEAN_APP_BUNDLE" "$APP_BUNDLE"
clear_bundle_metadata "$APP_BUNDLE"
codesign_best_effort "$APP_BUNDLE"

echo "[4/5] Creating DMG..."
rm -rf "$STAGING_DIR" "$DMG_RW"
hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true
mkdir -p "$STAGING_DIR"
hdiutil detach "/Volumes/$DISPLAY_NAME" >/dev/null 2>&1 || true
ditto --noextattr --norsrc "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
clear_bundle_metadata "$STAGING_DIR/$APP_NAME.app"
verify_codesign_best_effort "$STAGING_DIR/$APP_NAME.app"

create_dmg_background "$DMG_BACKGROUND"

hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  -size 650m \
  "$DMG_RW"

hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen -mountpoint "$DMG_MOUNT" >/dev/null
wait_for_path "$DMG_MOUNT/$APP_NAME.app"
wait_for_path "$DMG_MOUNT/Applications"
trap cleanup_mount EXIT

mkdir -p "$DMG_MOUNT/.background"
cp "$DMG_BACKGROUND" "$DMG_MOUNT/.background/background.png"
if [ -f "$ROOT_DIR/assets/icon.icns" ]; then
  ditto --noextattr --norsrc "$ROOT_DIR/assets/icon.icns" "$DMG_MOUNT/.VolumeIcon.icns"
  SetFile -a C "$DMG_MOUNT" || true
fi

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISPLAY_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 780, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {185, 205}
    try
      set position of item "Applications" of container window to {475, 205}
    end try
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

wait_for_path "$DMG_MOUNT/$APP_NAME.app"
clear_bundle_metadata "$DMG_MOUNT/$APP_NAME.app"
verify_codesign_best_effort "$DMG_MOUNT/$APP_NAME.app"

sync
cleanup_mount
trap - EXIT

hdiutil convert "$DMG_RW" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_OUT" \
  -ov

if [ -f "$ROOT_DIR/assets/icon.icns" ]; then
  set_custom_file_icon "$DMG_OUT" "$ROOT_DIR/assets/icon.icns"
fi

echo "[5/5] Verifying artifact..."
clear_bundle_metadata "$APP_BUNDLE"
VERIFY_APP="$BUILD_ROOT/verify/$APP_NAME.app"
rm -rf "$BUILD_ROOT/verify"
mkdir -p "$BUILD_ROOT/verify"
ditto --noextattr --norsrc "$APP_BUNDLE" "$VERIFY_APP"
verify_codesign_best_effort "$VERIFY_APP"
spctl --assess --type execute "$APP_BUNDLE" >/dev/null 2>&1 || true

APP_SIZE="$(du -sh "$APP_BUNDLE" | cut -f1)"
DMG_SIZE="$(du -sh "$DMG_OUT" | cut -f1)"
echo "App: $APP_SIZE  $APP_BUNDLE"
echo "DMG: $DMG_SIZE  $DMG_OUT"
