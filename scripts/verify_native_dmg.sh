#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH=""
APP_NAME="${APP_NAME:-CPaperNative.app}"
VOLUME_NAME="${VOLUME_NAME:-C-Paper}"
MOUNT_POINT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dmg)
      DMG_PATH="$2"
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

cleanup_mount() {
  if [ -n "$MOUNT_POINT" ] && mount | grep -q "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
}

trap cleanup_mount EXIT

if [ -z "$DMG_PATH" ]; then
  DMG_PATH="$(find "$DIST_DIR" -maxdepth 1 -name 'C-Paper-Native-*-standalone-*.dmg' -print | LC_ALL=C sort | tail -1 || true)"
fi

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
  echo "Missing DMG artifact to verify." >&2
  exit 1
fi

hdiutil verify "$DMG_PATH"

MOUNT_OUTPUT="$(hdiutil attach -nobrowse -readonly "$DMG_PATH")"
printf '%s\n' "$MOUNT_OUTPUT"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"

if [ -z "$MOUNT_POINT" ]; then
  echo "Failed to determine mounted DMG volume path." >&2
  exit 1
fi

test -d "$MOUNT_POINT/$APP_NAME"
test -L "$MOUNT_POINT/Applications"
test -f "$MOUNT_POINT/.background/background.png"
codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME"

echo "Verified DMG: $DMG_PATH"
echo "Mounted volume: $MOUNT_POINT"
