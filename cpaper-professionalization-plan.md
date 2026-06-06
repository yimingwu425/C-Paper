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
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T1.1: Make Startup Failure Recoverable

- **depends_on**: [T0.4]
- **location**: `macos/Sources/CPaperNativeApp/main.swift`, `RootView.swift`, `AppModel.swift`, setup state files
- **description**: Replace eager `AppModel()` construction and `try! NativeBackendService()` with a boot container state: loading, ready, failed. On backend initialization failure, show a focused error view with retry and copyable diagnostic text. Do not swallow errors silently.
- **validation**: Injected failing backend/path initialization shows failure UI instead of crashing; normal startup still bootstraps settings, subjects, favorites, downloads, and update checks. Repeated retry attempts are idempotent: no duplicate startup update checks, no leaked half-initialized model, and only one successful ready model is active.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T1.2: Add Shared File Transfer Layer

- **depends_on**: [T1.1]
- **location**: `macos/Sources/CPaperNativeApp/Backend/Networking/`, `DownloadSourceURLResolver.swift`, tests
- **description**: Add a shared transfer module, for example `HTTPFileTransferClient`, that owns proxy configuration, User-Agent, request construction, HTTP status validation, chunked file writing, cancellation cleanup, and progress callback behavior. Reuse `HTTPRequestBuilder`, `ProxyConfiguration`, and `DownloadSourceURLResolver`.
- **validation**: Unit tests cover successful transfer, non-2xx response, proxy configuration, progress reporting, cancellation, and partial-file cleanup.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T1.3: Isolate Download Sessions Before Changing Writer

- **depends_on**: [T1.2]
- **location**: `DownloadManager.swift`, `NativeBackendService.swift`, `AppModel+PaperWorkflow.swift`, download tests
- **description**: Introduce a run/session id so old cancelled workers cannot mutate the new queue, snapshot, work items, or download item statuses. Then update the download start path to pass `DownloadSettings` or at least `proxyURL`, and route default downloads through the shared transfer layer.
- **validation**: Regression tests cover start-while-running, cancel-then-start, late old-worker completion, EasyPaper token refresh, and no whole-PDF memory buffering.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T1.4: Move PDF Preview And Update Downloads Onto Shared Transfer

- **depends_on**: [T1.3]
- **location**: `PDFPreviewView.swift`, `NativeBackendService.swift`, `UpdateService.swift`, preview/update tests
- **description**: Remove direct `URLSession.shared.download` from PDF preview and direct byte-by-byte writing from update download. PDF preview should reuse local downloaded files when present, then use backend transfer with proxy and EasyPaper URL resolution. Update downloads should use chunked transfer and retain `.part` atomic replacement behavior.
- **validation**: PDF preview respects proxy/settings and EasyPaper token resolution; `UpdateServiceTests` cover chunked download success, error response, partial cleanup, and final atomic move.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T1.5: Make Settings Cancel Actually Revert

- **depends_on**: [T0.4]
- **location**: `SettingsView.swift`, settings section views, model/view tests
- **description**: Edit settings through a draft copy. Save writes draft values into `model.settings` and persists them; cancel closes without mutating app state. Preserve existing control layout and design language.
- **validation**: Automated tests cover draft rollback on cancel and persisted commit on save. Focused manual smoke covers directory picker and proxy test button behavior.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T1.6: Integrate Transfer-Related Support Facade Cleanup

- **depends_on**: [T1.4]
- **location**: `NativeBackendService.swift`, paper workflow state, related tests
- **description**: After download and preview both use the shared transfer contract, remove any temporary adapter glue, duplicate local-file lookup logic, or obsolete transfer helpers. Keep `NativeBackendService` as a narrow facade rather than a dumping ground for transfer details.
- **validation**: Search, preview, single download, batch download, cancel, and update tests still pass; `NativeBackendService` exposes only stable app-facing methods.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T2.1: Create Version Single Source Of Truth

- **depends_on**: [T0.3]
- **location**: `version.json`, `BackendConstants.swift`, `HTTPRequestBuilder.swift`, `scripts/build_native_dmg.sh`, `README.md`
- **description**: Make `version.json` the canonical version source. Other version displays, User-Agent strings, and build script metadata should be generated from it or checked against it. Add a drift check that fails when versions diverge.
- **validation**: Drift check passes in the intended state and fails when any duplicate version string is intentionally changed.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T2.2: Split CI Into Validate, Package, Release

- **depends_on**: [T2.4]
- **location**: `.github/workflows/build.yml`, validation scripts
- **description**: Refactor the native workflow into `validate`, `package`, and `release` jobs. `validate` runs on `pull_request` and native-relevant pushes, and includes Swift tests, shell syntax, JSON/YAML parsing, version drift, and repo hygiene. `package` builds and verifies DMG for main/tag release paths. `release` publishes only for tags. Add workflow `concurrency`, and remove legacy Python path triggers from native release unless intentionally needed.
- **validation**: Workflow graph clearly blocks package/release on validate; tag-only release behavior is preserved; path filters match native ownership.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T2.3: Prepare Signing And Notarization Without Requiring Secrets

- **depends_on**: [T2.2]
- **location**: `scripts/build_native_dmg.sh`, `scripts/lib/native_dmg_helpers.sh`, `.github/workflows/build.yml`, release docs
- **description**: Keep ad hoc signing as default. Add optional Developer ID signing and notarization path when CI secrets are present. Use explicit secret names in docs and workflow comments, and ensure local builds continue without credentials.
- **validation**: No-secret local/CI build still works with ad hoc signing; documented secret-backed path uses `codesign`, `notarytool`, and staple in the correct order.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T2.4: Add Lightweight Quality Gates

- **depends_on**: [T2.1]
- **location**: `.swiftlint.yml`, `.swiftformat`, scripts, CI
- **description**: Add lightweight SwiftLint/SwiftFormat or equivalent check-only configuration plus standalone validation scripts. Do not run mass formatting. Add a repo hygiene script that fails on `.DS_Store`, duplicate Finder-style `* 2.*` files, and other known pollution patterns. These scripts are created here; T2.2 wires them into GitHub Actions.
- **validation**: Check-only commands run locally; existing code does not receive a broad formatting diff; hygiene script catches recreated duplicate files.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T3.1: Refresh Architecture Boundary Documentation

- **depends_on**: [T0.3]
- **location**: `README.md`, `docs/PROJECT_INDEX.md`, `MAINTENANCE_BASELINE.md`, `native/CPaperNative/README.md`
- **description**: Refresh architecture boundary docs only: native 6.x reality, active source, archived legacy, external site link placeholder, and where tests/build scripts live. Avoid release-flow details that depend on T2.2/T2.3.
- **validation**: A new contributor can read README + PROJECT_INDEX and correctly identify active source, tests, and legacy boundaries.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T3.2: Freeze Legacy Clearly

- **depends_on**: [T3.1, T2.2]
- **location**: `legacy/`, `.github/workflows/build.yml`, `.github/workflows/legacy-release.yml`, legacy release notes
- **description**: Document legacy as archival. Keep final legacy release workflow understandable, but prevent legacy docs or path triggers from implying it is part of the active native product. Python dependency locking is optional and only needed if legacy CI continues running.
- **validation**: Legacy workflow and docs describe archival status; native workflow is not triggered by ordinary legacy-only changes.
- **status**: Not Completed
- **log**:
- **files edited/created**:

### T3.3: Refresh Release And Validation Documentation

- **depends_on**: [T2.2, T2.3, T3.2]
- **location**: `README.md`, `docs/PROJECT_INDEX.md`, release notes, signing/notarization docs
- **description**: Update release, validation, install, privacy/disclaimer, and data-source reliability documentation after CI and signing/notarization placeholders are stable. Keep website references as external-link pending.
- **validation**: Public docs describe the actual validate/package/release flow and no longer conflict with workflow behavior.
- **status**: Not Completed
- **log**:
- **files edited/created**:

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
