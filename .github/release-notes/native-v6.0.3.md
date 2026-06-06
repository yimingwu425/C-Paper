# C-Paper Native 6.0.3

C-Paper Native 6.0.3 combines the Swift-native download retry hotfix with the refreshed native UI and settings experience.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.3-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## Release And Install Notes

- Native releases use the `validate/package/release` GitHub Actions flow in `.github/workflows/build.yml`.
- The GitHub Release publish step is tag-only: it runs for `v*` tag pushes after validation and packaging pass.
- Manual `workflow_dispatch` runs validation and packaging, uploads a DMG artifact, and does not publish a GitHub Release.
- Native builds default to ad hoc signing. Optional Developer ID/notary signing and notarization are enabled only when the documented Apple signing secrets are all configured.
- The project site remains external-link pending; GitHub Releases are the canonical download location for this native line.

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

## Privacy And Disclaimer

C-Paper is a local desktop helper. It does not upload user data and does not own, host, or redistribute Cambridge International Education papers or mark schemes. Downloaded materials come from third-party public sources and remain subject to their original copyright and availability constraints.

## Data Source Reliability

FrankCIE remains the primary source. EasyPaper remains the primary non-FrankCIE fallback verified with live PDF downloads. PastPapers remains best-effort because directory pages may be Cloudflare-challenged. PapaCambridge reports unavailable when Cloudflare blocks non-browser clients instead of attempting to bypass the challenge.

These privacy/disclaimer/data source reliability notes reflect the app boundary: C-Paper reports source availability honestly and does not bypass third-party anti-automation challenges.
