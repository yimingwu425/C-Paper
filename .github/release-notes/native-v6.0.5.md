# C-Paper Native 6.0.5

C-Paper Native 6.0.5 is a native macOS workflow release focused on making download and update behavior clearer and more reliable in day-to-day use.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.5-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Added queue-wide HTTP 429 cooldown handling so bulk downloads wait and retry instead of cascading into large batches of failures.
- Surfaced the active download save directory in the Downloads page, with a direct `显示文件夹` action and clearer processed-versus-success summary text.
- Updated the native updater to show destination and progress while downloading, then auto-open the downloaded DMG and keep a manual-open hint if that open fails.
- Replaced the oversized subject menu with a searchable popover and kept the default subject state unselected unless the user has a saved last subject.

## Verification

- `swift test --jobs 1`
- `bash scripts/check_version_drift.sh`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

## Privacy And Disclaimer

C-Paper is a local desktop helper. It does not upload user data and does not own, host, or redistribute Cambridge International Education papers or mark schemes. Downloaded materials come from third-party public sources and remain subject to their original copyright and availability constraints.
