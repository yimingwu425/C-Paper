# C-Paper Native 6.0.1

C-Paper Native 6.0.1 is a native-backend hotfix for the 6.0 release line. It focuses on making third-party source behavior honest and source-specific.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.1-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Replaced generic third-party HTML source skeletons with independent PapaCambridge, PastPapers, and EasyPaper providers.
- Added EasyPaper support for its encrypted `dir_v3` API and refreshes EasyPaper download tokens immediately before downloading.
- Added PastPapers support for its real CAIE `relPath` / static PDF structure, with best-effort probing when directory pages are Cloudflare-challenged.
- Added PapaCambridge session-path handling and direct PDF verification, while reporting a clear unavailable state when Cloudflare blocks non-browser clients.
- Changed automatic fallback order to Frankcie, EasyPaper, PastPapers, then PapaCambridge.
- Manual source selection now reports unavailable sources clearly instead of returning empty success.
- Tightened native DMG packaging by clearing extended attributes around ad hoc signing and strict verification.

## Verification

- `swift test --jobs 1`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
- `swift build`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

## Source Reliability

EasyPaper is the primary non-Frankcie fallback verified with live PDF downloads. PastPapers is best-effort because directory pages may be Cloudflare-challenged, though static PDF URLs can still be usable. PapaCambridge currently blocks non-browser HTTP clients in live testing and reports unavailable instead of attempting to bypass Cloudflare.
