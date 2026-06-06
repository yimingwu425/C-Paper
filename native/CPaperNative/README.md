# C-Paper Native (Moved)

The native macOS project is now rooted at the repository top level.

The active implementation is the root `Package.swift` plus `macos/`, where the SwiftUI/AppKit app and Swift-native backend now live.

## Run

```bash
swift run CPaperNative
```

## Test

```bash
swift test
```

Archived Python bridge/backend code, when needed for historical reference, lives under `legacy/python-backend/`.
