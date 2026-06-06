#!/usr/bin/env bash

stop_running_app() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    for _ in {1..30}; do
      if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        return
      fi
      sleep 0.2
    done
    pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
  fi
}

clear_bundle_metadata() {
  local target="$1"

  xattr -cr "$target" 2>/dev/null || true
  find "$target" -depth -exec xattr -c {} \; 2>/dev/null || true
  find "$target" -depth -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
  find "$target" -depth -exec xattr -d com.apple.provenance {} \; 2>/dev/null || true
  find "$target" -depth -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true
  find "$target" -depth -exec xattr -d com.apple.macl {} \; 2>/dev/null || true
}

signing_identity_configured() {
  [ -n "${CPAPER_CODESIGN_IDENTITY:-}" ]
}

notarization_configured() {
  signing_identity_configured && [ -n "${CPAPER_NOTARY_KEYCHAIN_PROFILE:-}" ]
}

current_signing_mode() {
  if signing_identity_configured; then
    printf '%s\n' "Developer ID"
  else
    printf '%s\n' "ad hoc"
  fi
}

sign_app_bundle() {
  local target="$1"
  local codesign_error="$BUILD_ROOT/codesign-error.log"

  clear_bundle_metadata "$target"
  if signing_identity_configured; then
    echo "Using Developer ID identity: $CPAPER_CODESIGN_IDENTITY"
    if ! codesign \
      --force \
      --deep \
      --options runtime \
      --timestamp \
      --sign "$CPAPER_CODESIGN_IDENTITY" \
      "$target" 2>"$codesign_error"; then
      clear_bundle_metadata "$target"
      if ! codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$CPAPER_CODESIGN_IDENTITY" \
        "$target"; then
        cat "$codesign_error" >&2
        return 1
      fi
    fi
  elif ! codesign --force --deep --sign - "$target" 2>"$codesign_error"; then
    clear_bundle_metadata "$target"
    if ! codesign --force --deep --sign - "$target"; then
      cat "$codesign_error" >&2
      echo "Warning: ad hoc codesign failed for $target; continuing with unsigned bundle." >&2
    fi
  fi
  clear_bundle_metadata "$target"
}

notarize_dmg_if_configured() {
  local target="$1"

  if notarization_configured; then
    echo "Submitting DMG for notarization with profile: $CPAPER_NOTARY_KEYCHAIN_PROFILE"
    xcrun notarytool submit "$target" \
      --keychain-profile "$CPAPER_NOTARY_KEYCHAIN_PROFILE" \
      --wait
    echo "Stapling notarization ticket to: $target"
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
    return
  fi

  if [ -n "${CPAPER_NOTARY_KEYCHAIN_PROFILE:-}" ] && ! signing_identity_configured; then
    echo "Warning: CPAPER_NOTARY_KEYCHAIN_PROFILE is set without CPAPER_CODESIGN_IDENTITY; skipping notarization." >&2
  fi
}

verify_codesign_best_effort() {
  local target="$1"
  local verify_target="$target"
  local temp_verify_dir=""

  for _ in {1..3}; do
    clear_bundle_metadata "$target"
    if [ "$target" != "$APP_BUNDLE" ]; then
      temp_verify_dir="$BUILD_ROOT/codesign_verify"
      rm -rf "$temp_verify_dir"
      mkdir -p "$temp_verify_dir"
      verify_target="$temp_verify_dir/$(basename "$target")"
      ditto --noextattr --norsrc "$target" "$verify_target"
      clear_bundle_metadata "$verify_target"
    fi
    if codesign --verify --deep --strict "$verify_target" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done
  echo "Warning: strict codesign verification failed for $target; continuing." >&2
}

wait_for_path() {
  local target="$1"

  for _ in {1..50}; do
    if [ -e "$target" ]; then
      return
    fi
    sleep 0.1
  done

  echo "Missing expected path: $target" >&2
  return 1
}

create_dmg_background() {
  local output="$1"
  local swift_file="$BUILD_ROOT/create_dmg_background.swift"

  cat >"$swift_file" <<'SWIFT'
import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 660, height: 420)
let image = NSImage(size: size)

func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(calibratedWhite: 0.16, alpha: 1), alignment: NSTextAlignment = .center, width: CGFloat = 560) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(in: NSRect(x: point.x, y: point.y, width: width, height: size + 10), withAttributes: attributes)
}

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.978, blue: 1.0, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.76, green: 0.88, blue: 1.0, alpha: 0.74),
    NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
])!
glow.draw(in: NSRect(x: 120, y: 70, width: 420, height: 280), angle: 0)

let card = NSBezierPath(roundedRect: NSRect(x: 38, y: 34, width: 584, height: 352), xRadius: 28, yRadius: 28)
NSColor(calibratedWhite: 1.0, alpha: 0.82).setFill()
card.fill()
NSColor(calibratedRed: 0.78, green: 0.84, blue: 0.92, alpha: 0.45).setStroke()
card.lineWidth = 1
card.stroke()

drawText("C-Paper", at: NSPoint(x: 50, y: 315), size: 28, weight: .semibold, color: NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.28, alpha: 1))
drawText("拖入 Applications 完成安装", at: NSPoint(x: 50, y: 282), size: 17, weight: .medium, color: NSColor(calibratedRed: 0.23, green: 0.36, blue: 0.55, alpha: 1))

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 265, y: 196))
arrow.line(to: NSPoint(x: 395, y: 196))
arrow.move(to: NSPoint(x: 374, y: 217))
arrow.line(to: NSPoint(x: 397, y: 196))
arrow.line(to: NSPoint(x: 374, y: 175))
NSColor(calibratedRed: 0.20, green: 0.50, blue: 1.0, alpha: 0.72).setStroke()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.stroke()

drawText("将左侧应用拖到右侧文件夹", at: NSPoint(x: 50, y: 76), size: 14, weight: .medium, color: NSColor(calibratedRed: 0.30, green: 0.39, blue: 0.52, alpha: 1))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render DMG background")
}
try png.write(to: URL(fileURLWithPath: output))
SWIFT

  swift "$swift_file" "$output"
}

set_custom_file_icon() {
  local target="$1"
  local icon="$2"

  osascript >/dev/null <<APPLESCRIPT || true
use framework "AppKit"
use scripting additions
set targetPath to "$target"
set iconPath to "$icon"
set iconImage to current application's NSImage's alloc()'s initWithContentsOfFile:iconPath
if iconImage is not missing value then
  (current application's NSWorkspace's sharedWorkspace()'s setIcon:iconImage forFile:targetPath options:0)
end if
APPLESCRIPT
}

cleanup_mount() {
  if mount | grep -q "on $DMG_MOUNT "; then
    hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || hdiutil detach "$DMG_MOUNT" -force >/dev/null 2>&1 || true
  fi
}
