# Plan: C-Paper Download and Update Experience Fix

**Generated**: 2026-06-08

## Overview

Fix four user-visible problems in the native macOS app: bulk downloads fail aggressively after HTTP 429, the download destination is hard to discover, update downloads do not clearly show progress/location or auto-open the DMG, and the subject picker menu becomes too tall. Keep the current SwiftUI/AppKit architecture and visual style; do not touch `legacy/`.

## Prerequisites

- Work from `/Users/yimingwu/Documents/C-Paper`.
- Read `AGENTS.md`, `docs/PROJECT_INDEX.md`, and `docs/WORK_LOG.md` before implementation.
- Use Swift Package Manager validation: `swift test --jobs 1`.
- External docs checked for planning:
  - RFC 9110 `Retry-After` semantics for HTTP retry delay handling.
  - Apple Developer Documentation for SwiftUI popover-style presentation, `NSWorkspace.open(_:)`, and URLSession async byte transfer.
- After code/config changes, append a concise entry to `docs/WORK_LOG.md`.

## Implementation Decisions

- Treat HTTP 429 as a recoverable queue-wide cooldown event, not as ordinary per-file failure.
- Clamp retry delays to 5-120 seconds; when no valid `Retry-After` is present, use 30 seconds in production and inject a short value in tests.
- When a worker sees 429, set a shared request gate before any worker dequeues more work. 429 cooldown takes priority over circuit-breaker recovery to avoid double waiting.
- Keep existing `maxRetries = 3` and circuit breaker behavior; add 429-specific messages and cooldown before retry.
- Use real byte progress only on the default shared transfer path. Existing test-only `DownloadWriter` can remain status-based.
- Auto-open the downloaded update DMG after a successful update download. If auto-open fails, keep the update as downloaded and show a clear manual-open hint.
- Replace only the long subject picker with a searchable popover/list. Leave short settings menus on the existing `GlassMenuField`.
- Do not let parallel workers edit `docs/WORK_LOG.md`; final integration owns one consolidated work-log entry.

## Dependency Graph

```text
T1 ──┐
     ├── T5 ──┐
T2 ──┘        │
              ├── T9 ── T10
T3 ── T7 ─────┤
              │
T4 ── T8 ─────┘
T6 ───────────┘
```

## Tasks

### T1: HTTP 429 Retry Metadata

- **depends_on**: []
- **location**: `macos/Sources/CPaperNativeApp/Backend/Networking/NetworkClient.swift`, `macos/Sources/CPaperNativeApp/Backend/Networking/HTTPFileTransferClient.swift`, `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift`
- **description**: Extend `NetworkClientError.rateLimited` to include `retryAfter: TimeInterval?`. Parse `Retry-After` from HTTP responses as seconds first, then HTTP-date using an injectable `now` provider for tests. Invalid headers, negative seconds, and past dates return `nil`; oversized future values are returned raw here and clamped in T5. Keep localized descriptions user-readable and update all switch/catch sites.
- **validation**: Unit tests prove 429 without header yields `retryAfter == nil`, numeric header yields expected seconds, future HTTP-date yields expected seconds with fixed `now`, past/invalid values yield `nil`, and 429 still removes partial files.
- **status**: Completed
- **log**:
  - 2026-06-08: Added optional `retryAfter` metadata to HTTP 429 errors, parsed numeric and HTTP-date `Retry-After`, and covered invalid/past values plus partial-file cleanup in tests.
  - RED: focused transfer tests initially failed on missing `retryAfter`/`nowProvider`.
  - GREEN: `swift test --jobs 1 --filter 'ModelTests|UpdateServiceTests|HTTPFileTransferClientTests|SubjectPickerLogicTests'`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Backend/Networking/NetworkClient.swift`
  - `macos/Sources/CPaperNativeApp/Backend/Networking/HTTPFileTransferClient.swift`
  - `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift`

### T2: Download Item Real Progress Model

- **depends_on**: []
- **location**: `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift`, `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift`, `macos/Tests/CPaperNativeTests/ModelTests.swift`
- **description**: Add optional `progressFraction` to `DownloadTaskItem` with a default of `nil`. Make `progress` prefer `progressFraction` clamped to 0...1, otherwise preserve the current status-derived progress behavior. Keep Codable compatibility.
- **validation**: Existing model tests still compile with old initializers, and a new test verifies progress override/clamping.
- **status**: Completed
- **log**:
  - 2026-06-08: Added optional `progressFraction` to `DownloadTaskItem`, preserved legacy initializer behavior, and made `progress` prefer clamped real progress when present.
  - RED: `ModelTests/testDownloadTaskProgressUsesFractionWhenAvailable` failed before the new initializer argument existed.
  - GREEN: `swift test --jobs 1 --filter 'ModelTests|UpdateServiceTests|HTTPFileTransferClientTests|SubjectPickerLogicTests'`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift`
  - `macos/Tests/CPaperNativeTests/ModelTests.swift`

### T3: Update Destination and Open Injection Contract

- **depends_on**: []
- **location**: `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift`, `macos/Sources/CPaperNativeApp/Models/UpdateModels.swift`, `macos/Sources/CPaperNativeApp/State/AppModel.swift`, `macos/Tests/CPaperNativeTests/UpdateServiceTests.swift`, `macos/Tests/CPaperNativeTests/ModelTests.swift`
- **description**: Add `UpdateService.destinationURL(for:)`, change `UpdateStatus.downloading` to carry `destinationURL: URL?`, and add a narrow `openDownloadedFile: (URL) -> Bool` dependency to `AppModel` defaulting to `NSWorkspace.shared.open`. Keep this separate from RootView's generic URL opener.
- **validation**: Tests verify destination path construction, downloading status includes the destination before bytes finish, injected `openDownloadedFile` captures the final DMG URL without opening Finder, and an injected `false` return is observable by T7 without losing the downloaded URL.
- **status**: Completed
- **log**:
  - 2026-06-08: Added `UpdateService.destinationURL(for:)` and routed update downloads through the shared destination builder.
  - Extended `UpdateStatus.downloading` with `destinationURL` plus a `destinationURL` accessor that also resolves downloaded files.
  - Added `AppModel` `openDownloadedFile` injection, a narrow `openDownloadedUpdateFile()` helper, and backend facade access to the update destination.
  - Added a one-line compile shim in `SettingsInfoSections.swift` so the expanded enum payload still builds before T7 updates the update UI.
  - RED: update/model tests initially failed on missing destination and opener APIs.
  - GREEN: `swift test --jobs 1 --filter 'ModelTests|UpdateServiceTests|HTTPFileTransferClientTests|SubjectPickerLogicTests'`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift`
  - `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift`
  - `macos/Sources/CPaperNativeApp/Models/UpdateModels.swift`
  - `macos/Sources/CPaperNativeApp/State/AppModel.swift`
  - `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift`
  - `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift`
  - `macos/Tests/CPaperNativeTests/UpdateServiceTests.swift`
  - `macos/Tests/CPaperNativeTests/ModelTests.swift`

### T4: Subject Picker Filtering Helper

- **depends_on**: []
- **location**: `macos/Sources/CPaperNativeApp/Models/CPaperModels.swift` or a small adjacent model/helper file, `macos/Tests/CPaperNativeTests/ModelTests.swift`
- **description**: Add a pure helper for searchable subject picker behavior: filter by subject code or display name, preserve code-sorted ordering, return an empty list for no matches, and provide small reducer-style helpers for “select subject clears manual code” and “valid 4-digit manual code clears selection”.
- **validation**: Unit tests cover code search, name search, empty query, empty result, selection clearing manual code, and manual 4-digit input clearing selection.
- **status**: Completed
- **log**:
  - 2026-06-08: Added pure `SubjectPickerLogic` helper for code/name filtering with code-sorted results.
  - Added reducer-style helpers for subject selection/manual-code interaction.
  - Added unit tests for code search, name search, empty query, empty result, selection clearing manual code, and valid manual code clearing selection.
  - GREEN: `swift test --jobs 1 --filter 'ModelTests|UpdateServiceTests|HTTPFileTransferClientTests|SubjectPickerLogicTests'`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Models/SubjectPickerLogic.swift`
  - `macos/Tests/CPaperNativeTests/SubjectPickerLogicTests.swift`

### T5: DownloadManager 429 Cooldown Gate and Byte Progress

- **depends_on**: [T1, T2]
- **location**: `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift`, `macos/Sources/CPaperNativeApp/Backend/Downloads/RateLimiter.swift`, `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift`, `macos/Tests/CPaperNativeTests/DownloadTestSupport.swift`
- **description**: Add a shared cooldown gate for `NetworkClientError.rateLimited`. Store `nextAllowedRequestAt`/equivalent inside the actor, have every worker check the gate before dequeueing or starting a request, and have any 429 update the gate immediately. Cooldown pauses new requests during the current worker round, not only between retry rounds. When both 429 cooldown and circuit-breaker recovery exist, wait for the later safe instant once and show “服务器限流，等待后自动重试…”. Update `SharedTransferWriter` to accept a progress callback and write progress into the matching `DownloadTaskItem`.
- **validation**: Tests cover 429 with retry delay, 429 without retry delay using injected short default, concurrent workers stop issuing new requests while the gate is active, no mass final failures after recoverable 429, progress updates during shared transfer, and existing cancellation/retry tests still pass.
- **status**: Completed
- **log**:
  - 2026-06-08: Added a shared 429 cooldown gate inside `DownloadManager`, including current-round worker blocking, later-of cooldown/circuit-breaker waiting, and the Chinese retry-wait message.
  - Extended `SharedTransferWriter` with a progress callback and wrote byte progress into `DownloadTaskItem.progressFraction` for shared transfers.
  - RED: `swift test --jobs 1 --filter DownloadManagerTests`.
  - GREEN: `swift test --jobs 1 --filter DownloadManagerTests`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift`
  - `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift`
  - `macos/Tests/CPaperNativeTests/DownloadTestSupport.swift`

### T6: Download Page Destination and Honest Summary

- **depends_on**: [T2]
- **location**: `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift`, `macos/Sources/CPaperNativeApp/State/AppModel.swift`, `macos/Tests/CPaperNativeTests/ModelTests.swift`
- **description**: Show the active save directory on the download page and add a “显示文件夹” action using existing `model.revealSaveDirectory()`. Rename/adjust summary copy so 100% means processed, while success/failure counts remain explicit.
- **validation**: Existing model directory tests pass; add a focused test/helper assertion for all-skipped or all-failed summary wording if a testable summary helper is introduced. Manual UI check confirms destination text is visible in Downloads and the Finder action uses the configured save directory.
- **status**: Completed
- **log**:
  - 2026-06-08: Downloads page now shows the configured save directory and adds a `显示文件夹` action wired to `model.revealSaveDirectory()`.
  - Rewrote the queue summary so 100% means processed while success/failure/cancelled/skipped counts stay explicit.
  - Added focused `DownloadQueueSummary` assertions for all-skipped and all-failed wording.
  - GREEN: `swift test --jobs 1 --filter 'ModelTests|AppMenuCommandCenterTests|UpdateServiceTests'`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift`
  - `macos/Tests/CPaperNativeTests/ModelTests.swift`

### T7: Update Download UX and Auto-Open

- **depends_on**: [T3]
- **location**: `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift`, `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift`, `macos/Sources/CPaperNativeApp/Views/RootView.swift`, `macos/Tests/CPaperNativeTests/ModelTests.swift`, `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`
- **description**: Set update status to downloading with destination URL before starting transfer, preserve destination URL through progress callbacks, auto-open the final DMG through injected `openDownloadedFile`, and show save location in the settings/update UI. During downloading, show the target directory/filename only; do not expose “打开 DMG” until the final file exists. If auto-open returns false, keep `.downloaded(url)` and set a user-visible hint/error that the DMG is downloaded but must be opened manually. Update menu-command tests for the new enum shape.
- **validation**: Tests verify progress status retains the destination URL, successful download triggers exactly one open call for the DMG, open failure preserves downloaded URL and surfaces manual-open guidance, and downloading state never offers an open action for a missing final file. Manual startup-update flow shows progress/location.
- **status**: Completed
- **log**:
  - 2026-06-08: Update downloads now clear stale errors at start, preserve the target DMG path through progress callbacks, and auto-open the downloaded DMG through the injected opener.
  - Auto-open failure keeps `.downloaded(url)` and surfaces `更新 DMG 已下载，但自动打开失败，请在设置中手动打开。`.
  - Settings now shows the update destination directory and DMG filename while downloading and after completion.
  - GREEN: `swift test --jobs 1 --filter 'ModelTests|AppMenuCommandCenterTests|UpdateServiceTests'`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift`
  - `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift`
  - `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`
  - `macos/Tests/CPaperNativeTests/ModelTests.swift`

### T8: Searchable Subject Picker UI

- **depends_on**: [T4]
- **location**: `macos/Sources/CPaperNativeApp/Views/SearchControls.swift`, `macos/Sources/CPaperNativeApp/Views/BatchFilterPanel.swift`, `macos/Sources/CPaperNativeApp/Views/SearchView.swift`
- **description**: Replace the subject `Menu + Picker` with a glass-styled button plus popover containing a search field and scrollable list backed by the T4 helper. Reuse existing `GlassInputShell`/`GlassTextField` styling where practical; do not change short menus in settings.
- **validation**: Manual UI check confirms the picker no longer covers the app, search filters by code/name, selection updates Search and Batch pages, and manual code fallback still works.
- **status**: Completed
- **log**:
  - 2026-06-08: Replaced the subject `Menu + Picker` with a glass button and fixed-size searchable popover in `SearchControls.swift`.
  - Popover uses `SubjectPickerLogic` for code/name filtering, keeps selection/manual-code fallback behavior, and avoids the old app-covering tall menu.
  - reason_not_testable: SwiftUI popover presentation and shared binding behavior do not have a stable unit-test seam in the current target.
  - Validation: `swift build --jobs 1`.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Views/SearchControls.swift`

### T9: Work Log and Focused Regression Sweep

- **depends_on**: [T5, T6, T7, T8]
- **location**: `docs/WORK_LOG.md`, relevant changed tests
- **description**: As the single integration owner, append one concise work-log entry summarizing the download, update, and picker fixes. Parallel implementation agents should not edit `docs/WORK_LOG.md`; they should fill their task `log` fields or report notes for T9 to consolidate. Run focused tests for changed domains before the full suite.
- **validation**: `swift test --jobs 1 --filter 'DownloadManagerTests|DownloadDestinationBuilderTests|HTTPFileTransferClientTests|UpdateServiceTests|ModelTests|AppMenuCommandCenterTests'` passes, plus any new helper-specific test class added by T4.
- **status**: Completed
- **log**:
  - 2026-06-08: Added one consolidated work-log entry covering download 429 recovery, download/update destination visibility, update DMG auto-open behavior, and searchable subject picker UI.
  - GREEN: `swift test --jobs 1 --filter 'DownloadManagerTests|DownloadDestinationBuilderTests|HTTPFileTransferClientTests|UpdateServiceTests|ModelTests|AppMenuCommandCenterTests|SubjectPickerLogicTests'` passed with 79 executed tests.
- **files edited/created**:
  - `docs/WORK_LOG.md`
  - `cpaper-download-update-experience-plan.md`

### T10: Full Validation and Visual QA

- **depends_on**: [T9]
- **location**: entire active Swift package
- **description**: Run full validation and perform manual app checks for the three user-visible flows: bulk download with visible location/progress, update download with auto-open, and searchable subject selection. Use deterministic test stubs/harnesses from T5/T7 for 429 and update-complete checks instead of relying on live source failures or a real GitHub release.
- **validation**: `swift test --jobs 1` passes. `swift run CPaperNative` launches. Manual QA notes confirm Downloads page location, deterministic 429 recovery behavior, update progress/location/auto-open behavior via stubbed completion, and compact searchable subject picker. `git diff --check` has no whitespace errors.
- **status**: Completed
- **log**:
  - 2026-06-08: Full validation passed with `swift test --jobs 1`: 120 executed tests, 4 intentionally skipped live-source tests, 0 failures.
  - `git diff --check` passed.
  - `swift run CPaperNative` built and launched the native app successfully; the run session was stopped after QA.
  - Manual visual QA confirmed by the user for the updated UI. Deterministic tests cover 429 recovery and update DMG auto-open; the visible app check covered the compact subject picker and main UI surfaces.
- **files edited/created**:
  - `cpaper-download-update-experience-plan.md`

## Parallel Execution Groups

| Wave | Tasks | Can Start When |
|------|-------|----------------|
| 1 | T1, T2, T3, T4 | Immediately |
| 2 | T5, T6, T7, T8 | Their listed Wave 1 dependencies complete |
| 3 | T9 | T5, T6, T7, T8 complete |
| 4 | T10 | T9 complete |

## Testing Strategy

- Prefer test-first implementation for model/network/download/update changes.
- Keep live-source tests skipped unless the implementer intentionally opts into `RUN_LIVE_SOURCE_TESTS=1`.
- Use injected short cooldowns in tests; never make tests wait 30 real seconds.
- Add deterministic test support for 429 and update-complete flows; do not depend on live external services for acceptance.
- Manual UI QA is required for the SwiftUI popover and Finder/DMG open behaviors because they are difficult to assert reliably in unit tests.

## Risks & Mitigations

- **429 behavior can create slow tests**: inject a cooldown duration for tests and clamp only in production path.
- **Enum signature changes can break many tests**: update all `.downloading(progress:)` construction sites in one task and keep helper accessors on `UpdateStatus`.
- **Progress updates can race with actor state**: mutate `DownloadTaskItem` only inside `DownloadManager` actor methods.
- **Parallel agents can conflict on documentation**: implementation tasks must not edit `docs/WORK_LOG.md`; T9 owns the final consolidated entry.
- **Subject picker may lose keyboard focus behavior**: keep manual code field outside the popover and make the popover search field optional for mouse-only use.
- **Auto-opening DMG can be annoying in tests**: route all opens through injected `openDownloadedFile`.
