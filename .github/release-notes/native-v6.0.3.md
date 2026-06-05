# C-Paper Native 6.0.3

C-Paper Native 6.0.3 is a Swift-native backend hotfix for the 6.0 release line. It fixes batch downloads getting stuck when the circuit breaker opens and retries are attempted before the recovery window has elapsed.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-6.0.3-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What Changed

- Download retries now wait for the circuit breaker recovery timeout before failed items are requeued.
- Retry handling also waits when the breaker opens exactly at the end of a failure batch, before a `rate_limit` item has appeared.
- The production recovery timeout remains 30 seconds; tests can inject a shorter timeout.
- Swift tests cover both breaker-open retry recovery and the threshold-boundary retry case.

## Verification

- `swift test --filter DownloadManagerTests/testDownloadManagerWaitsForCircuitBreakerRecoveryBeforeRetrying --jobs 1`
- `swift test --filter DownloadManagerTests/testDownloadManagerWaitsWhenCircuitBreakerOpensAtRetryBoundary --jobs 1`
- `swift build --product CPaperNative`
- `swift test --jobs 1`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

## Scope

This release is limited to the native Swift download/retry path and release metadata for 6.0.3. It does not change the archived Python/legacy implementation.
