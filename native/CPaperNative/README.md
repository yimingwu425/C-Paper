# C-Paper Native

Native macOS SwiftUI front end for C-Paper.

## Run

```bash
cd native/CPaperNative
swift run CPaperNative
```

## Test

```bash
cd native/CPaperNative
swift test
cd ../..
pytest
```

The native app uses `native/bridge/cpaper_bridge.py` to call the existing Python backend.
