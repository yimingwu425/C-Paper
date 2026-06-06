# Plan: C-Paper 全仓库专业化整改

**Generated**: 2026-06-06

## Overview

本计划用于把 C-Paper 从当前“本地工作区污染 + 若干高风险技术债”的状态，推进到可编译、可验证、可维护、发布流程更专业的状态。

执行边界：

- 主线产品是 Swift/macOS native app 与 Swift-native backend。
- `legacy/` 保留为归档与必要维护，不重新变成主线。
- 仓库内不恢复 `site/`；网站在外部项目，后续由用户提供链接后再接入 README / release notes。
- 计划只描述实施路径；不要在执行本计划时跳过验证或顺手重构无关代码。
- 每个实施任务完成后都要追加一条简短 `docs/WORK_LOG.md` 记录，包含任务、变更、原因和实际验证命令。

## Prerequisites

- macOS + Xcode command line tools / Swift Package Manager。
- GitHub Actions 可编辑权限。
- 可选：Developer ID Application 证书、Apple notarization 凭据与 GitHub Actions secrets；本计划只预留签名/公证路径，不要求当前必须具备。
- 规范工具采用轻量渐进路线：先增加配置和 CI 检查，避免一次性格式化全仓库造成不可 review diff。
- 参考官方资料：
  - GitHub Actions workflow syntax: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions
  - GitHub Actions secrets: https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
  - Apple notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
  - SwiftLint: https://github.com/realm/SwiftLint
  - SwiftFormat: https://github.com/nicklockwood/SwiftFormat

## Dependency Graph

```text
T0.1 -> T0.2 -> T0.3 -> T0.4
                 ├────-> T1.1 -> T1.2 -> T1.3 -> T1.4 -> T1.6
                 │           └────-> T1.5
                 ├────-> T2.1 -> T2.4 -> T2.2 -> T2.3
                 └────-> T3.1 -> T3.2 -> T3.3

T1.* + T2.* + T3.* -> T4.1 -> T4.2
All implementation tasks -> T5
```

## Tasks

### T0.1: Clean Workspace Pollution

- **depends_on**: []
- **location**: repo root, `.gitignore`, duplicate untracked files
- **description**: Remove only confirmed pollution: byte-identical `* 2.swift`, `* 2.py`, `* 2.md`, `requirements 2.txt`, `.DS_Store`, and ignored build outputs. Add only explicit local ignores such as `.codex/`; do not hide broad `* 2.*` patterns in `.gitignore`. Remove `.worktrees/` entries only when `git worktree list` confirms they are stale and contain no unique work. If any `* 2.*` file differs from its canonical file, stop and inspect before deletion.
- **validation**: Target pollution patterns no longer appear: `find . -name '* 2.*' -print`, `find . -name '.DS_Store' -print`, and checks for the explicitly listed generated outputs are clean. Unrelated dirty worktree entries, if any, are left untouched and documented.
- **status**: Completed
- **log**: 2026-06-06: reason_not_testable: workspace pollution cleanup is a filesystem hygiene task, so validation used static shell checks rather than RED/GREEN tests. Compared all source/doc/script `* 2.*` files outside ignored generated directories with their canonical counterparts and deleted only byte-identical copies. Removed ignored generated outputs (`build/`, `dist/`, `.build/`, `scripts/dist/`, `.pytest_cache/`) and `.DS_Store` files. Preserved the registered `.worktrees/swift-native-backend-6` worktree and removed only its ignored `.build` cache. Removed stale nonstandard `.git/objects/maintenance 2.lock` after confirming it was not open. Added explicit `.codex/` ignore. Validation: `find . -name '* 2.*' -print` produced no output; `find . -name '.DS_Store' -print` produced no output; generated output existence check printed `pollution-validation-clean`; `git status --short` shows only `.gitignore` modified and the pre-existing `PaperFilenameParser.swift` deletion left for T0.2.
- **files edited/created**: `.gitignore`; deleted byte-identical duplicate `* 2.*` source/doc/script files; removed ignored generated output directories and `.DS_Store` files.

### T0.2: Restore Compilable Parsing Baseline

- **depends_on**: [T0.1]
- **location**: `macos/Sources/CPaperNativeApp/Backend/Parsing/`, `macos/Tests/CPaperNativeTests/PaperParsingTests.swift`
- **description**: Restore or recreate `PaperFilenameParser.swift` using the current call sites, `PaperParsingTests`, and the latest git-history version of this file as the contract. Do not infer new behavior from legacy code unless current tests/callers explicitly require it. Keep behavior aligned for subject, session/year, paper type, component number, season name, paper group, and invalid-path rejection.
- **validation**: `swift test --jobs 1 --filter PaperParsingTests` compiles and passes.
- **status**: Completed
- **log**: 2026-06-06: RED: `swift test --jobs 1 --filter PaperParsingTests` failed at compile time because `PaperFilenameParser` and `ParsedPaperFilename` were missing from the active source set, producing downstream parser/source compile errors. Restored `macos/Sources/CPaperNativeApp/Backend/Parsing/PaperFilenameParser.swift` from the latest git-tracked version to reestablish the current parser contract without adding new behavior. GREEN: the same command built successfully and `PaperParsingTests` ran 6 tests with 0 failures.
- **files edited/created**: `macos/Sources/CPaperNativeApp/Backend/Parsing/PaperFilenameParser.swift`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T0.3: Correct Active Architecture Boundaries

- **depends_on**: [T0.2]
- **location**: `MAINTENANCE_BASELINE.md`, `docs/PROJECT_INDEX.md`, `README.md`, `native/CPaperNative/README.md`
- **description**: Fix misleading active/legacy documentation before deeper work begins. Native Swift backend is active; Python bridge/backend are archived under `legacy/python-backend/`; `site/` is external and should be documented as link pending rather than an in-repo active directory.
- **validation**: No current docs describe root `bridge/`, root `backend/`, or in-repo `site/` as active implementation.
- **status**: Completed
- **log**: 2026-06-06: reason_not_testable: this task only corrects documentation boundaries, so validation used static text checks instead of RED/GREEN tests. Updated the active/legacy architecture descriptions to keep the active implementation native-first (`Package.swift`, `macos/`, Swift-native backend, `scripts/`, `assets/`, `docs/`), moved Python bridge/backend references to archived `legacy/python-backend/`, and replaced in-repo `site/` claims with an external project-site note marked link pending. Validation evidence: `rg -n -e 'bridge/' -e 'backend/' -e 'site/' -e 'requirements\\.txt' -e 'pytest' MAINTENANCE_BASELINE.md docs/PROJECT_INDEX.md README.md native/CPaperNative/README.md` shows only legacy or non-active references after the edit; no target doc now describes root `bridge/`, root `backend/`, or in-repo `site/` as active implementation.
- **files edited/created**: `MAINTENANCE_BASELINE.md`; `docs/PROJECT_INDEX.md`; `README.md`; `native/CPaperNative/README.md`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T0.4: Establish Deterministic Baseline

- **depends_on**: [T0.3]
- **location**: full repo
- **description**: Run the deterministic baseline after the repository is no longer structurally polluted. Capture the true current state before feature fixes.
- **validation**: `swift test --jobs 1` runs to completion or to a real test failure; result is recorded in `docs/WORK_LOG.md`.
- **status**: Completed
- **log**: 2026-06-06: reason_not_testable: this task is a baseline measurement task, not a code-fix/TDD task, so the evidence is the exact `swift test --jobs 1` run output and exit status rather than a new RED/GREEN cycle. Baseline evidence: `swift test --jobs 1` exited with status `0`; output included `Build complete! (0.14s)`, `Executed 58 tests, with 4 tests skipped and 0 failures (0 unexpected) in 1.614 (1.623) seconds`, and `Test Suite 'All tests' passed`.
- **files edited/created**: `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T1.1: Make Startup Failure Recoverable

- **depends_on**: [T0.4]
- **location**: `macos/Sources/CPaperNativeApp/main.swift`, `RootView.swift`, `AppModel.swift`, setup state files
- **description**: Replace eager `AppModel()` construction and `try! NativeBackendService()` with a boot container state: loading, ready, failed. On backend initialization failure, show a focused error view with retry and copyable diagnostic text. Do not swallow errors silently.
- **validation**: Injected failing backend/path initialization shows failure UI instead of crashing; normal startup still bootstraps settings, subjects, favorites, downloads, and update checks. Repeated retry attempts are idempotent: no duplicate startup update checks, no leaked half-initialized model, and only one successful ready model is active.
- **status**: Completed
- **log**: 2026-06-06: RED evidence was captured during the parallel T1.1 test phase when `StartupBootCoordinatorTests` referenced the new boot coordinator contract before `AppBootCoordinator` was available to the test target, causing SwiftPM compilation to fail with `cannot find 'AppBootCoordinator' in scope`. Implemented `AppBootCoordinator` with loading/ready/failed phases, explicit failing diagnostics, retry support, and stale-attempt protection; changed `AppModel` to require an injected backend and added `AppModel.live()` for fallible live startup; moved `RootView` to render loading, ready, and failure startup states. GREEN: `swift test --jobs 1 --filter StartupBootCoordinatorTests` passed 2 tests with 0 failures, and `swift test --jobs 1` passed 62 tests with 4 skipped and 0 failures.
- **files edited/created**: `macos/Sources/CPaperNativeApp/State/AppBootCoordinator.swift`; `macos/Sources/CPaperNativeApp/State/AppModel.swift`; `macos/Sources/CPaperNativeApp/Views/RootView.swift`; `macos/Tests/CPaperNativeTests/StartupBootCoordinatorTests.swift`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T1.2: Add Shared File Transfer Layer

- **depends_on**: [T1.1]
- **location**: `macos/Sources/CPaperNativeApp/Backend/Networking/`, `DownloadSourceURLResolver.swift`, tests
- **description**: Add a shared transfer module, for example `HTTPFileTransferClient`, that owns proxy configuration, User-Agent, request construction, HTTP status validation, chunked file writing, cancellation cleanup, and progress callback behavior. Reuse `HTTPRequestBuilder`, `ProxyConfiguration`, and `DownloadSourceURLResolver`.
- **validation**: Unit tests cover successful transfer, non-2xx response, proxy configuration, progress reporting, cancellation, and partial-file cleanup.
- **status**: Completed
- **log**: 2026-06-06: RED: `swift test --jobs 1 --filter HTTPFileTransferClientTests` failed at compile time because the new test suite referenced missing `HTTPFileTransferClient` symbols. GREEN: added `HTTPFileTransferClient` to own request building, proxy-aware session construction, shared HTTP status validation, chunked file writes, progress callbacks, and cleanup on failure/cancellation; `swift test --jobs 1 --filter HTTPFileTransferClientTests` then passed 5 tests with 0 failures, and `swift test --jobs 1` passed 67 tests with 4 skipped and 0 failures.
- **files edited/created**: `macos/Sources/CPaperNativeApp/Backend/Networking/HTTPFileTransferClient.swift`; `macos/Sources/CPaperNativeApp/Backend/Networking/NetworkClient.swift`; `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T1.3: Isolate Download Sessions Before Changing Writer

- **depends_on**: [T1.2]
- **location**: `DownloadManager.swift`, `NativeBackendService.swift`, `AppModel+PaperWorkflow.swift`, download tests
- **description**: Introduce a run/session id so old cancelled workers cannot mutate the new queue, snapshot, work items, or download item statuses. Then update the download start path to pass `DownloadSettings` or at least `proxyURL`, and route default downloads through the shared transfer layer.
- **validation**: Regression tests cover start-while-running, cancel-then-start, late old-worker completion, EasyPaper token refresh, and no whole-PDF memory buffering.
- **status**: Completed
- **log**: 2026-06-06: RED: `swift test --jobs 1 --filter DownloadManagerTests` failed at compile time after adding the new regression coverage because `DownloadManager` did not yet accept a shared-transfer writer and `NativeBackendService.startDownload` did not accept/pass `proxyURL` (`extra argument 'sharedTransfer' in call`, `extra argument 'proxyURL' in call`). GREEN: added run-id invalidation so stale workers cannot touch a newer run's queue/item/snapshot state, passed per-run rate limiter/circuit breaker instances through worker execution to avoid cross-run contamination, guarded atomic replace/completion recording against late stale completions, and routed the default download path through `HTTPFileTransferClient` with proxy-aware transfer. Updated the backend/app download start path to pass `settings.proxyURL`. Validation PASS: `swift test --jobs 1 --filter DownloadManagerTests` passed 10 tests with 0 failures, including start-while-running, cancel-then-start, late old-worker completion, EasyPaper token refresh, and proxy/shared-transfer routing coverage. Validation PASS: `swift test --jobs 1` passed 70 tests with 4 skipped and 0 failures.
- **files edited/created**: `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift`; `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift`; `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift`; `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift`; `macos/Tests/CPaperNativeTests/DownloadTestSupport.swift`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T1.4: Move PDF Preview And Update Downloads Onto Shared Transfer

- **depends_on**: [T1.3]
- **location**: `PDFPreviewView.swift`, `NativeBackendService.swift`, `UpdateService.swift`, preview/update tests
- **description**: Remove direct `URLSession.shared.download` from PDF preview and direct byte-by-byte writing from update download. PDF preview should reuse local downloaded files when present, then use backend transfer with proxy and EasyPaper URL resolution. Update downloads should use chunked transfer and retain `.part` atomic replacement behavior.
- **validation**: PDF preview respects proxy/settings and EasyPaper token resolution; `UpdateServiceTests` cover chunked download success, error response, partial cleanup, and final atomic move.
- **status**: Completed
- **log**: 2026-06-06: RED: `swift test --jobs 1 --filter UpdateServiceTests` and `swift test --jobs 1 --filter NativeBackendServicePreviewTests` failed at compile time after adding the new T1.4 coverage because `UpdateService` did not yet expose a shared-transfer injection path and `NativeBackendService` had no preview-transfer entrypoint (`extra argument 'transferClientFactory' in call`, `extra argument 'previewTransfer' in call`). GREEN: moved preview loading into `NativeBackendService.previewURL(for:settings:)`, which reuses already-downloaded local files, caches preview files under the native cache directory, routes network preview through `HTTPFileTransferClient`, and resolves EasyPaper download URLs before transfer; updated `PDFPreviewView` to consume that backend path instead of `URLSession.shared.download`. Also moved default update downloads onto `HTTPFileTransferClient`, kept `.part` + atomic replace semantics, and explicitly clean up leftover partials on transfer failure. Validation PASS: `swift test --jobs 1 --filter UpdateServiceTests` passed 7 tests with 0 failures, `swift test --jobs 1 --filter NativeBackendServicePreviewTests` passed 2 tests with 0 failures, and `swift test --jobs 1` passed 74 tests with 4 skipped and 0 failures.
- **files edited/created**: `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift`; `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadSourceURLResolver.swift`; `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift`; `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift`; `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift`; `macos/Tests/CPaperNativeTests/NativeBackendServicePreviewTests.swift`; `macos/Tests/CPaperNativeTests/TransferTestSupport.swift`; `macos/Tests/CPaperNativeTests/UpdateServiceTests.swift`

### T1.5: Make Settings Cancel Actually Revert

- **depends_on**: [T0.4]
- **location**: `SettingsView.swift`, settings section views, model/view tests
- **description**: Edit settings through a draft copy. Save writes draft values into `model.settings` and persists them; cancel closes without mutating app state. Preserve existing control layout and design language.
- **validation**: Automated tests cover draft rollback on cancel and persisted commit on save. Focused manual smoke covers directory picker and proxy test button behavior.
- **status**: Completed
- **log**: 2026-06-06: RED: `swift test --jobs 1 --filter ModelTests` initially failed at `macos/Tests/CPaperNativeTests/ModelTests.swift:114` because `AppModel.saveSettings` did not accept a draft value, so the new save-commit test could not compile. Implemented local settings draft state in `SettingsView`, rebound the editable settings sections to that draft, changed save to commit the draft via `AppModel.saveSettings(_:)`, and updated the save-directory/proxy helpers so the directory picker and proxy test operate on draft values without mutating live settings on cancel. Added focused `ModelTests` coverage for draft rollback/no-op cancel semantics and persisted commit-on-save behavior. GREEN: `swift build --product CPaperNative` passed, and an additional temporary compiled harness against the built `CPaperNativeApp` module completed both new draft scenarios and printed `settings-draft-check: ok`. `swift test --jobs 1 --filter ModelTests` remains blocked after the T1.5 fix by concurrent untracked `macos/Tests/CPaperNativeTests/StartupBootCoordinatorTests.swift` referencing missing `AppBootCoordinator`, so the T1.5 behavior was green-verified with the built-module harness instead of a passing SwiftPM test run. Manual/static-check evidence: the browse action now only assigns the selected path into `draftSettings.saveDirectory` in `SettingsView.swift`, cancel still just dismisses, and the proxy test button now calls `model.testProxy(proxyURL)` with the draft proxy URL while only updating local `proxyStatus`.
- **files edited/created**: `macos/Sources/CPaperNativeApp/State/AppModel+Setup.swift`; `macos/Sources/CPaperNativeApp/Views/SettingsView.swift`; `macos/Sources/CPaperNativeApp/Views/SettingsFormSections.swift`; `macos/Tests/CPaperNativeTests/ModelTests.swift`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T1.6: Integrate Transfer-Related Support Facade Cleanup

- **depends_on**: [T1.4]
- **location**: `NativeBackendService.swift`, paper workflow state, related tests
- **description**: After download and preview both use the shared transfer contract, remove any temporary adapter glue, duplicate local-file lookup logic, or obsolete transfer helpers. Keep `NativeBackendService` as a narrow facade rather than a dumping ground for transfer details.
- **validation**: Search, preview, single download, batch download, cancel, and update tests still pass; `NativeBackendService` exposes only stable app-facing methods.
- **status**: Completed
- **log**: 2026-06-06: RED: `swift test --jobs 1 --filter DownloadDestinationBuilderTests/testExistingDownloadURLFindsMergedAndSplitDestinations` failed at compile time because `DownloadDestinationBuilder.existingDownloadURL` did not exist. GREEN: added `DownloadDestinationBuilder.existingDownloadURL(for:saveDirectory:fileManager:)` for merged and split downloaded-file lookup; moved preview local-file reuse, preview cache pathing, EasyPaper URL resolution, and shared-transfer preview writes into `PreviewFileService`; and reduced `NativeBackendService.previewURL(for:settings:)` to a narrow facade call. Validation PASS: the same focused RED test passed; `swift test --jobs 1 --filter NativeBackendServicePreviewTests`, `swift test --jobs 1 --filter DownloadManagerTests`, `swift test --jobs 1 --filter UpdateServiceTests`, `swift test --jobs 1 --filter ModelTests`, and full `swift test --jobs 1` passed with 75 tests, 4 skipped, and 0 failures. Static cleanup check: `rg -n "PreviewTransferWriter|localDownloadedFileURL|defaultPreviewTransfer|URLSession\\.shared\\.download|data\\(from:" macos/Sources/CPaperNativeApp/Backend macos/Sources/CPaperNativeApp/Views` found no obsolete facade/download glue.
- **files edited/created**: `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift`; `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift`; `macos/Sources/CPaperNativeApp/Backend/Downloads/PreviewFileService.swift`; `macos/Tests/CPaperNativeTests/DownloadDestinationBuilderTests.swift`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T2.1: Create Version Single Source Of Truth

- **depends_on**: [T0.3]
- **location**: `version.json`, `BackendConstants.swift`, `HTTPRequestBuilder.swift`, `scripts/build_native_dmg.sh`, `README.md`
- **description**: Make `version.json` the canonical version source. Other version displays, User-Agent strings, and build script metadata should be generated from it or checked against it. Add a drift check that fails when versions diverge.
- **validation**: Drift check passes in the intended state and fails when any duplicate version string is intentionally changed.
- **status**: Completed
- **log**: 2026-06-06: RED/FAIL: added `scripts/check_version_drift.sh` first and ran it against the pre-change repo; it failed with `VERSION DRIFT: BackendConstants.userAgent must derive from BackendConstants.version`. Also proved controlled drift failure without dirtying tracked files by overriding a temporary `BackendConstants.swift` copy to `9.9.9`; the same script failed with `VERSION DRIFT: BackendConstants.version expected 6.0.3 but found 9.9.9`. GREEN/PASS: added `scripts/lib/version_helpers.sh`, switched `scripts/build_native_dmg.sh` to read `VERSION` from `version.json`, derived `BackendConstants.userAgent` from `BackendConstants.version`, pointed `HTTPRequestBuilder.defaultUserAgent` at `BackendConstants.userAgent`, and reduced README hardcoded version duplication. Validation PASS: `bash scripts/check_version_drift.sh`, `bash -n scripts/build_native_dmg.sh`, `python3 -m json.tool version.json`, and `swift build --product CPaperNative`. Additional evidence: attempted `swift test --jobs 1 --filter UpdateServiceTests`, but current test compilation is blocked by pre-existing parallel-worktree errors in `StartupBootCoordinatorTests` (`cannot find 'AppBootCoordinator' in scope`), not by T2.1 changes.
- **files edited/created**: `README.md`; `macos/Sources/CPaperNativeApp/Backend/Core/BackendConstants.swift`; `macos/Sources/CPaperNativeApp/Backend/Networking/HTTPRequestBuilder.swift`; `scripts/build_native_dmg.sh`; `scripts/check_version_drift.sh`; `scripts/lib/version_helpers.sh`

### T2.2: Split CI Into Validate, Package, Release

- **depends_on**: [T2.4]
- **location**: `.github/workflows/build.yml`, validation scripts
- **description**: Refactor the native workflow into `validate`, `package`, and `release` jobs. `validate` runs on `pull_request` and native-relevant pushes, and includes Swift tests, shell syntax, JSON/YAML parsing, version drift, and repo hygiene. `package` builds and verifies DMG for main/tag release paths. `release` publishes only for tags. Add workflow `concurrency`, and remove legacy Python path triggers from native release unless intentionally needed.
- **validation**: Workflow graph clearly blocks package/release on validate; tag-only release behavior is preserved; path filters match native ownership.
- **status**: Completed
- **log**: 2026-06-06: `reason_not_testable`: this task refactors GitHub Actions control flow and path filters, so validation used static workflow parsing/inspection plus the concrete commands wired into `validate` rather than a RED/GREEN unit test. Split `.github/workflows/build.yml` into `validate`, `package`, and `release` jobs; added top-level workflow `concurrency`; scoped `pull_request` and branch-push path filters to native-owned files; removed `legacy/python-backend/**` from the native workflow triggers; kept DMG artifact upload in `package`; and moved tag-only release publishing behind `needs: package` with artifact download in `release`. Validation PASS: `python3` + `yaml.BaseLoader` parsed `.github/workflows/build.yml` and asserted `package -> validate`, `release -> package`, tag-only release condition, absence of `legacy/python-backend/**`, and presence of workflow concurrency; `python3` also parsed both `.github/workflows/build.yml` and `.github/workflows/legacy-release.yml`. Validation PASS: `python3 -m json.tool version.json`, `bash scripts/check_version_drift.sh`, `bash scripts/check_repo_hygiene.sh`, `bash scripts/check_swift_quality.sh`, `swift test --jobs 1`, and `git diff --check`.
- **files edited/created**: `.github/workflows/build.yml`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T2.3: Prepare Signing And Notarization Without Requiring Secrets

- **depends_on**: [T2.2]
- **location**: `scripts/build_native_dmg.sh`, `scripts/lib/native_dmg_helpers.sh`, `.github/workflows/build.yml`, release docs
- **description**: Keep ad hoc signing as default. Add optional Developer ID signing and notarization path when CI secrets are present. Use explicit secret names in docs and workflow comments, and ensure local builds continue without credentials.
- **validation**: No-secret local/CI build still works with ad hoc signing; documented secret-backed path uses `codesign`, `notarytool`, and staple in the correct order.
- **status**: Completed
- **log**: 2026-06-06: `reason_not_testable`: this task prepares native packaging/release scripts for optional Apple signing and notarization, so validation used shell syntax checks, workflow parsing, and dry/static path assertions rather than live Apple credential execution. Updated `scripts/lib/native_dmg_helpers.sh` to detect optional `CPAPER_CODESIGN_IDENTITY` / `CPAPER_NOTARY_KEYCHAIN_PROFILE`, use Developer ID signing when configured, keep ad hoc signing as the no-secret default, and submit/staple the final DMG with `xcrun notarytool submit --wait` and `xcrun stapler staple` when notarization is configured. Updated `scripts/build_native_dmg.sh` to report the active signing mode, call the shared signing helper before DMG packaging, and run optional notarization after the final DMG is produced. Updated `.github/workflows/build.yml` so the `package` job only imports a Developer ID certificate, stores a `notarytool` keychain profile, and exports signing env vars when all optional secrets are present; otherwise the build step receives no signing env and remains ad hoc. Added concise README release-build notes documenting the env vars, optional secrets, and the ad hoc fallback. Validation PASS: `bash -n scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`; `python3 - <<'PY' ... yaml.load(..., Loader=yaml.BaseLoader) ... PY` parsing `.github/workflows/build.yml`; `python3 - <<'PY' ... assert secret names in package configure-step gate ... PY`; `python3 - <<'PY' ... assert 'codesign' < 'xcrun notarytool submit' < 'xcrun stapler staple' ... PY`; `bash -lc 'unset CPAPER_CODESIGN_IDENTITY CPAPER_NOTARY_KEYCHAIN_PROFILE; source scripts/lib/native_dmg_helpers.sh; test \"$(current_signing_mode)\" = \"ad hoc\"; ! notarization_configured; echo no-secret-path-ok'`; and `git diff --check`.
- **files edited/created**: `.github/workflows/build.yml`; `README.md`; `scripts/build_native_dmg.sh`; `scripts/lib/native_dmg_helpers.sh`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T2.4: Add Lightweight Quality Gates

- **depends_on**: [T2.1]
- **location**: `.swiftlint.yml`, `.swiftformat`, scripts, CI
- **description**: Add lightweight SwiftLint/SwiftFormat or equivalent check-only configuration plus standalone validation scripts. Do not run mass formatting. Add a repo hygiene script that fails on `.DS_Store`, duplicate Finder-style `* 2.*` files, and other known pollution patterns. These scripts are created here; T2.2 wires them into GitHub Actions.
- **validation**: Check-only commands run locally; existing code does not receive a broad formatting diff; hygiene script catches recreated duplicate files.
- **status**: Completed
- **log**: 2026-06-06: RED/FAIL evidence first: added `scripts/check_repo_hygiene.sh` and ran it against a temporary fixture containing `.DS_Store` and `subdir/Notes 2.md`; the script failed as intended and listed both pollution files without touching tracked content. Added lightweight check-only configs in `.swiftlint.yml` and `.swiftformat`, plus `scripts/check_swift_quality.sh`, which runs `swiftlint lint --strict` and `swiftformat --lint` when those binaries are available and otherwise exits successfully with explicit skip messages. GREEN/PASS: `bash scripts/check_repo_hygiene.sh` passed on the real repository, `bash scripts/check_swift_quality.sh` ran locally and skipped both checks because `swiftlint` and `swiftformat` are not installed in this environment, and no existing Swift sources were reformatted or edited. Additional validation: `bash -n scripts/check_repo_hygiene.sh`, `bash -n scripts/check_swift_quality.sh`, and `git diff --check`.
- **files edited/created**: `.swiftlint.yml`; `.swiftformat`; `scripts/check_repo_hygiene.sh`; `scripts/check_swift_quality.sh`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T3.1: Refresh Architecture Boundary Documentation

- **depends_on**: [T0.3]
- **location**: `README.md`, `docs/PROJECT_INDEX.md`, `MAINTENANCE_BASELINE.md`, `native/CPaperNative/README.md`
- **description**: Refresh architecture boundary docs only: native 6.x reality, active source, archived legacy, external site link placeholder, and where tests/build scripts live. Avoid release-flow details that depend on T2.2/T2.3.
- **validation**: A new contributor can read README + PROJECT_INDEX and correctly identify active source, tests, and legacy boundaries.
- **status**: Completed
- **log**: 2026-06-06: `reason_not_testable`: this task only refreshes contributor-facing architecture boundary documentation, so there is no meaningful RED/GREEN runtime test to add. Updated `README.md`, `docs/PROJECT_INDEX.md`, `MAINTENANCE_BASELINE.md`, and `native/CPaperNative/README.md` to consistently mark the root `Package.swift` + `macos/` as the active native 6.x implementation, point active tests to `macos/Tests/CPaperNativeTests/`, list `scripts/` and `scripts/lib/` as active build-script locations, keep the project site as external-link pending, and confine Python/pywebview references to `legacy/`. Validation PASS: `rg -n "Package\\.swift|macos/Tests/CPaperNativeTests|scripts/lib|swift test --jobs 1|legacy/python-backend|legacy/pywebview|site/" README.md docs/PROJECT_INDEX.md MAINTENANCE_BASELINE.md native/CPaperNative/README.md` showed the required active/legacy boundary terms in all four docs. Validation PASS: `rg -n "Build Native macOS|workflow|GitHub Actions|site/.*active|active app directory|main implementation under legacy|legacy is active" README.md docs/PROJECT_INDEX.md MAINTENANCE_BASELINE.md native/CPaperNative/README.md` found no release-flow prose in the refreshed boundary sections; the only remaining workflow match is the unchanged README badge link.
- **files edited/created**: `README.md`; `docs/PROJECT_INDEX.md`; `MAINTENANCE_BASELINE.md`; `native/CPaperNative/README.md`

### T3.2: Freeze Legacy Clearly

- **depends_on**: [T3.1, T2.2]
- **location**: `legacy/`, `.github/workflows/build.yml`, `.github/workflows/legacy-release.yml`, legacy release notes
- **description**: Document legacy as archival. Keep final legacy release workflow understandable, but prevent legacy docs or path triggers from implying it is part of the active native product. Python dependency locking is optional and only needed if legacy CI continues running.
- **validation**: Legacy workflow and docs describe archival status; native workflow is not triggered by ordinary legacy-only changes.
- **status**: Completed
- **log**: 2026-06-06: `reason_not_testable`: this task freezes documentation and workflow boundaries rather than changing runtime behavior, so no meaningful RED/GREEN unit test applies. Added `legacy/README.md` to mark `legacy/` as archival, point active maintenance to root `Package.swift` + `macos/`, and state that legacy-only changes should not trigger the native workflow. Updated `.github/workflows/legacy-release.yml` with final archived legacy release naming, run name, job names, and comments that keep the final 5.2.1 pywebview release path understandable without making it look like the active product line. Updated `.github/workflows/build.yml` comments to document that native branch path filters intentionally exclude `legacy/`, and tightened `.github/release-notes/legacy-v5.2.1.md` archival wording. Python dependency locking was intentionally not added because no routine legacy CI runs from ordinary branch or pull-request changes. Validation PASS: `ruby - <<'RUBY' ... YAML.load_file(...) ... RUBY` parsed `.github/workflows/build.yml` and `.github/workflows/legacy-release.yml`; `ruby - <<'RUBY' ... assert path filters exclude legacy/ and archival terms exist ... RUBY` proved `pull_request` and branch `push` path filters contain 12 native-owned paths and no `legacy/` entries, and proved archival status is described in `legacy/README.md`, `.github/workflows/legacy-release.yml`, and `.github/release-notes/legacy-v5.2.1.md`; `git diff --check` passed.
- **files edited/created**: `legacy/README.md`; `.github/workflows/build.yml`; `.github/workflows/legacy-release.yml`; `.github/release-notes/legacy-v5.2.1.md`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T3.3: Refresh Release And Validation Documentation

- **depends_on**: [T2.2, T2.3, T3.2]
- **location**: `README.md`, `docs/PROJECT_INDEX.md`, release notes, signing/notarization docs
- **description**: Update release, validation, install, privacy/disclaimer, and data-source reliability documentation after CI and signing/notarization placeholders are stable. Keep website references as external-link pending.
- **validation**: Public docs describe the actual validate/package/release flow and no longer conflict with workflow behavior.
- **status**: Completed
- **log**: 2026-06-06: `reason_not_testable`: this is a documentation refresh for release, validation, install, privacy/disclaimer, data-source reliability, and signing/notarization behavior, so there is no meaningful RED/GREEN runtime test. Updated README release/install/signing/source-reliability wording, added `docs/RELEASE_AND_VALIDATION.md` as the focused native release reference, indexed it from `docs/PROJECT_INDEX.md`, and updated the latest native release note to describe the current tag-only release path, manual `workflow_dispatch` packaging behavior, ad hoc default signing, and optional Developer ID/notary path. Kept website/project-site wording as external-link pending. Validation PASS: Ruby parsed `.github/workflows/build.yml` and asserted `package -> validate`, `release -> package`, package event gating for `workflow_dispatch`/`push`, and tag-only release gating. Validation PASS: static doc consistency check confirmed required release terms in public docs and no contradiction with workflow behavior; `rg -n "validate/package/release|tag-only|workflow_dispatch|ad hoc|Developer ID/notary|external-link pending|privacy/disclaimer/data source reliability" README.md docs/PROJECT_INDEX.md docs/RELEASE_AND_VALIDATION.md .github/release-notes/native-v6.0.3.md`; `git diff --check`.
- **files edited/created**: `README.md`; `docs/PROJECT_INDEX.md`; `docs/RELEASE_AND_VALIDATION.md`; `.github/release-notes/native-v6.0.3.md`; `cpaper-professionalization-plan.md`; `docs/WORK_LOG.md`

### T4.1: Add Supportability And Diagnostics

- **depends_on**: [T1.1, T1.2, T1.3, T1.4, T1.6, T2.2]
- **location**: UI views, error models, logging/support helpers
- **description**: Add user-facing diagnostics for startup, download, preview, update, and source-provider failures. Include a local log/support bundle path, reveal/export action, and redacted context. Never include secrets, proxy credentials, EasyPaper tokens, or private path details beyond what is necessary.
- **validation**: Users can copy/export diagnostics; sensitive values are redacted; failure messages remain actionable and concise.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T4.2: Product Polish Pass

- **depends_on**: [T4.1]
- **location**: SwiftUI views, DMG assets, docs
- **description**: Review empty states, loading states, cancellation states, accessibility labels, Settings language, DMG install guidance, privacy/disclaimer visibility, and consistency with the existing glass design system. Keep UI task-focused, not marketing-heavy.
- **validation**: Manual smoke test covers search, preview, batch preview, batch download, single download, cancellation, settings save/cancel, update check, and failure states.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T5: Final Verification And Release Readiness Audit

- **depends_on**: [T0.4, T1.1, T1.2, T1.3, T1.4, T1.5, T1.6, T2.1, T2.2, T2.3, T2.4, T3.1, T3.2, T3.3, T4.1, T4.2]
- **location**: full repo
- **description**: Run deterministic verification, release packaging verification, and final documentation audit. Keep live source checks manual/nightly unless explicitly requested as blocking.
- **validation**: Required checks pass or failures are documented with exact commands and output summary: `swift test --jobs 1`, focused tests, `bash -n scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`, `python3 -m json.tool version.json`, YAML parse, version drift check, hygiene scan, `CONFIGURATION=release bash scripts/build_native_dmg.sh`, DMG verify/mount checks.
- **status**: Not Completed
- **log**:
- **files edited/created**:

## Parallel Execution Groups

| Wave | Tasks | Can Start When |
| --- | --- | --- |
| 0A | T0.1 | Immediately |
| 0B | T0.2 | T0.1 complete |
| 0C | T0.3 | T0.2 complete |
| 0D | T0.4 | T0.3 complete |
| 1 | T1.1, T1.5, T2.1, T3.1 | Baseline available |
| 2 | T1.2, T2.4 | Respective Wave 1 dependencies complete |
| 3 | T1.3, T2.2 | Shared transfer / quality scripts complete |
| 4 | T1.4, T2.3, T3.2 | T1.3 and T2.2 complete as applicable |
| 5 | T1.6, T3.3 | Transfer migration and release platform complete |
| 6 | T4.1 | Stability, CI, and docs dependencies complete |
| 7 | T4.2 | T4.1 complete |
| 8 | T5 | All implementation waves complete |

## Testing Strategy

- Deterministic required checks:
  - `swift test --jobs 1`
  - focused tests for parsing, download manager, update service, model/settings, and source registry
  - `bash -n scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`
  - `python3 -m json.tool version.json`
  - YAML parse for workflows
  - version drift check
  - repo hygiene scan
- Release checks:
  - `CONFIGURATION=release bash scripts/build_native_dmg.sh`
  - `hdiutil verify dist/C-Paper-Native-*-standalone-*.dmg`
  - mount DMG and verify app bundle, Applications symlink, and background asset
- Optional live checks:
  - `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
  - Keep live source checks manual or scheduled because third-party sources are unstable.

## Risks & Mitigations

- **Risk**: Deleting duplicate files may remove user work.
  - **Mitigation**: Only delete files that are byte-identical to canonical files or clearly generated local artifacts; inspect differing files before removal.
- **Risk**: Startup error handling can accidentally hide initialization bugs.
  - **Mitigation**: Preserve raw diagnostic detail for support, but show concise user-facing copy.
- **Risk**: Shared transfer abstraction could become overbuilt.
  - **Mitigation**: Keep the interface narrow: request/source URL, destination URL, proxy/config, progress callback.
- **Risk**: CI strictness could block urgent release work.
  - **Mitigation**: Add deterministic checks first; keep live network tests outside default blocking path.
- **Risk**: Signing/notarization path may fail without secrets.
  - **Mitigation**: Default to ad hoc signing; enable Developer ID path only when all required secrets are present.
- **Risk**: Version single-source migration may introduce release metadata drift.
  - **Mitigation**: Add drift check before changing release scripts, then keep it in CI.
