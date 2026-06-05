# C-Paper Native 6.0.3

C-Paper Native 6.0.3 combines the Swift-native download retry hotfix with the refreshed native UI and settings experience.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.3-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Download retries now wait for the circuit breaker recovery timeout before failed items are requeued.
- Retry handling also waits when the breaker opens exactly at the end of a failure batch, before a `rate_limit` item has appeared.
- Subject selection now uses the same glass-style control language as the rest of the app.
- Removed Python-bridge-era local/native backend readiness prompts and backend availability gating from the UI.
- Settings now includes About, manual update checking, startup update checking, and in-app DMG downloads for newer GitHub Releases.
- The user-facing source name now displays as `FrankCIE`.
- The native DMG build script waits for mounted app and Applications paths before Finder layout operations.

## Verification

- `swift test --jobs 1`
- `swift build`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

## Source Reliability

FrankCIE remains the primary source. EasyPaper remains the primary non-FrankCIE fallback verified with live PDF downloads. PastPapers remains best-effort because directory pages may be Cloudflare-challenged. PapaCambridge reports unavailable when Cloudflare blocks non-browser clients instead of attempting to bypass the challenge.
