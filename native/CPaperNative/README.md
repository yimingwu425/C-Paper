# C-Paper Native (Moved)

The native macOS project is now rooted at the repository top level.

The active implementation is the root `Package.swift` plus `macos/`, where the SwiftUI/AppKit app, Swift-native backend, and active Swift tests now live.

Active build scripts live in `scripts/` and `scripts/lib/`.

## Run

```bash
swift run CPaperNative
```

## Test

```bash
swift test --jobs 1
```

Archived Python bridge/backend code lives under `legacy/python-backend/`. The old pywebview shell lives under `legacy/pywebview/`.
