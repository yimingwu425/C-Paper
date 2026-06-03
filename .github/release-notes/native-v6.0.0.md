# C-Paper Native 6.0.0

C-Paper Native 6.0.0 is a major native-backend release for macOS. The active product line is now the SwiftUI/AppKit app with a Swift-native backend.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.0-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Replaced the active Python bridge/backend with a Swift-native backend.
- Added modular backend layers for sources, parsing, networking, downloads, persistence, and migration.
- Added automatic source fallback across Frankcie, PapaCambridge, PastPapers, and EasyPaper.
- Added manual data source selection in Settings.
- Moved local app data to macOS Application Support with migration from old `~/.cie_cache` settings, favorites, and download history.
- Removed Python bridge packaging from the native DMG build.

## Main Features

- Search Cambridge International Education past papers by subject, year, and season.
- Preview PDFs inside the app.
- Group question papers, mark schemes, and related components.
- Build batch download queues across years, seasons, and paper numbers.
- Track download progress, completed items, failed items, retries, and cancellation state.
- Save local settings such as download directory, proxy URL, data source, rate, concurrency, duplicate-file handling, and favorite subjects.

## Architecture Note

This release is for the native macOS line:

- `macos/`: SwiftUI/AppKit desktop client and Swift-native backend
- `legacy/python-backend/`: archived Python bridge/backend reference
- `legacy/pywebview/`: archived legacy desktop shell

## Verification

The release workflow builds the native app, packages a standalone DMG, verifies the DMG, mounts it, checks the app bundle and Applications symlink, and then publishes this GitHub Release.

## Disclaimer

C-Paper is a local desktop search and download helper. It does not own, host, or redistribute Cambridge International Education papers. Data availability depends on the third-party source used by the app.
