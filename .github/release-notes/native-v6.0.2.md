# C-Paper Native 6.0.2

C-Paper Native 6.0.2 is a Swift-native backend usability and parity hotfix for the 6.0 release line. It focuses on making fallback sources reachable from the app UI and aligning duplicate-download behavior with the archived Python backend.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.2-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Subject loading now participates in source fallback instead of depending only on Frankcie.
- EasyPaper and PastPapers can populate the subject list when Frankcie's subject API is unavailable.
- Search and Batch now allow manual 4-digit Cambridge subject-code entry, so users can still search when every subject-list provider is temporarily unavailable.
- Swift-native download history is now connected to successful downloads.
- Duplicate `skip` / `missing` modes now use download history like the archived Python backend.
- Settings text now matches the actual automatic source order: Frankcie, EasyPaper, PastPapers, PapaCambridge.
- Live source smoke tests now cover subject fallback and retry transient EasyPaper PDF handshake failures.

## Verification

- `swift test --jobs 1`
- `swift build`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
- `python3 -m pytest legacy/python-backend/tests`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

## Source Reliability

EasyPaper remains the primary non-Frankcie fallback verified with live PDF downloads. PastPapers remains best-effort because directory pages may be Cloudflare-challenged. PapaCambridge reports unavailable when Cloudflare blocks non-browser clients instead of attempting to bypass the challenge.
