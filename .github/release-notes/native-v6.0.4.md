# C-Paper Native 6.0.4

C-Paper Native 6.0.4 is a native macOS polish release focused on making the menu bar feel like a real first-class desktop app.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.4-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Added a complete Chinese macOS menu bar with `C-Paper`, `文件`, `编辑`, `显示`, `窗口`, and `帮助`.
- Routed menu actions into the ready-state app flow for settings, update checking, route switching, diagnostics, and support access.
- Installed the AppKit main menu during startup before the first window becomes interactive, while keeping the existing manual `NSApplication` lifecycle.
- Unified save-directory validation so menu actions and app behavior share the same path usability rules and Chinese error messaging.
- Added AppKit menu, startup, and binding tests, then validated the release build and final menu-bar QA on macOS.

## Verification

- `swift test --jobs 1`
- `bash scripts/check_version_drift.sh`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

## Privacy And Disclaimer

C-Paper is a local desktop helper. It does not upload user data and does not own, host, or redistribute Cambridge International Education papers or mark schemes. Downloaded materials come from third-party public sources and remain subject to their original copyright and availability constraints.
