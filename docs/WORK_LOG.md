# WORK_LOG

## Purpose

This file is a concise running log of meaningful code, configuration, and documentation changes. Future AI agents should append short factual entries after each code or configuration change.

## Entry Template

### YYYY-MM-DD — Short task title

**Task**
- What was requested.

**Changed**
- Files modified.
- Main code/config/documentation changes.

**Reason**
- Why the change was needed.

**Tested**
- Commands run.
- Files checked.
- Manual checks performed.

**Risks / Notes**
- Anything fragile.
- Anything not tested.
- Follow-up work.

## Entries

### 2026-06-24 — Fix invalid GitHub Actions scratch-path expression for release workflow

**Task**
- Fix the native GitHub Actions workflow after GitHub rejected `.github/workflows/build.yml` because the job-level `env` used an unsupported `runner.temp` expression.

**Changed**
- Updated `.github/workflows/build.yml` so `validate` and `package` now set `CPAPER_SWIFT_SCRATCH_PATH` with the runtime `RUNNER_TEMP` environment variable instead of `${{ runner.temp }}`.
- Updated `docs/WORK_LOG.md` with this workflow-fix entry.

**Reason**
- GitHub parses job-level expressions before the runner starts, and this workflow shape rejected `runner.temp` there. Using `RUNNER_TEMP` keeps the same scratch-path intent while matching what the runner shell can always provide at execution time.

**Tested**
- Inspected `.github/workflows/build.yml` around the failing lines and replaced both invalid expressions with the runtime-safe equivalent.
- Planned immediate follow-up validation: local YAML parse plus a new push to let GitHub re-parse the workflow.

**Risks / Notes**
- This is a workflow-only fix and does not change product code.
- GitHub-side execution still needs to be confirmed after the updated workflow is pushed.

### 2026-06-18 — Add installed-menu save-directory creation proof for a missing valid path

**Task**
- Continue release-quality hardening by proving that the installed AppKit menu “显示下载文件夹” command can still create and reveal a valid-but-missing save directory instead of surfacing a false error state.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu coverage asserting that dispatching “显示下载文件夹” against a creatable missing path creates the directory and leaves `saveDirectoryNotice` / `errorMessage` clear.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so download-chain evidence now explicitly includes the menu-driven save-directory creation path.

**Reason**
- Download reliability is not just cancellation and retry semantics. The file-system bridge from a user-invoked menu command into a real save directory also matters, especially when the path is valid but absent and should be created automatically instead of reported as a failure.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-save-dir-create swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-menu-save-dir-create --filter 'AppMenuCommandCenterTests/testInstalledRevealSaveDirectoryMenuItemCreatesMissingDirectoryWithoutNotice'`
- `git diff --check -- macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens AppKit-to-filesystem coverage without changing runtime behavior.
- It still does not automate the OS-level Finder success surface itself; it proves directory creation and the absence of an erroneous app-level failure state.

### 2026-06-18 — Keep installed diagnostic copy working while root error alerts block workflow commands

**Task**
- Continue release-quality hardening by proving that the installed AppKit menu can still copy the latest redacted diagnostic even when a root error alert is active and workflow-changing commands are intentionally blocked.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu coverage asserting that “复制最近诊断” remains enabled, “刷新当前视图” stays blocked, the root error alert is visible, and the copied diagnostic remains redacted.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so observability evidence now explicitly includes this alert-visible menu-copy path.

**Reason**
- Release-grade observability is not just about generating diagnostics. When the app is already in a blocking error state, the menu path for copying the latest report still needs proof because that is exactly when users most need a working escape hatch that does not mutate workflow state.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-save-dir-create swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-menu-save-dir-create --filter 'AppMenuCommandCenterTests/testInstalledCopyLatestDiagnosticMenuItemStillWorksWhileErrorAlertBlocksWorkflowCommands'`
- `rg -n '[[:blank:]]$|^(<<<<<<<|>>>>>>> )' macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens AppKit-to-observability coverage without changing runtime behavior.
- The proof stays at the app/UI boundary and does not attempt to automate broader macOS alert focus semantics beyond the installed menu dispatch path.

### 2026-06-18 — Let installed support-directory recovery escape a visible root error alert

**Task**
- Continue release-quality hardening by proving that the installed AppKit menu can still surface contextual support recovery even when a root error alert is already blocking workflow-changing commands.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu coverage asserting that “显示支持目录” stays available while “刷新当前视图” remains blocked by a visible root error alert, and that dispatching the menu item clears the opaque error alert into the visible support-directory notice with “重试打开”.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so observability evidence now explicitly includes this error-alert-to-support-notice menu recovery path.

**Reason**
- Release-grade recovery is not only about copying diagnostics. In a real blocked state, users also need proof that a non-workflow-changing recovery command can still transition the app from an opaque alert into a more actionable support surface.

**Tested**
- Pending targeted installed-menu verification for the error-alert support-directory recovery assertion.

**Risks / Notes**
- This strengthens AppKit-to-recovery observability coverage without changing runtime behavior.
- The proof still stays within app-level state and visible notices; it does not attempt to automate Finder success once the support path is valid.

### 2026-06-18 — Add installed-menu update-failure escalation proof into the root notice surface

**Task**
- Continue release-quality hardening by proving that the installed AppKit menu “检查更新...” command still reaches a visible SwiftUI recovery surface when the manual update check fails.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu coverage asserting that dispatching “检查更新...” through the real menu against a failing `UpdateService` produces a retryable update diagnostic and a visible root update notice with “重新检查”.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so update and observability evidence now explicitly includes this AppKit-to-SwiftUI manual-update-failure bridge.

**Reason**
- The remaining UI automation gap is increasingly about richer multi-step chains rather than local button wiring. Menu-driven update checking is a stable high-value bridge because it crosses the installed AppKit layer, runs async work, and must still end in a visible recovery surface.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-update-failure swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-menu-update-failure --filter 'AppMenuCommandCenterTests/testInstalledCheckForUpdatesMenuItemSurfacesVisibleRetryNoticeAfterFailure'`
- `git diff --check -- macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens menu-to-root update recovery proof without changing runtime behavior.
- It still does not prove broader first-responder or focus semantics beyond the explicit menu dispatch path.

### 2026-06-18 — Add installed-menu support-directory escalation proof into the root notice surface

**Task**
- Continue release-quality hardening by proving that the installed AppKit menu “显示支持目录” command still reaches a visible SwiftUI recovery surface when the support path is blocked.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu coverage asserting that dispatching “显示支持目录” against a file-blocked support path raises the support-directory diagnostic and makes the root support notice visible with its “重试打开” recovery action.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so observability and remaining P1 notes now explicitly include this AppKit-to-SwiftUI support-directory escalation proof.

**Reason**
- The remaining automation gap is no longer basic button wiring, but richer AppKit/SwiftUI chains. A menu-driven support-directory failure path is a stable high-value bridge case because it crosses the installed menu layer, mutates model state, and must still surface an actionable visible recovery notice.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-support-escalation swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-menu-support-escalation --filter 'AppMenuCommandCenterTests/testInstalledRevealSupportDirectoryMenuItemEscalatesIntoVisibleSupportNotice'`
- `git diff --check -- macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens menu-to-root observability proof without changing runtime behavior.
- The added evidence still does not fully cover broader first-responder or focus semantics across every editable surface.

### 2026-06-18 — Add rendered missing-artifact escalation proof for settings update reveal

**Task**
- Continue release-quality hardening by proving that the settings-page update “显示文件” action degrades into a visible retry path when the previously downloaded DMG is no longer present.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered coverage asserting that tapping settings update “显示文件” against a missing DMG flips update state into a retryable notice and exposes the visible “重新下载” action.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so update-chain evidence now explicitly includes missing-artifact escalation from the settings page, not only successful open/download flows and root-level retry notices.

**Reason**
- Release quality for updates depends not only on download/open happy paths, but also on whether stale local artifact state turns into an actionable visible recovery path at the UI surface where users inspect and reopen downloaded DMGs.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-update-reveal-missing swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-update-reveal-missing --filter 'RenderedWorkflowInteractionTests/testUpdateSettingsSectionRevealDownloadedFileMissingArtifactShowsRetryNotice'`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens visible update recovery proof without changing product behavior.
- The proof covers missing-artifact escalation, not the separate OS-driven Finder success path for an intact downloaded DMG.

### 2026-06-18 — Add rendered save-directory notice escalation proof from the downloads page

**Task**
- Continue release-quality hardening by proving that the visible downloads-page “显示文件夹” action does not fail silently when the configured save path is invalid.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered root-surface coverage asserting that tapping the downloads-page save-directory “显示文件夹” control against a file-backed invalid path raises the save-directory notice and exposes its visible “打开设置” recovery action.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so download-chain evidence now explicitly includes save-directory reveal escalation from the downloads page, not only cancellation, retry, and integrity-repair flows.

**Reason**
- File landing safety is not just about atomic writes and queue state; the user-visible path back out of a bad save-directory configuration also needs direct proof from the real downloads surface, because that is where broken landing paths become actionable.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-save-dir-escalation swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-save-dir-escalation --filter 'RenderedWorkflowInteractionTests/testRootViewDownloadsRevealSaveDirectoryInvalidPathShowsSaveDirectoryNotice'`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens visible download-path observability without changing product behavior.
- The proof covers invalid-path escalation, not the separate OS-driven Finder success path for already-valid directories.

### 2026-06-18 — Extend preview-failure observability proof into visible UI and root notice escalation

**Task**
- Continue release-quality hardening by proving that the preview-failure surface not only supports retry and repair, but also exposes working visible diagnostic and support-directory actions.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered coverage asserting that the preview-failure “复制诊断” action copies a redacted preview diagnostic report into `NSPasteboard`.
- Added rendered root-surface coverage asserting that tapping preview-failure “显示支持文件夹” escalates a blocked Finder/support-directory path into the root support-directory notice instead of failing silently.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so preview and observability evidence now explicitly includes preview-failure diagnostic copy and support-notice escalation.

**Reason**
- Preview is one of the four release-critical chains, and its visible failure surface still lacked direct proof for the two user actions that matter most once retry alone is not enough: capturing diagnostics and surfacing actionable support-directory guidance.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-preview-observability swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-preview-observability --filter 'RenderedWorkflowInteractionTests/testPDFPreviewViewCopyDiagnosticButtonCopiesRedactedPreviewFailureReport|RenderedWorkflowInteractionTests/testRootViewPreviewFailureRevealSupportDirectoryActionShowsSupportNotice'`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens visible preview-failure observability without widening runtime behavior.
- The new root-surface proof still stops at app-level notice escalation; it does not attempt broader OS-driven Finder success automation.

### 2026-06-18 — Add rendered diagnostic-copy proof for the downloads center

**Task**
- Continue release-quality hardening by proving that the downloads-center header “复制诊断” action really copies the latest download diagnostic from visible UI, instead of relying only on model-level or AppKit-level copy coverage.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered coverage asserting that the downloads-page header “复制诊断” button copies the latest recovered-download diagnostic report into `NSPasteboard`.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so observability evidence now explicitly includes download-center clipboard-copy behavior, not only settings, startup-failure, and menu-driven copy actions.

**Reason**
- Download recovery is one of the highest-signal failure surfaces in the app. Even with strong manager/model diagnostics and menu-level copy proof, the visible downloads-center copy action itself still lacked direct rendered verification.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-download-diag swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-download-diag --filter 'RenderedWorkflowInteractionTests/testDownloadsViewCopyDiagnosticButtonCopiesLatestDownloadRecoveryReport|RenderedWorkflowInteractionTests/testDownloadsViewRetryFailedButtonRestartsRecoveredInterruptedDownload'`
- `xcrun xctest -XCTest 'RenderedWorkflowInteractionTests/testDownloadsViewCopyDiagnosticButtonCopiesLatestDownloadRecoveryReport' /tmp/cpaper-native-swiftpm-download-diag/arm64-apple-macosx/debug/CPaperNativePackageTests.xctest`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- Current local `swift test` on this scratch path built the fresh bundle but exhibited the known quiet tail behavior, so the final assertion result was confirmed with direct `xcrun xctest` against the freshly built package test bundle.
- This strengthens visible download observability proof without changing product behavior.

### 2026-06-18 — Add rendered cancellation proof for the downloads center

**Task**
- Continue release-quality hardening by proving that the visible downloads-center “取消” action really cancels an in-flight queue and still preserves the file-safety contract instead of only relying on manager-level tests.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered coverage asserting that tapping the downloads-page “取消” button:
- cancels a real running queue from the visible UI
- moves the queue into a cancelled terminal state
- keeps the late-arriving file from being committed to its final destination
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so download-chain evidence now explicitly includes the downloads-center cancellation path, not only retry and repair flows.

**Reason**
- Download cancellation is part of the release-critical state machine and file-safety contract. The repo already had strong manager/model proof, but the user-visible downloads page still lacked direct rendered evidence for the main cancel action.

**Tested**
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-download-cancel swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-download-cancel --filter 'RenderedWorkflowInteractionTests/testDownloadsViewCancelButtonCancelsRunningQueueAndKeepsFileUncommitted|RenderedWorkflowInteractionTests/testDownloadsViewRetryFailedButtonRestartsRecoveredInterruptedDownload'`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This strengthens visible download-state proof without widening product behavior.
- The remaining UI-level gap is still broader first-responder/focus and richer AppKit-to-SwiftUI end-to-end chaining, not the basic downloads-page cancel/retry/repair controls themselves.

### 2026-06-18 — Execute stronger RC audit end to end on the active native worktree

**Task**
- Continue release-quality hardening by turning the newly added `--release-candidate` entrypoint from a documented stronger path into current-turn execution evidence on the active native worktree.

**Changed**
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` so the stronger current-turn proof is now backed by an actual successful `bash scripts/run_native_release_audit.sh --release-candidate` run, not just the existence of the entrypoint.
- Updated `docs/WORK_LOG.md` with the concrete stronger-RC execution record, including live-source and package-verification outcomes.

**Reason**
- The release-candidate matrix had already been tightened structurally, but release-quality confidence still depended on proving that the stronger path really passes end to end on the current native worktree, including the slowest and highest-signal checks.

**Tested**
- `bash scripts/run_native_release_audit.sh --release-candidate`

**Risks / Notes**
- Current-turn stronger RC evidence is now concrete: the run completed with the full Swift suite green, `RUN_LIVE_SOURCE_TESTS=1` canary green, release DMG creation successful, and DMG verification/mount checks green.
- A follow-up spike attempted to turn startup-failure retry recovery into a stricter root-hosted rendered assertion, but the current ViewInspector timing path was not yet stable enough to justify keeping that extra test in the suite. The existing adjacent-layer proof remains in place instead of merging brittle coverage.

### 2026-06-18 — Add explicit stronger RC audit mode

**Task**
- Continue release-quality hardening by reducing the remaining “remember the right audit flags” failure mode around package verification and live-source canaries.

**Changed**
- Updated `scripts/run_native_release_audit.sh` with `--release-candidate` and `--help`, so the stronger RC pass is now a named one-command mode instead of an implicit `--with-package --with-live-sources` combination.
- Updated `README.md`, `docs/RELEASE_AND_VALIDATION.md`, and `docs/RELEASE_CANDIDATE_AUDIT.md` so the stronger RC path is documented consistently as `bash scripts/run_native_release_audit.sh --release-candidate`.
- Updated `scripts/check_release_docs.sh` so release-doc consistency checks now require the new `--release-candidate` entrypoint to stay documented.

**Reason**
- The stronger RC path already existed in practice, but it still relied on contributors remembering a specific pair of optional flags. That is below the bar for a release-quality audit entrypoint because the highest-signal gate should be explicit and easy to invoke correctly.

**Tested**
- `bash scripts/run_native_release_audit.sh --help`
- `bash scripts/check_release_docs.sh`
- `git diff --check -- scripts/run_native_release_audit.sh scripts/check_release_docs.sh README.md docs/RELEASE_AND_VALIDATION.md docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This does not make package or live-source checks mandatory in the default audit path. It only makes the stronger RC mode explicit and harder to forget.

### 2026-06-18 — Add keyboard submit workflow coverage for search and batch filters

**Task**
- Continue release-quality hardening by shrinking the remaining UI interaction gap around keyboard-driven workflow entry, so the main search and batch filter surfaces do not rely on mouse-only primary actions.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift` so the search filter surface now treats text submission as a real search trigger whenever the current filter state is valid and idle.
- Updated `macos/Sources/CPaperNativeApp/Views/BatchFilterPanel.swift` so the batch filter surface now treats text submission as a real preview trigger whenever the current batch rule set is valid and idle.
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered submit-path coverage for:
- search-filter submit routing into `model.search()`
- batch-filter submit routing into `model.previewBatch()`
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` to record this keyboard-driven workflow proof as part of the remaining P1 UI-chain evidence.

**Reason**
- The remaining high-value UI gap was no longer another button tap, but whether the main workflow entry surfaces still honor keyboard-first submission semantics. That interaction path matters for release-quality confidence because it sits directly on the human-visible filter forms used to start search and batch preview work.

**Tested**
- `git diff --check -- macos/Sources/CPaperNativeApp/Views/SearchView.swift macos/Sources/CPaperNativeApp/Views/BatchFilterPanel.swift macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift macos/Tests/CPaperNativeTests/AppMenuControllerTests.swift`
- `env NSUnbufferedIO=YES CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-editmenu-responder2 swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-editmenu-responder2 --filter 'RenderedWorkflowInteractionTests/testSearchFilterPanelSubmitRunsSearchWorkflow|RenderedWorkflowInteractionTests/testBatchFilterPanelSubmitRunsPreviewWorkflow'`
- `env NSUnbufferedIO=YES xcrun xctest -XCTest 'RenderedWorkflowInteractionTests/testBatchFilterPanelSubmitRunsPreviewWorkflow' /tmp/cpaper-native-swiftpm-editmenu-responder2/arm64-apple-macosx/debug/CPaperNativePackageTests.xctest`

**Risks / Notes**
- Search and batch submit coverage both passed after tightening the tests to target the actual filter panels that own the submit semantics.
- `SearchFilterPanel` was made module-visible so the rendered test can verify the real submit owner directly without widening runtime behavior.

### 2026-06-18 — Close startup-failure rendered observability gap

**Task**
- Continue release-quality hardening by proving that the startup-failure surface not only shows diagnostics, but also routes the visible “复制诊断信息” and “显示支持文件夹” failure path into real user-visible outcomes after SwiftUI rendering.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/RootView.swift` so `StartupFailureView` exposes the same lightweight inspection hook pattern already used by other rendered-test surfaces, without changing runtime behavior.
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` so startup-failure coverage now uses hosted rendered inspection to assert:
- “复制诊断信息” copies the startup diagnostic text into `NSPasteboard`
- “显示支持文件夹” surfaces the contextual alert when Finder reveal fails, including the actionable redacted path and failure reason
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` to record this startup-failure observability proof.

**Reason**
- The remaining high-signal gap in visible observability proof was no longer settings or ready-state notices, but the boot-failure surface itself: release-quality confidence still benefited from proving that startup diagnostics can be copied and that support-folder reveal failures become actionable alerts instead of silent no-ops.

**Tested**
- `env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-startup-failure-diag-next2 swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-startup-failure-diag-next2 --filter 'RenderedWorkflowInteractionTests/testRootViewStartupFailureRevealSupportDirectoryFailureShowsContextualAlert'`
- `env NSUnbufferedIO=YES xcrun xctest -XCTest RenderedWorkflowInteractionTests/testRootViewStartupFailureRevealSupportDirectoryFailureShowsContextualAlert /tmp/cpaper-native-swiftpm-startup-failure-diag-next2/arm64-apple-macosx/debug/CPaperNativePackageTests.xctest`

**Risks / Notes**
- This closes the startup-failure observability gap for rendered copy/alert behavior, but it still does not prove broader OS-driven Finder integration or first-responder behavior outside the hosted test harness.

### 2026-06-18 — Prove startup-failure retry dispatch across view and coordinator layers

**Task**
- Continue release-quality hardening by proving that the startup-failure surface does not stop at passive diagnostics: the visible “重试” control must dispatch a real retry action, and the boot coordinator must still recover from a failed initialization into the ready phase.

**Changed**
- Kept `StartupBootCoordinatorTests.swift` as the coordinator-level proof that a first failed initialization can recover into `.ready` on retry without changing product logic.
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with hosted rendered coverage asserting that `StartupFailureView`’s visible “重试” button invokes its retry callback exactly once.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so startup-failure evidence now explicitly includes retry dispatch at the visible view layer plus recovery semantics at the coordinator layer.

**Reason**
- Startup-failure quality would still be incomplete if the surface only proved diagnostics and alerts. Release confidence also needs evidence that the visible recovery affordance is wired and that retry remains a real path back into the app.

**Tested**
- `env NSUnbufferedIO=YES xcrun xctest -XCTest RenderedWorkflowInteractionTests/testStartupFailureViewRetryButtonInvokesRetryAction /tmp/cpaper-native-swiftpm-startup-failure-diag-next2/arm64-apple-macosx/debug/CPaperNativePackageTests.xctest`
- Existing coordinator recovery proof in `StartupBootCoordinatorTests.testRetryRecoversAfterInitializationFailure`

**Risks / Notes**
- This proves retry dispatch and recovery semantics across adjacent layers, but it still stops short of a single root-hosted end-to-end assertion that the full `RootView` shell visibly transitions from failure UI into ready UI after tapping retry.

### 2026-06-18 — Extend diagnostic observability proof into visible UI and AppKit menu copy paths

**Task**
- Continue release-quality hardening by proving that user-facing diagnostic copy actions still emit the redacted latest report through real visible UI and installed menu items, not only through model-level formatting tests.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered coverage asserting that the visible settings notice “复制诊断” action copies a redacted diagnostic report into `NSPasteboard`.
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu coverage asserting that “复制最近诊断” copies the latest diagnostic report into `NSPasteboard`, preserving area labeling while redacting credentials, tokens, and the home-directory path.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so observability proof now explicitly includes real clipboard-copy paths from both SwiftUI and AppKit surfaces.

**Reason**
- Observability quality was already strong at the formatting/model level, but release-quality confidence still benefited from proving that the actual user-visible copy actions route the right redacted content all the way into the system clipboard.

**Tested**
- `source scripts/lib/swiftpm_retry_helpers.sh && CPAPER_SWIFTPM_RETRY_ATTEMPTS=3 run_swiftpm_command_with_retry "rerunning RenderedWorkflowInteractionTests and AppMenuCommandCenterTests after diagnostic copy coverage" env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-diagnostic-copy swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-diagnostic-copy --filter 'RenderedWorkflowInteractionTests|AppMenuCommandCenterTests'`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This raises confidence in visible diagnostics handling, but it still does not provide full OS-driven focus or first-responder automation across every input surface.

### 2026-06-18 — Close rendered retry-recovery gaps for download and update notices

**Task**
- Continue release-quality hardening by proving the still-visible retry recovery paths that matter most for release risk: retrying failed search/batch download starts from inline download notices, and retrying a failed update download from the root update notice.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- search-page inline `downloadNotice` “重试下载” after an initial startup-stage download failure, ending in a queued download and cleared notice
- batch-page inline `downloadNotice` “重试下载” after an initial startup-stage download failure, ending in a queued download and cleared notice
- root-level `UpdateNoticeCard` “重试下载” after an initial update download failure, ending in a downloaded DMG, cleared notice, and invoked open path
- Added small rendered-test helpers that force a real first-attempt failure and a successful retry without changing product behavior.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the download/update rows and remaining UI-gap note now record these rendered retry-recovery assertions.

**Reason**
- The highest-value remaining rendered gap was no longer happy-path execution, but whether the visible retry controls for release-relevant failure states still reran the correct workflows after real SwiftUI rendering.

**Tested**
- `source scripts/lib/swiftpm_retry_helpers.sh && CPAPER_SWIFTPM_RETRY_ATTEMPTS=3 run_swiftpm_command_with_retry "rerunning RenderedWorkflowInteractionTests after download/update retry coverage" env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-rendered-retry-notices swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-rendered-retry-notices --filter RenderedWorkflowInteractionTests`
- `git diff --check -- macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift docs/RELEASE_CANDIDATE_AUDIT.md docs/WORK_LOG.md`

**Risks / Notes**
- This closes the visible retry-notice gap for download start and update download recovery, but broader first-responder and OS-driven focus behavior is still outside the current rendered proof envelope.

### 2026-06-18 — Close SubjectPicker popover rendered-interaction gap

**Task**
- Continue release-quality hardening by proving that the searchable subject picker popover behaves correctly after real SwiftUI rendering, including selection side effects and dismiss/reopen reset behavior.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/InspectionSupport.swift` with reusable popover inspection support so active SwiftUI popovers can be inspected without changing runtime behavior.
- Updated `macos/Sources/CPaperNativeApp/Views/SearchControls.swift` so `SubjectPicker` uses the inspectable popover wrapper, exposes inspection hooks for ViewInspector-driven rendered tests, and resets the transient popover query before reopening the subject picker.
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage proving that:
- selecting a subject through the searchable popover clears the manual subject-code override
- dismissing the popover and reopening it resets the transient search query and restores the full subject list
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` to record this narrower but real rendered proof for manual subject-selection behavior.

**Reason**
- The remaining failure was no longer product workflow logic in search or batch, but an unproven input-chain edge: the searchable `SubjectPicker` popover still lacked rendered interaction proof, and the tests exposed that reopening the picker could retain stale transient query state.

**Tested**
- `source scripts/lib/swiftpm_retry_helpers.sh && CPAPER_SWIFTPM_RETRY_ATTEMPTS=3 run_swiftpm_command_with_retry "final rerun RenderedWorkflowInteractionTests after staged reopen delay" env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-rendered-popover swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-rendered-popover --filter RenderedWorkflowInteractionTests`
- `source scripts/lib/swiftpm_retry_helpers.sh && CPAPER_SWIFTPM_RETRY_ATTEMPTS=3 run_swiftpm_command_with_retry "rerunning AppMenuControllerTests after SubjectPicker-native inspection" env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-editmenu-4 swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-editmenu-4 --filter AppMenuControllerTests`

**Risks / Notes**
- This closes a real rendered-interaction gap for manual subject selection, but broader AppKit first-responder and richer OS-level focus behavior are still outside the current proof envelope.

### 2026-06-18 — Remove SubjectPicker rendered-test concurrency noise

**Task**
- Tighten the new `SubjectPicker` rendered-interaction coverage by eliminating Swift 6 sendability noise in the test harness without changing tested behavior.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` so the temporary `SubjectSelectionBox` used by `SubjectPicker` rendered tests is explicitly main-actor-bound and sendability-tolerant for the inspection-driven binding closures.

**Reason**
- The previous rendered test pass was green, but it still emitted avoidable `Sendable` warnings from the temporary selection box closures, which is below the bar for release-quality verification noise.

**Tested**
- `source scripts/lib/swiftpm_retry_helpers.sh && CPAPER_SWIFTPM_RETRY_ATTEMPTS=3 run_swiftpm_command_with_retry "rerunning RenderedWorkflowInteractionTests after SubjectSelectionBox sendable cleanup" env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-rendered-popover swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-rendered-popover --filter RenderedWorkflowInteractionTests`

**Risks / Notes**
- This is test-only cleanup; it does not widen product behavior or change the rendered interaction contract already proven in the previous entry.

### 2026-06-18 — Gate AppKit workflow menu commands while root modal UI is active

**Task**
- Continue release-quality hardening by proving that AppKit menu-driven workflow commands do not punch through root-level modal UI such as the settings sheet, startup update prompt, or error alert state.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/RootView.swift` so `ReadyRootMenuBindings` now treats root modal state as a blocker for workflow-changing menu commands, including refresh, route switching, manual update checks, and reopening settings while settings / pending-update / error-alert UI is active.
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu assertions that:
- workflow menu items stay disabled while the settings sheet is presented
- workflow menu items stay disabled while the startup pending-update prompt is visible
- error-alert state still keeps “复制最近诊断” available even while workflow-changing commands are blocked
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` to record this tighter AppKit modal-state proof.

**Reason**
- The remaining AppKit gap was no longer simple menu routing, but whether modal root UI actually owns command flow. Before this pass, menu-driven refresh and route changes could still be considered executable even when a sheet or alert should have been the active interaction surface.

**Tested**
- `source scripts/lib/swiftpm_retry_helpers.sh && run_swiftpm_command_with_retry "running AppMenuCommandCenterTests" env CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-modal swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-menu-modal --filter AppMenuCommandCenterTests`

**Risks / Notes**
- This closes a real menu/modal coordination gap, but it still does not provide full first-responder automation for text input or broader OS-driven UI focus coverage.

### 2026-06-18 — Extend rendered workflow coverage into visible search and batch retry recovery

**Task**
- Continue release-quality hardening by proving two visible retry workflows after SwiftUI rendering: retrying a failed search from the inline source notice, and retrying a failed batch preview from the batch workflow surface.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- search-page first-failure to inline “重试搜索” recovery, ending in loaded results and restored source summary
- batch-page first-failure to inline “重试预览” recovery, ending in loaded preview files and restored source summary
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the search row and remaining UI-gap notes now record these rendered retry-recovery assertions.

**Reason**
- The next high-value UI gap was not more happy-path clicks, but whether the visible failure-recovery controls for search and batch still actually reran the intended workflows after rendering.

**Tested**
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm --filter RenderedWorkflowInteractionTests`
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-audit bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass improves proof for visible retry semantics in search and batch, but it still does not provide full app-level focus automation or richer AppKit end-to-end chaining.

### 2026-06-18 — Extend rendered root workflow coverage into full search and batch route handoffs

**Task**
- Continue release-quality hardening by proving two longer root-surface user flows: running a search then handing its results into the downloads center, and generating a batch preview then handing that batch into the downloads center.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with root-level rendered interaction coverage for:
- `RootView` search flow: route-aware toolbar refresh loads result files and source summary, then “下载当前结果” switches the app into the downloads route with a queued task
- `RootView` batch flow: route-aware toolbar refresh loads preview files and source summary, then “选择目录并下载” switches the app into the downloads route with a queued task
- Added a combined rendered test helper that wires the native source registry and download manager together so these route-spanning workflows run against the real root shell instead of isolated subpanels.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the remaining UI-gap note now records these longer root-surface chains explicitly.

**Reason**
- The highest-value remaining UI gap was not another isolated button proof, but whether visible multi-step workflows still survive a real `RootView` route transition after async search or batch preview work completes.

**Tested**
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-root swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-root --filter RenderedWorkflowInteractionTests`
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-root-audit bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass strengthens real route-spanning SwiftUI workflow proof, but it still does not exercise AppKit focus, menu routing, or full OS-level UI automation.

### 2026-06-18 — Extend AppKit menu command coverage into live workflow refresh and recovery routing

**Task**
- Continue release-quality hardening by proving that installed macOS menu items do more than flip local flags: they must drive the real route-aware workflows for search, batch preview, and downloads recovery through the live menu-command bridge.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` with installed-menu interaction coverage for:
- the View menu “刷新当前视图” item re-running a real search workflow when the app is on the search route
- the View menu “刷新当前视图” item re-running a real batch preview workflow when the app is on the batch route
- the View menu “下载” item switching into the downloads route and triggering interrupted-session recovery state refresh
- Added small menu-test helpers and source/download stubs so these assertions run through `AppMenuController` menu items plus `AppMenuCommandCenter` dispatch instead of direct command-method calls alone.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the remaining UI-gap note now records menu-driven AppKit workflow proof explicitly.

**Reason**
- The next meaningful gap after rendered root-surface chains was the AppKit bridge itself: whether installed menu items still route into the correct async product workflows once the real macOS menu layer is in play.

**Tested**
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm-menu --filter AppMenuCommandCenterTests`
- `git diff --check`
- Attempted `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-audit bash scripts/run_native_release_audit.sh`, but this turn hit repeated transient SwiftPM `input file ... was modified during the build` failures before the full suite could complete.

**Risks / Notes**
- This pass proves menu-driven AppKit-to-model workflow routing, but it still does not cover keyboard focus, first-responder behavior, or full OS-driven UI automation.
- Default release audit was attempted three times in this turn and each run was interrupted by the known local SwiftPM transient “input file was modified during the build” issue rather than a test assertion failure.

### 2026-06-18 — Auto-retry known SwiftPM transient build noise in native audit and package scripts

**Task**
- Continue release-quality hardening by closing a real validation-path weakness exposed on the active worktree: local native release audits and package builds could still fail spuriously with SwiftPM’s transient `input file ... was modified during the build` error, forcing manual reruns.

**Changed**
- Added `scripts/lib/swiftpm_retry_helpers.sh` with a shared wrapper that detects the known SwiftPM transient modified-during-build failure and retries the command a small number of times before surfacing a real error.
- Updated `scripts/run_native_release_audit.sh` so both the default full Swift suite and the optional live-source canary run through that retry wrapper.
- Updated `scripts/build_native_dmg.sh` so local Swift builds for native packaging use the same retry wrapper.
- Updated `.github/workflows/build.yml` so the validate Swift-test step also uses the same retry helper, and the workflow shell-syntax check now covers that helper file too.
- Updated `scripts/check_release_docs.sh` so release-doc consistency checks enforce the new retry-helper contract in workflow/docs/index state.
- Updated `docs/RELEASE_AND_VALIDATION.md`, `docs/PROJECT_INDEX.md`, `docs/RELEASE_CANDIDATE_AUDIT.md`, and `docs/WORK_LOG.md` to record the new local audit/build behavior.

**Reason**
- The project had already moved SwiftPM scratch output outside the repository tree, but current-turn evidence showed that local validation still needed manual reruns when SwiftPM emitted the same transient modified-during-build noise. That made the default audit path less repeatable than the release-quality goal requires.

**Tested**
- `bash -n scripts/build_native_dmg.sh scripts/run_native_release_audit.sh scripts/lib/swiftpm_retry_helpers.sh`
- `bash scripts/check_release_docs.sh`
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-menu-audit bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- The retry wrapper only handles the known SwiftPM transient modified-during-build failure; it intentionally does not mask unrelated build/test failures.
- Current-turn audit evidence: the first `swift test` build hit the known SwiftPM transient modified-during-build error once, the wrapper retried automatically, and the overall default audit then passed with `277` tests run, `7` skipped, and `0` failures.

### 2026-06-18 — Extend rendered workflow coverage into visible search execution and startup update download

**Task**
- Continue release-quality hardening by proving two still-visible multi-step workflows after SwiftUI rendering: executing a real search from the search page, and downloading a newly available update directly from the startup prompt.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- search-page “搜索” loading result files and source-summary state through the visible search action
- root startup update prompt “下载更新” downloading the DMG and invoking the downloaded-file open path
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the search/update rows and remaining UI-gap notes now record these rendered workflow assertions.

**Reason**
- The remaining high-value UI gap was no longer only route switches or local recovery buttons, but full user-visible workflow jumps where a visible action causes async state transitions and new durable artifacts.

**Tested**
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm --filter RenderedWorkflowInteractionTests`
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-audit bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass improves proof for two more multi-step workflows, but it still does not provide app-level focus automation or full AppKit end-to-end interaction coverage.

### 2026-06-18 — Extend rendered workflow coverage into batch download initiation and settings-page update download

**Task**
- Continue release-quality hardening by proving two still-visible workflow jumps after SwiftUI rendering: starting a batch download into the downloads center, and triggering the settings-page update download path through the real UI action.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- batch-page “选择目录并下载” starting the queued download and switching into the downloads route
- settings-page “下载更新” starting the update download, writing the DMG, and invoking the downloaded-file open path
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the download/update rows and remaining UI-gap notes now record these rendered workflow assertions.

**Reason**
- The remaining rendered gap was no longer basic single-surface controls, but user-visible workflow jumps that cross state boundaries: batch preview into queued downloads, and available update into downloaded local artifact.

**Tested**
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm --filter RenderedWorkflowInteractionTests`
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-audit bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass still stops short of full app-level UI automation; it proves the SwiftUI wiring for two more cross-state workflows, not AppKit focus or multi-window behavior.

### 2026-06-18 — Extend rendered downloads-center recovery coverage into retry and integrity repair actions

**Task**
- Continue release-quality hardening by proving that the downloads-center recovery buttons still drive the intended retry and repair workflows after SwiftUI rendering, not only in model/service tests.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- downloads-page “重试失败项” restarting a restored interrupted task and clearing the startup recovery notice/summary
- downloads-page integrity notice “重新下载受影响文件” requeueing a missing completed file and clearing the integrity notice after repair
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the download row and remaining UI-gap notes now record these rendered recovery assertions.

**Reason**
- The highest-value remaining downloads gap was no longer whether the recovery model logic existed, but whether the visible downloads-center controls still actually triggered those recovery paths after rendering.

**Tested**
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm swift test --jobs 1 --scratch-path /tmp/cpaper-native-swiftpm --filter RenderedWorkflowInteractionTests`
- `CPAPER_SWIFT_SCRATCH_PATH=/tmp/cpaper-native-swiftpm-audit bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass proves the visible retry/repair buttons in the downloads center, but it still does not add full app-level UI automation for richer focus and multi-window AppKit behavior.

### 2026-06-18 — Move SwiftPM scratch output out of the repository for more stable native audits

**Task**
- Continue release-quality hardening by fixing a new validation-path weakness: repeated local native release audits could fail during SwiftPM compilation with transient “input file was modified during the build” errors inside the repository worktree.

**Changed**
- Updated `scripts/run_native_release_audit.sh` so the default full test run and optional live-source canary use `--scratch-path "$CPAPER_SWIFT_SCRATCH_PATH"` with a temp-directory default outside the repository tree.
- Updated `scripts/build_native_dmg.sh` so reusable Swift build artifacts are discovered and built through the same redirected SwiftPM scratch path instead of the repository-local `.build/`.
- Updated `.github/workflows/build.yml` so `validate` and `package` export `CPAPER_SWIFT_SCRATCH_PATH` under the runner temp directory, and the validate Swift test step now passes the explicit scratch path.
- Updated `scripts/check_release_docs.sh` and `docs/RELEASE_AND_VALIDATION.md` so release-doc consistency checks and native release docs both require and describe the redirected SwiftPM scratch path.

**Reason**
- The active checkout lives under `Documents`, and the repo already had evidence that file-provider metadata can interfere with build artifacts. Once the same class of environment noise started breaking `run_native_release_audit.sh` itself during SwiftPM compilation, the validation path needed a structural fix rather than repeated reruns.

**Tested**
- Pending in this entry; see follow-up validation commands after the script and workflow changes are re-verified.

**Risks / Notes**
- This change targets build-repeatability only. It does not change app behavior or eliminate all possible external file-provider interference outside SwiftPM scratch output.

### 2026-06-18 — Extend rendered preview coverage into failure recovery actions

**Task**
- Continue release-quality hardening by moving the preview workflow beyond pure service/model proof and asserting that the visible failure-recovery actions still drive the intended model behavior after SwiftUI rendering.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- preview failure “重试预览” resetting the failure state and bumping the preview reload revision
- preview failure “重新下载文件” starting the repair download and automatically returning the preview workflow to retry state after a successful local repair path
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the preview row now records rendered recovery proof instead of describing preview as service/model-only evidence.

**Reason**
- The preview pipeline had become technically strong, but the audit still called out that its proof stopped below the user-visible layer. The highest-value remaining preview gap was whether the inline recovery controls actually still invoked the intended model workflow.

**Tested**
- Pending in this entry; see follow-up validation commands after the test changes compile.

**Risks / Notes**
- This pass proves the preview failure recovery controls, not broader preview selection/focus behavior or real PDF rendering at the AppKit view layer.

### 2026-06-18 — Extend rendered workflow coverage into cross-panel download and recovery flows

**Task**
- Continue release-quality hardening by proving two real cross-panel user flows that were still weaker than the surrounding model/service tests: starting a search download into the downloads center, and escalating a save-directory recovery notice into the settings sheet.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- search-page “下载当前结果” starting a real queued download and switching `model.route` into `.downloads`
- downloads-page save-directory notice primary action presenting the root settings sheet
- Expanded the rendered-test helpers so this file can build a download-capable native test model and wait for async route/queue updates without changing app behavior.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the audit record now distinguishes these cross-panel assertions from the still-open broader end-to-end interaction gap.

**Reason**
- The main remaining UI gap was no longer isolated controls, but user flows that cross workflow boundaries: success paths that leave one panel for another, and failure-recovery paths that jump from an inline notice into settings.

**Tested**
- `swift test --jobs 1 --filter RenderedWorkflowInteractionTests`
- `swift test --jobs 1`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass improves cross-panel proof for one success path and one recovery path, but it still does not cover richer focus semantics or full multi-step end-to-end UI automation.

### 2026-06-18 — Extend rendered root-shell coverage into settings-sheet lifecycle and error-alert actions

**Task**
- Continue release-quality hardening by covering two root-shell interaction gaps still called out by the audit: settings sheet lifecycle and root error-alert button behavior.

**Changed**
- Added `macos/Sources/CPaperNativeApp/Views/InspectionSupport.swift` and updated `macos/Sources/CPaperNativeApp/Views/RootView.swift` so the settings sheet uses an inspectable wrapper equivalent to SwiftUI’s normal sheet presentation, enabling rendered lifecycle assertions without changing product behavior.
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- root toolbar “设置” action presenting the settings sheet and allowing sheet dismissal back into model state
- root error alert clearing `errorMessage` through the visible “好” action
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the audit record now reflects these root-shell interaction assertions while keeping the broader UI end-to-end gap open.

**Reason**
- The remaining interaction blind spot in the active shell was no longer ordinary route switching, but modal and alert wiring that users hit across workflows. Those branches were explicitly listed in the audit as not yet proven by rendered interaction tests.

**Tested**
- `swift test --jobs 1 --filter RenderedWorkflowInteractionTests`
- `swift test --jobs 1`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass improves root-shell modal/alert proof only. It still does not cover broader multi-panel chaining or focus behavior.

### 2026-06-18 — Extend rendered interaction coverage into root toolbar and startup update prompt

**Task**
- Continue release-quality hardening by expanding the first rendered SwiftUI interaction layer from sidebar/settings surfaces into the root workflow shell.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- root toolbar “下载” action switching the active route
- root startup update prompt primary action invoking the downloaded-DMG open path
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the audit record now distinguishes these root-shell interaction assertions from the still-open broader UI workflow gap.

**Reason**
- After the first rendered tests landed, the biggest remaining unproven visible wiring in the active shell was not inside sidebar/settings subviews anymore, but in `RootView` itself: toolbar actions and startup update prompt behavior that users hit before or outside deeper workflow panels.

**Tested**
- `swift test --jobs 1 --filter RenderedWorkflowInteractionTests`
- `swift test --jobs 1`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass proves root-shell interaction on two high-value controls, but it still does not cover settings sheet presentation lifecycle, error-alert button actions, or cross-panel workflow chains.

### 2026-06-18 — Add first rendered SwiftUI interaction tests for sidebar and settings workflows

**Task**
- Continue release-quality hardening by moving one step beyond pure presentation tests and proving that selected visible controls still behave correctly after SwiftUI rendering.

**Changed**
- Updated `Package.swift` to add the test-only `ViewInspector` dependency for SwiftUI view inspection.
- Added `macos/Tests/CPaperNativeTests/RenderedWorkflowInteractionTests.swift` with rendered interaction coverage for:
- sidebar “下载” route switching
- settings-page support/settings notice rendering
- settings-page downloaded-update “打开 DMG” action invocation
- settings-page update button disablement while a download is in flight
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the audit record now distinguishes these rendered interaction assertions from the broader remaining end-to-end UI gap.

**Reason**
- The repo had strong service/model proof and growing pure presentation coverage, but still lacked any automated check that real rendered SwiftUI controls on the active macOS surfaces actually invoke the intended actions or reflect disabled state correctly.

**Tested**
- `swift test --jobs 1 --filter RenderedWorkflowInteractionTests`
- `swift test --jobs 1`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This is the first rendered-interaction layer, not a full app-level UI automation stack.
- The strongest remaining gap is still broader multi-surface interaction coverage for toolbar, alerts, sheets, and full workflow chaining.

### 2026-06-18 — Extend workflow presentation coverage into root and settings surfaces

**Task**
- Continue release-quality hardening by reducing another visible-workflow blind spot: root-level alerts/notices and settings-page update/support actions that still depended on implicit SwiftUI branches.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` with `RootWorkflowPresentation`, `SettingsWorkflowPresentation`, and `UpdateSettingsWorkflowPresentation`.
- Updated `macos/Sources/CPaperNativeApp/Views/RootView.swift`, `SettingsView.swift`, and `SettingsInfoSections.swift` so root notice stacking, refresh-route dispatch, error/update prompt state, settings notices, update action visibility, and support-diagnostic button availability now route through shared presentation state.
- Expanded `macos/Tests/CPaperNativeTests/WorkflowPresentationTests.swift` with direct coverage for root prompt wording, root alert affordances, route-specific refresh semantics, settings-page update button visibility/disablement, and diagnostic availability.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the audit record now reflects broader root/settings workflow proof without claiming full UI automation.

**Reason**
- The previous pass covered search, batch, downloads, and part of update visibility, but the remaining root/settings surfaces still encoded important user-facing behavior directly in view branches. That left cross-panel update/support presentation more fragile than the surrounding tested model logic.

**Tested**
- `swift test --jobs 1 --filter WorkflowPresentationTests`
- `swift test --jobs 1`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass still stops at pure presentation/state verification; it does not add real AppKit/SwiftUI interaction automation.
- One intermediate audit run observed a transient full-suite failure that did not reproduce on immediate full-suite rerun; the final validated state for this entry is green on `swift test --jobs 1` and `bash scripts/run_native_release_audit.sh`.

### 2026-06-18 — Fix concurrent update finalization race and extend downloads-page presentation coverage

**Task**
- Continue release-quality hardening by closing two remaining weak spots: implicit downloads-page visibility logic and a real concurrent update finalization race exposed by the default audit.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` with `DownloadsWorkflowPresentation`, plus download header-action and queue-badge enums.
- Updated `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` so top notices, recovery summary, header buttons, queue badge, and empty-state rendering now reuse shared presentation state instead of duplicating SwiftUI condition branches.
- Expanded `macos/Tests/CPaperNativeTests/WorkflowPresentationTests.swift` with direct coverage for downloads-page action/badge/empty-state decisions.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/StagedFileSystem.swift` so staged finalization now falls back from `moveItem` to `replaceItemAt` when another concurrent writer creates the destination between existence check and final move.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` so the audit matrix now records downloads-page presentation coverage and the update-artifact race fix.

**Reason**
- The downloads page still relied on several duplicated visible-state branches, and the default release audit exposed a real update-path race where concurrent DMG downloads could fail with a `File exists` error during final commit.

**Tested**
- `swift test --jobs 1 --filter 'UpdateServiceTests/testDownloadUpdateUsesUniquePartialFilesForConcurrentRequests'`
- `swift test --jobs 1 --filter StagedFileSystemTests`
- `swift test --jobs 1 --filter WorkflowPresentationTests`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass hardens concurrent final-file landing for both update and generic staged-write callers, but it still relies on local filesystem semantics rather than a dedicated file-lock protocol.
- Full UI interaction automation remains an open gap even though more visible state is now covered as pure presentation logic.

### 2026-06-18 — Extract workflow presentation state for visible search, batch, and update wiring

**Task**
- Reduce drift in human-visible workflow wiring by extracting the most duplicated SwiftUI visibility and action-label conditions into directly testable presentation state instead of leaving them implicit inside view branches.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` with `SearchWorkflowPresentation`, `BatchPreviewWorkflowPresentation`, and `UpdateWorkflowPresentation`.
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift`, `BatchPreviewPanel.swift`, `SettingsInfoSections.swift`, and `RootView.swift` so those views now consume shared presentation state for route-scoped notices, source-summary visibility, and update action labels.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so update notice reveal text also routes through the shared update presentation state.
- Added `macos/Tests/CPaperNativeTests/WorkflowPresentationTests.swift` with direct coverage for search/batch notice scoping and update call-to-action/reveal text decisions.
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` and `docs/WORK_LOG.md` to record that this closes part of the visible-workflow proof gap without claiming full UI automation.

**Reason**
- The visible workflow behavior was increasingly correct but still partly enforced by duplicated SwiftUI conditionals. That made search, batch, and update surfaces more drift-prone than the surrounding model logic and harder to verify surgically.

**Tested**
- `swift test --jobs 1 --filter WorkflowPresentationTests`
- `bash scripts/run_native_release_audit.sh`
- `git diff --check`

**Risks / Notes**
- This pass improves proof for visible workflow decisions, but it does not add UI interaction automation or snapshot coverage.
- The strongest remaining UI-related gap is still full end-to-end assertion of real rendered interaction flows.

### 2026-06-18 — Re-run stronger RC package and live-source evidence on current worktree

**Task**
- Upgrade the release-candidate audit from “default local gates passed” to stronger current-turn evidence by rerunning package verification and live third-party source checks on the active worktree.

**Changed**
- Updated `docs/RELEASE_CANDIDATE_AUDIT.md` so package verification and live source behavior are now marked as proven in the current turn instead of only partially proven from older evidence.
- Updated `docs/WORK_LOG.md` with the stronger RC evidence for the active native release candidate.

**Reason**
- After the previous turn, the main remaining weak spot in the audit matrix was not missing implementation but missing fresh proof. The package path and live canary had older evidence, but not current-turn confirmation against the latest worktree.

**Tested**
- `bash scripts/run_native_release_audit.sh --with-package`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`

**Risks / Notes**
- Live source checks are still external-dependency canaries and may fail in future turns without implying a local regression.
- Credentialed Developer ID signing and notarization remain outside ordinary local verification.

### 2026-06-18 — Add release-candidate audit matrix and direct download-session recovery tests

**Task**
- Turn the broad native release-quality goal into an auditable requirement matrix, then close one weak-evidence gap in the restart-recovery path instead of continuing with unstructured hardening.

**Changed**
- Added `docs/RELEASE_CANDIDATE_AUDIT.md` to map the release-candidate goal onto concrete current evidence, partial proof, and remaining gaps.
- Updated `docs/PROJECT_INDEX.md` and `docs/RELEASE_AND_VALIDATION.md` so the new audit artifact is discoverable from the native documentation path.
- Added `macos/Tests/CPaperNativeTests/DownloadSessionStoreTests.swift` with direct coverage for corrupt persisted session fallback and interrupted-session normalization, including partial-file cleanup and preservation of already-terminal items.

**Reason**
- The repository already had substantial release-hardening work, but the proof was scattered. The most immediate weak spot was download-session recovery: important behavior existed, but the evidence was mostly indirect.

**Tested**
- `bash scripts/run_native_release_audit.sh`
- `swift test --jobs 1 --filter DownloadSessionStoreTests`

**Risks / Notes**
- The new audit matrix is an internal engineering artifact, not a public release note.
- UI-level workflow assertions and credentialed signing/notarization validation remain open release-quality gaps.

### 2026-06-18 — Add one-command native release audit entrypoint

**Task**
- Continue release hardening by turning the now-scattered native validation, release-doc checks, full tests, and optional package/live canaries into one reusable local audit command.

**Changed**
- Added `scripts/run_native_release_audit.sh` to run shell syntax checks, `version.json` parsing, workflow YAML parsing, release-documentation consistency, version drift, repo hygiene, and `swift test --jobs 1`, with optional `--with-package` and `--with-live-sources` extensions.
- Updated `README.md`, `docs/RELEASE_AND_VALIDATION.md`, and `docs/PROJECT_INDEX.md` so the new audit entrypoint is documented as the default local release-candidate validation command.

**Reason**
- The repository had strong release evidence, but it was spread across many manual commands. That made release-grade verification harder to repeat consistently than the underlying gates warranted.

**Tested**
- Not yet run in this entry; see follow-up validation commands after code changes.

**Risks / Notes**
- The default audit path does not force package or live-source checks; those remain opt-in because they are slower and, for live sources, externally unstable.

### 2026-06-18 — Reuse one executable DMG verification gate across local and CI packaging

**Task**
- Continue release hardening by extracting the workflow’s inline DMG verification shell into a reusable script so local package audits and CI package verification use the same checks.

**Changed**
- Added `scripts/verify_native_dmg.sh` to verify the latest or specified native DMG with `hdiutil verify`, mount checks for `CPaperNative.app`, `Applications` symlink, `.background/background.png`, and strict codesign verification on the mounted app.
- Updated `.github/workflows/build.yml` so the native `package` job now runs `bash scripts/verify_native_dmg.sh` instead of maintaining a duplicated inline verification block, and so changes to the new script trigger the native workflow.
- Updated `scripts/check_release_docs.sh`, `README.md`, `docs/PROJECT_INDEX.md`, and `docs/RELEASE_AND_VALIDATION.md` so release docs and workflow validation now require and describe the shared DMG verification entrypoint.

**Reason**
- The repository already had strong local DMG verification evidence, but the authoritative workflow still duplicated that logic inline. That made the release path more drift-prone than the rest of the new validation gates.

**Tested**
- `bash -n scripts/check_release_docs.sh scripts/verify_native_dmg.sh .github/workflows/build.yml scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`
- `bash scripts/check_release_docs.sh`
- `bash scripts/verify_native_dmg.sh --dmg dist/C-Paper-Native-6.0.5-standalone-20260618.dmg`
- `git diff --check`

**Risks / Notes**
- This pass tightens the package gate by making mounted-app strict codesign verification part of the shared script instead of an optional manual audit step.

### 2026-06-18 — Verify local release packaging path against current worktree

**Task**
- Run the native release packaging path locally after the recent workflow, source, download, and update hardening work to prove the current worktree still produces a valid installable DMG.

**Changed**
- Updated `docs/WORK_LOG.md` with current local packaging evidence for the native release path.

**Reason**
- Full tests and live source canaries were already green, but that still left one release-critical question open: whether the current dirty-but-coherent native worktree could actually package into a valid DMG and pass the same mount checks the workflow expects.

**Tested**
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`
- `hdiutil verify dist/C-Paper-Native-6.0.5-standalone-20260618.dmg`
- Mounted `dist/C-Paper-Native-6.0.5-standalone-20260618.dmg` and checked `CPaperNative.app`, `Applications` symlink, `.background/background.png`, and `codesign --verify --deep --strict` on the mounted app
- `git diff --check`

**Risks / Notes**
- Local release packaging succeeded on 2026-06-18 with artifact `dist/C-Paper-Native-6.0.5-standalone-20260618.dmg`.
- This validates the ad hoc local packaging path only; Developer ID signing and notarization still depend on external credentials and were not exercised in this pass.

### 2026-06-18 — Turn release-documentation consistency into a real validation gate

**Task**
- Continue release hardening by converting the manual release-documentation consistency checklist into an executable repository gate.

**Changed**
- Added `scripts/check_release_docs.sh` to statically verify release workflow gating, release-doc keywords, live canary command coverage, and that native doc changes trigger the active build workflow.
- Updated `.github/workflows/build.yml` so native validate runs now include the release-doc consistency script, and so `README.md`, `docs/PROJECT_INDEX.md`, `docs/RELEASE_AND_VALIDATION.md`, and the new script itself participate in native-owned path triggers.
- Updated `docs/RELEASE_AND_VALIDATION.md` and `docs/PROJECT_INDEX.md` so their validation summaries now describe the executable release-documentation consistency gate instead of only a manual checklist.

**Reason**
- Release/install/signing/source-reliability docs had a documented validation checklist, but the repository was not actually enforcing that checklist. That left a gap where workflow and release docs could drift without tripping CI.

**Tested**
- `bash -n scripts/check_release_docs.sh .github/workflows/build.yml scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`
- `bash scripts/check_release_docs.sh`
- `ruby - <<'RUBY' ... YAML.load_file('.github/workflows/build.yml') ... RUBY`
- `git diff --check`

**Risks / Notes**
- The new gate is intentionally static. It proves workflow/docs/live-canary alignment, but it does not replace DMG packaging or Apple-signing runtime verification.

### 2026-06-18 — Mark completed-but-broken download items directly in the table

**Task**
- Continue release hardening by making completed download items with integrity problems visible directly in the downloads table instead of only through the queue-level integrity notice.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` with a typed integrity-state model for missing, unreadable, empty, and inspect-only completed-file problems.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so integrity checks now persist a per-task state map alongside the existing queue-level integrity notice and clear that map when issues disappear.
- Updated `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` so completed items with integrity problems render an inline status badge and a short repair/inspection summary in the table.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for the new integrity-state variants and for mapping missing, empty, and directory-path cases onto the expected row-level states.

**Reason**
- Queue-level integrity notices already warned that some completed files were broken, but users still had to guess which specific rows were affected when inspecting a mixed queue.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testDownloadIntegrityStateUsesRepairableAndInspectOnlyVariants|testRefreshDownloadsShowsIntegrityNoticeWhenCompletedDownloadFileIsMissing|testRefreshDownloadsShowsIntegrityNoticeWhenCompletedDownloadFileBecomesEmpty|testRefreshDownloadsDoesNotOfferRepairRetryWhenCompletedDownloadPathBecomesDirectory|testRetryDownloadsNeedingRepairRestartsQueueForMissingCompletedFile|testRefreshDownloadsClearsIntegrityNoticeAfterCompletedFileReturns|testRefreshDownloadsClearsIntegrityNoticeAfterCompletedFileBecomesUsableAgain)'`

**Risks / Notes**
- The new row-level states are derived from the latest integrity scan and are intentionally runtime-only; they are not persisted into the saved download history.

### 2026-06-18 — Mark restored download tasks directly in the downloads table

**Task**
- Continue release hardening by making the downloads table itself show which failed items were restored from an interrupted previous session.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` so failed interrupted download items now expose a typed workflow tag instead of leaving restored-session context only in queue-level notices.
- Updated `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` so restored interrupted items render an inline `上次会话` badge in the status column plus a short explanatory line in the info column.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for interrupted items receiving the restored-session tag and ordinary failures not receiving it.

**Reason**
- Queue-level recovery summaries were already visible, but users still had to infer which specific row came from a restored interrupted session. That made queue inspection less precise once multiple failure types coexisted.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testInterruptedFailedDownloadItemCarriesRecoveredSessionWorkflowTag|testOrdinaryFailedDownloadItemDoesNotCarryRecoveredSessionWorkflowTag|testDownloadTaskMessageUsesTypedFailureSummaryBeforeRawError|testDownloadRecoverySummaryExplainsInterruptedQueueWithoutStartupNoticeState|testRefreshDownloadsRecordsRecoveredInterruptedSessionDetails)'`

**Risks / Notes**
- This pass marks only interrupted restored failures. It does not yet add per-row markers for completed-file integrity repair states.

### 2026-06-18 — Validate native release-hardening changes against full suite and live sources

**Task**
- Run a stage-level validation pass after the recent search, preview, download, and update hardening work to confirm there is no local regression and that live source behavior still matches release expectations.

**Changed**
- Updated `docs/WORK_LOG.md` with the current validation evidence for the native release-hardening batch.

**Reason**
- The recent work touched four core workflows. A broader validation pass was needed so release-hardening evidence would not rely only on narrow targeted tests.

**Tested**
- `git diff --check`
- `swift test --jobs 1`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`

**Risks / Notes**
- `swift test --jobs 1` passed with `233` tests run, `7` live-source tests skipped, and `0` failures.
- The opt-in live canary then ran separately with `7` executed tests and `0` failures, confirming current upstream source behavior still satisfies the documented release-time expectations.

### 2026-06-18 — Distinguish restored update artifacts from current-session downloads

**Task**
- Continue release hardening by making the update workflow keep persistent context about whether the current DMG was restored from a previous session or downloaded in the current session.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/UpdateModels.swift` so downloaded update state now records artifact origin and exposes origin-aware status/summary text instead of treating restored artifacts and fresh downloads as the same state.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so restored update artifacts are marked explicitly, and later open-failure/missing/invalid transitions preserve that origin instead of silently collapsing into a generic downloaded state.
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift` so the update section now shows a persistent artifact-summary row with badges for restored-local artifacts and manual-open states.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for restored-artifact summaries, startup/manual restore origin, and ensuring successful current-session downloads are not mislabeled as restored artifacts.

**Reason**
- The update workflow already restored previously downloaded DMGs across restart, but after the startup prompt or notice disappeared, settings state could no longer explain whether the current artifact came from an older local download or from the current session.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testRestoredDownloadedUpdateStateCarriesPersistentRecoverySummary|testStartupUpdateCheckRestoresPreviouslyDownloadedArtifactForLatestRelease|testManualUpdateCheckRestoresPreviouslyDownloadedArtifactWithoutStartupPrompt|testDownloadAvailableUpdateAutomaticallyOpensDownloadedDMG|testDownloadAvailableUpdateOpenFailureKeepsDownloadedURLAndShowsGuidance)'`

**Risks / Notes**
- This pass keeps the distinction at the artifact/state level only. It does not yet add a top-level global banner outside the settings/update surfaces.

### 2026-06-18 — Keep download recovery context visible after startup restore

**Task**
- Continue release hardening by keeping interrupted-download recovery context visible in the downloads page even after the one-shot startup recovery notice is gone.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so the model now tracks cleaned partial-file count from session recovery and exposes a computed queue-level recovery summary based on current interrupted failed items.
- Updated `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` so the downloads page now shows an inline recovery summary row with restored-task and cleaned-partial badges whenever the queue still contains interrupted tasks from a previous session.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for queue-level recovery summaries both with and without fresh startup notice state, plus clearing that summary when retrying the restored queue.

**Reason**
- The existing startup recovery notice was useful but ephemeral. Once the queue changed, users could still see interrupted failed items but no longer had a short explanation that those failures came from a restored previous session.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testDownloadRecoverySummaryExplainsInterruptedQueueWithoutStartupNoticeState|testRefreshDownloadsRecordsRecoveredInterruptedSessionDetails|testRetryRecoverableDownloadsClearsRecoveryNoticeWhenQueueRestarts)'`

**Risks / Notes**
- The inline summary is queue-level only. It does not yet add a per-row “recovered from previous session” marker in the download table.

### 2026-06-18 — Keep batch preview source provenance visible after notice dismissal

**Task**
- Continue release hardening by making batch preview results retain source provenance and automatic-fallback context even after the source notice is dismissed.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` and `macos/Sources/CPaperNativeApp/Models/PaperModels.swift` so batch preview payloads now carry aggregate source IDs, successful query count, and automatic fallback count in addition to warnings.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so successful batch previews persist an aggregate source summary in model state and failed previews clear any stale previous provenance.
- Updated `macos/Sources/CPaperNativeApp/Views/BatchPreviewPanel.swift` so the preview list now shows an inline source-summary row with per-source badges and an explicit automatic-fallback count badge.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for persisted batch-preview provenance and stale-state clearing on batch preview failure.

**Reason**
- Search results already kept source provenance visible after dismissing source notices, but batch preview still lost that context immediately. That made mixed-source or fallback-backed preview results harder to trust and troubleshoot.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testPreviewBatchKeepsPartialResultsAndWarningsWhenSomeQueriesFail|testPreviewBatchStoresAggregateSourceSummaryAndFallbackState|testHandleBatchPreviewFailureClearsPreviousSourceSummary|testPreviewBatchUsesRetryableFailureWhenAllBatchQueriesFail)'`

**Risks / Notes**
- The new summary is aggregate-only. It does not yet expose a per-year/per-season source map inside the preview list.

### 2026-06-18 — Keep source fallback provenance visible in the search results panel

**Task**
- Continue release hardening by keeping source provenance visible after a successful search, even if the user dismisses the source notice.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/PaperModels.swift` and `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` so search payloads now carry both the winning source ID and whether automatic fallback was used.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so successful searches persist a result-source summary in model state and failed searches clear any stale previous source provenance.
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift` so the results panel now shows an inline source summary row, including an explicit `自动回退` badge when the result came from a fallback provider.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for payload fallback state, persisted search-result source summaries, and stale-state clearing on search failure.

**Reason**
- The previous pass made automatic fallback clearer while the source notice was visible, but once that notice was dismissed the search results area no longer told users where the current files came from or whether automatic fallback had happened.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testSearchWarningsPreferFallbackSummaryBeforeDetailedAttemptDiagnostics|testSearchStoresResultSourceSummaryAndFallbackState|testSearchFailureClearsPreviousResultSourceSummary|testApplySourceWarningsUsesAutomaticFallbackNoticeLevelForFallbackSummary)'`

**Risks / Notes**
- This pass adds provenance UI for the search workflow only. Batch preview still does not show a single source badge because one batch result can aggregate multiple per-year/per-season queries.

### 2026-06-18 — Give successful automatic source fallback its own notice state

**Task**
- Continue release hardening by making ready-state source notices visually distinguish “search failed” from “search succeeded after automatic fallback”.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` so source notices now distinguish successful automatic fallback from ordinary warning and failure states.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so fallback-summary warnings map to the new automatic-fallback notice level instead of the generic warning bucket.
- Updated `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift`, `macos/Sources/CPaperNativeApp/Views/SearchView.swift`, and `macos/Sources/CPaperNativeApp/Views/BatchPreviewPanel.swift` so automatic-fallback notices render with a dedicated title and accent-colored recovery-style card instead of the ordinary orange warning styling.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage proving fallback-summary warnings now select the new notice state while preserving the existing warning behavior for non-fallback cases.

**Reason**
- The previous pass improved the warning text itself, but the card still looked identical to a partial failure notice. That left users parsing the body copy to understand whether the search had succeeded or not.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testSearchWarningsPreferFallbackSummaryBeforeDetailedAttemptDiagnostics|testApplySourceWarningsUsesAutomaticFallbackNoticeLevelForFallbackSummary|testApplySourceWarningsShowsVisibleMessageAndDiagnostic|testPreviewBatchKeepsPartialResultsAndWarningsWhenSomeQueriesFail)'`

**Risks / Notes**
- This pass changes presentation/state classification only. It does not yet add a dedicated inline badge or source-attempt breakdown row in the search results area.

### 2026-06-18 — Summarize successful automatic source fallback in user-facing warnings

**Task**
- Continue release hardening by making successful automatic source fallback easier to understand in the ready-state UI instead of only exposing raw per-source failure strings.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` so source warnings now prepend a short user-facing fallback summary when automatic mode succeeds after one or more failed or timed-out providers.
- Kept detailed provider diagnostics intact after the summary, so the source notice still preserves exact per-provider reasons and timings in the diagnostic payload.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with end-to-end service coverage proving a successful fallback now surfaces a readable summary first, followed by the detailed timed failure line.

**Reason**
- After adding per-provider timing and automatic timeout boundaries, the ready-state source notice could still show a raw first warning like `FrankCIE: 搜索超时...` even though the search had already succeeded through a later provider. That was accurate but not the shortest user-facing explanation of what happened.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/testSearchWarningsPreferFallbackSummaryBeforeDetailedAttemptDiagnostics'`
- `swift test --jobs 1 --filter SourceRegistryTests`

**Risks / Notes**
- This pass only improves the warning text order and summary for successful automatic fallback. It does not yet add a distinct source-notice presentation style for timeout-vs-failure cases.

### 2026-06-18 — Bound automatic source fallback latency per provider

**Task**
- Continue release hardening by preventing one slow source provider from stalling the entire automatic search or subject-loading fallback chain for too long.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Sources/SourceRegistry.swift` so automatic source search and automatic subject loading now apply a per-provider total timeout budget before recording a failed attempt and moving on to the next source.
- Kept manual source mode unchanged, so an explicitly selected provider still gets its full direct result without the automatic fallback timeout boundary.
- Updated `macos/Sources/CPaperNativeApp/Backend/Sources/PaperSource.swift`, `macos/Sources/CPaperNativeApp/Models/CPaperModels.swift`, and `macos/Sources/CPaperNativeApp/Models/PaperModels.swift` with the minimal `Sendable` conformances needed to race automatic source attempts against timeout tasks safely.
- Expanded `macos/Tests/CPaperNativeTests/SourceRegistryTests.swift` with coverage for timed-out automatic search fallback, timed-out automatic subject fallback, and the guarantee that manual mode does not inherit the automatic timeout boundary.

**Reason**
- Live source validation showed that a provider can be functionally correct but still take tens of seconds. Without a registry-level timeout, automatic fallback had no cap on how long it could wait for one slow provider before trying the next one.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter SourceRegistryTests`

**Risks / Notes**
- The new timeout currently applies only to automatic source chaining, not manual source mode. If a user explicitly selects a slow provider, they still wait for that provider's own behavior instead of being cut off early.

### 2026-06-18 — Record source-attempt durations in diagnostics

**Task**
- Continue release hardening by improving source-workflow observability after live source validation showed large real-world latency differences between providers.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Sources/PaperSource.swift` so `SourceAttempt` can carry measured attempt duration and expose a diagnostic-ready message variant with elapsed milliseconds.
- Updated `macos/Sources/CPaperNativeApp/Backend/Sources/SourceRegistry.swift` so automatic/manual subject fetches and searches record per-source elapsed time for both successful and failed attempts.
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` and `macos/Sources/CPaperNativeApp/Backend/Core/BackendError.swift` so fallback warnings and no-result summaries now include source-attempt timing instead of only status text.
- Expanded `macos/Tests/CPaperNativeTests/SourceRegistryTests.swift` with coverage for timed attempts, timed no-result diagnostics, and localized diagnostic formatting.

**Reason**
- `RUN_LIVE_SOURCE_TESTS=1` confirmed the real source stack still works, but it also showed that different providers can vary widely in latency. Without timing in `SourceAttempt`, the app's source warnings and no-result diagnostics could tell users which provider failed, but not which one was slow enough to explain a poor search experience.

**Tested**
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
- `git diff --check`
- `swift test --jobs 1 --filter SourceRegistryTests`

**Risks / Notes**
- Timing is advisory observability data only; it does not yet change timeout policy, fallback order, or UI copy beyond diagnostic/warning text.

### 2026-06-18 — Auto-retry preview after successful repair downloads

**Task**
- Continue release hardening by removing the extra manual step after repairing a broken local preview file.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` with a small pending-preview-repair tracker so preview-triggered overwrite downloads can remember which selected file should resume preview loading when the queue finishes.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so `refreshDownloads()` now converts a finished successful preview-repair download into a model-level `retryPreview()` trigger instead of leaving the preview panel stuck in the previous failure state.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage proving a broken preview file not only forces overwrite despite duplicate skipping, but also queues and executes an automatic preview retry once the repaired file lands.

**Reason**
- The previous pass made “重新下载文件” real for corrupt downloaded previews, but the workflow still stopped one step short: after the repair completed, users still had to click “重试预览” manually. That left a needless gap in an otherwise deterministic recovery path.

**Tested**
- `swift test --jobs 1 --filter 'ModelTests/(testRedownloadSelectedPreviewFileForcesOverwriteEvenWhenDuplicateModeWouldSkip|testRedownloadSelectedPreviewFileQueuesAutomaticPreviewRetryAfterSuccessfulRepair)'`

**Risks / Notes**
- The automatic preview retry only fires when the same selected file finishes a successful repair download. If the user changes selection mid-download, the pending repair marker is cleared and no auto-retry runs.

### 2026-06-18 — Let unreadable downloaded previews force a real repair download

**Task**
- Continue release hardening by fixing the preview workflow so “请重新下载” is a real recovery path even when the global duplicate-file policy would normally skip that file.

**Changed**
- Added `PreviewFailureState` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` so preview failures now explicitly carry both the diagnostic and whether a direct redownload repair path should be shown.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` so unreadable user-downloaded preview files are marked as redownloadable failures, while missing cache files and managed-cache corruption remain retry-preview failures only.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so single-file downloads can take a narrow duplicate-mode override, and added a preview-specific repair entry point that forces overwrite only for the selected broken preview file.
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` so preview failures that come from unreadable downloaded files expose an inline “重新下载文件” action.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for the new preview failure state and for redownloading a corrupted local file even when the saved duplicate policy is `.skip`.

**Reason**
- The preview workflow already detected unreadable local downloaded PDFs and told the user to redownload them, but the actual single-file download path still respected duplicate skipping. In the common “file exists but is corrupt” case, the suggested recovery action could silently do nothing.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testPreviewLoadStateCarriesLoadedURLAndFailureDiagnostic|testRevealPreviewFileWhenCachedFileIsMissingUsesPreviewFailureState|testPreviewLoadFailureRemovesUnreadableManagedCacheFileAndUsesRetryableFailure|testPreviewLoadFailureKeepsUnreadableDownloadedFileAndUsesDownloadAwareMessage|testRedownloadSelectedPreviewFileForcesOverwriteEvenWhenDuplicateModeWouldSkip)'`

**Risks / Notes**
- The forced overwrite path is intentionally limited to preview-triggered repair of the currently selected broken file. Normal search/batch/single-file downloads still respect the user's configured duplicate policy.

### 2026-06-18 — Restore downloaded update artifacts across app restarts

**Task**
- Continue release hardening by giving the update workflow restart-safe recovery semantics when the latest DMG was already downloaded in a previous session.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so `checkForUpdates()` now checks whether the latest release's expected DMG already exists locally and is usable, then restores `updateStatus` into a downloaded/manual-open state instead of forgetting the artifact after restart.
- Updated `macos/Sources/CPaperNativeApp/Views/RootView.swift` so the startup update prompt switches from “下载更新” to “打开已下载更新” when that restored artifact is already present locally, with matching prompt copy.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for startup/manual restoration of a valid downloaded DMG and for rejecting empty local artifacts instead of restoring them.

**Reason**
- Before this change, the update pipeline had no restart memory: users could already have the newest DMG on disk, relaunch the app, and still be told to download again because the workflow only trusted in-memory state.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testStartupUpdateCheckPromptsWhenNewVersionExistsWithoutDownloading|testStartupUpdateCheckRestoresPreviouslyDownloadedArtifactForLatestRelease|testManualUpdateCheckRestoresPreviouslyDownloadedArtifactWithoutStartupPrompt|testUpdateCheckDoesNotRestoreEmptyDownloadedArtifact|testDownloadAvailableUpdateClearsPromptAndStoresDownloadedURL|testDownloadAvailableUpdateOpenFailureKeepsDownloadedURLAndShowsGuidance|testPerformUpdateNoticeActionClearsOpenFailureNoticeAfterManualSuccess)'`

**Risks / Notes**
- This pass only restores the latest release's expected DMG when the file is still locally usable. It does not add a general persisted update-history store for older artifacts or invalid local files.

### 2026-06-18 — Let completed-but-broken downloads recover from the downloads page

**Task**
- Continue release hardening by shortening the recovery path for completed download records whose files later disappeared or became unusable.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so completed-download integrity checks now distinguish retry-safe cases from inspect-only cases, and added a workflow action that restarts downloads for the safe subset directly from the downloads page.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift` and `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` with a targeted retry path for selected completed download tasks, reusing the existing queue/session machinery instead of forcing users back through search.
- Updated `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift`, `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift`, and `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` so integrity notices can expose a direct “重新下载受影响文件” action when safe, and so both recovery/integrity cards copy the exact diagnostic bound to the notice instead of whichever same-context diagnostic happened to be latest.
- Expanded `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift` and `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for retrying completed repaired files, preserving the no-auto-retry boundary for directory-path corruption, and the end-to-end model action that requeues a missing completed file.

**Reason**
- The app could already detect when a “completed” download no longer mapped to a usable local file, but the downloads page still stopped at warning text. That left users with a typed failure state and no short workflow-local recovery path for the common safe cases.

**Tested**
- `swift test --jobs 1 --filter 'DownloadManagerTests/testDownloadManagerCanRetryCompletedItemsNeedingRepair|ModelTests/(testRefreshDownloadsShowsIntegrityNoticeWhenCompletedDownloadFileIsMissing|testRefreshDownloadsShowsIntegrityNoticeWhenCompletedDownloadFileBecomesEmpty|testRefreshDownloadsDoesNotOfferRepairRetryWhenCompletedDownloadPathBecomesDirectory|testRetryDownloadsNeedingRepairRestartsQueueForMissingCompletedFile)'`

**Risks / Notes**
- The new one-click repair action intentionally excludes integrity failures where the saved path has become a directory or another non-regular path shape, because auto-replacing those could delete unexpected user content. Those cases still surface diagnostics and require manual inspection.

### 2026-06-18 — Surface fallback save-directory persistence failures inside the download workflow

**Task**
- Continue release hardening by making download flows visibly recoverable when the app can choose a replacement save directory but then fails to persist that new path.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so save-directory resolution now returns a typed result, and fallback-directory persistence failures can be routed back into `DownloadNotice` with the correct retry action instead of disappearing into a settings-only notice.
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift` and `macos/Sources/CPaperNativeApp/Views/BatchPreviewPanel.swift` so download notices copy the diagnostic embedded in the notice itself, rather than assuming every download notice always uses the `.download` diagnostic context.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for visible retryable download notices when fallback save-directory persistence fails, while still preserving the stricter “do not continue downloading” rule.

**Reason**
- After tightening fallback directory persistence, the remaining UX gap was that users initiating downloads from search or batch could hit a settings-save failure and see no workflow-local recovery affordance, because `settingsNotice` was only rendered in the settings sheet.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testResolvedSaveDirectoryKeepsMissingCreatableConfiguredDirectory|testResolvedSaveDirectoryPersistsChosenDirectoryBeforeReturningIt|testResolvedSaveDirectoryReturnsNilWhenChosenDirectoryCannotBeSaved|testStartSingleFileDownloadDoesNotProceedWhenChosenDirectoryCannotBeSaved|testStartSearchDownloadShowsRetryableDownloadNoticeWhenChosenDirectoryCannotBeSaved)'`
- `swift test --jobs 1`

**Risks / Notes**
- Download notices can now legitimately carry a diagnostic whose original context is `.settings`, so future UI code should rely on `downloadNotice.diagnostic` instead of assuming every download recovery path writes into `.download`.

### 2026-06-18 — Do not proceed with fallback directory downloads until the new path is saved

**Task**
- Continue release hardening by fixing the fallback save-directory flow so choosing a new directory after the configured path becomes unusable does not silently mutate in-memory settings or continue downloading when settings persistence fails.

**Changed**
- Added a testable `directoryChooser` injection point to `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` while preserving the live `NSOpenPanel` behavior by default.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so `resolvedSaveDirectory()` now saves the newly chosen directory through a draft settings commit first and returns `nil` when that save fails, instead of mutating `settings` up front.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for successful fallback-directory persistence, failed fallback-directory persistence, and single-file downloads correctly refusing to proceed when the chosen directory cannot be saved.

**Reason**
- Before this change, the fallback chooser path could leave the in-memory save directory pointing at a new location even if persistence failed, and downloads could proceed from that half-committed state. That weakened both observability and state-machine reliability.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testResolvedSaveDirectoryPersistsChosenDirectoryBeforeReturningIt|testResolvedSaveDirectoryReturnsNilWhenChosenDirectoryCannotBeSaved|testStartSingleFileDownloadDoesNotProceedWhenChosenDirectoryCannotBeSaved)'`
- `swift test --jobs 1`

**Risks / Notes**
- This pass intentionally makes fallback directory selection depend on settings persistence succeeding first. That is stricter than before, but it prevents downloads from starting under a save path the app could not reliably record.

### 2026-06-18 — Unify save-directory semantics across all download entry points

**Task**
- Continue release hardening by removing the split behavior where single-file downloads used the configured save directory but search and batch downloads always forced a new directory picker.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so search, batch, and single-file download starts now all flow through the same helper and the same `resolvedSaveDirectory()` contract.
- Search and batch downloads now honor the configured save directory first, fall back to directory selection only when the configured path is unusable, and keep the existing route-to-downloads behavior after successful queue startup.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for search downloads using an existing configured directory and batch downloads using a missing-but-creatable configured directory.

**Reason**
- The old split contract made the download workflow harder to reason about: the app displayed a saved download location in settings and the downloads page, but two of the three actual download entry points ignored it and asked again every time.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testStartSearchDownloadUsesConfiguredSaveDirectory|testStartBatchDownloadUsesConfiguredCreatableSaveDirectory|testPerformDownloadNoticeActionRetriesSingleFileDownloadStart)'`
- `swift test --jobs 1`

**Risks / Notes**
- If the configured directory is missing or invalid, search and batch downloads now inherit the same fallback behavior as single-file downloads. That improves consistency, but any future UX change to directory-selection policy should now be made in one place instead of three.

### 2026-06-18 — Move support-folder reveal failures out of the global alert path

**Task**
- Continue release hardening by stopping support-folder reveal failures from interrupting unrelated workflows with the app-wide error alert.

**Changed**
- Extended `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift` with a dedicated `supportDirectory` diagnostic context and added `SupportDirectoryNotice` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` so `revealSupportDirectory()` now records a typed support-directory notice instead of routing failure through `errorMessage`, and clears stale support-folder notices after a successful reveal.
- Added `SupportDirectoryNoticeCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift`, then rendered that notice from `macos/Sources/CPaperNativeApp/Views/RootView.swift` and `macos/Sources/CPaperNativeApp/Views/SettingsView.swift`.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for both the new failure notice path and notice clearing after a later successful reveal.

**Reason**
- “显示支持文件夹” is usually a follow-up action inside another workflow notice. Falling back to the global alert for that secondary failure broke workflow locality and reintroduced the same cross-flow interruption this release-hardening pass has been removing elsewhere.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testRevealSupportDirectoryUsesContextualNoticeWhenSupportPathCannotBecomeDirectory|testRevealSupportDirectoryClearsStaleNoticeAfterSuccessfulReveal)'`
- `swift test --jobs 1`

**Risks / Notes**
- The startup failure screen still keeps its own dedicated alert path because it does not run inside the ready-state workflow shell and therefore cannot reuse the normal in-app notice surfaces.

### 2026-06-18 — Accept creatable save directories instead of treating them as broken

**Task**
- Continue release hardening by fixing the save-directory workflow so a configured directory that does not exist yet, but can be created safely, is no longer treated as unusable.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` so save-directory validation now distinguishes between ready directories, missing-but-creatable directories, and truly invalid paths, with clearer diagnostic reasons for invalid cases.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so single-file downloads reuse that same validation and keep a configured creatable directory instead of immediately forcing a directory picker.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for creatable missing directories, reveal-time directory creation, and the revised invalid-path diagnostics.
- Updated `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` so the menu contract now treats creatable save directories as revealable while still disabling clearly invalid file paths.

**Reason**
- The previous workflow only trusted an already-existing folder. That wrongly downgraded the default `~/Downloads/C-Paper` style configuration into an error state until the folder happened to exist, even though the download pipeline can safely create it when needed.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests/(testUsableSaveDirectoryURLExpandsTildeForExistingDirectory|testUsableSaveDirectoryURLAcceptsMissingCreatableDirectory|testResolvedSaveDirectoryKeepsMissingCreatableConfiguredDirectory|testRevealSaveDirectoryCreatesMissingConfiguredDirectory|testRevealSaveDirectoryUsesContextualNoticeWhenPathIsAFile|testPerformSaveDirectoryNoticeActionOpensSettings)'`
- `swift test --jobs 1 --filter 'AppMenuCommandCenterTests/testReadyBindingTreatsCreatableSaveDirectoryAsRevealableButDisablesInvalidPath'`
- `swift test --jobs 1`

**Risks / Notes**
- This pass still uses filesystem-level readability and writability checks only; it does not attempt to predict all possible later sandbox or Finder-open failures beyond the local path preflight.

### 2026-06-18 — Add end-to-end model coverage for manual sources without subject lists

**Task**
- Strengthen the source workflow evidence by covering the real `loadSubjects()` path for manual sources that do not expose subject directories.

**Changed**
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with an async end-to-end model test that drives `await model.loadSubjects()` through a manual `PapaCambridge`-style unsupported-subject-list failure and verifies the resulting no-retry guidance plus manual-code recovery state.

**Reason**
- The earlier regression test covered the handler directly, but release-grade confidence is stronger when the full async model workflow is also locked down.

**Tested**
- `swift test --jobs 1 --filter ModelTests/testLoadSubjectsUsesManualCodeGuidanceWhenSelectedSourceLacksSubjectList`

**Risks / Notes**
- This is test-only coverage; it does not change production workflow semantics beyond the earlier user-facing fix.

### 2026-06-18 — Make all source notices dismissible in search and batch flows

**Task**
- Continue release hardening by fixing a UI-level workflow gap where non-retry source notices could remain stuck on screen without a dismiss affordance.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift` and `macos/Sources/CPaperNativeApp/Views/BatchPreviewPanel.swift` so `SourceNoticeCard` always shows the dismiss button, including warning-only and guidance-only notices whose action is `nil`.

**Reason**
- Some source notices are intentionally non-retryable, such as manual-source guidance or partial-source warnings. Hiding the dismiss action for those notices turned a correct workflow message into a sticky UI obstacle.

**Tested**
- `git diff --check`
- `swift test --jobs 1`

**Risks / Notes**
- This is a presentation-layer fix only. It does not change source-state semantics or diagnostic contents.

### 2026-06-18 — Fix manual subject-loading recovery semantics for sources without subject lists

**Task**
- Continue release hardening by making manual source mode surface the correct recovery guidance when the selected source does not provide a subject directory.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Setup.swift` so subject-loading failures from manual sources that explicitly do not support subject lists now produce a contextual source notice with manual-code guidance instead of a misleading retry action.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for a manual `PapaCambridge` subject-list failure that must preserve a selected-source-specific reason and remove the incorrect retry affordance.
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsFormSections.swift` and `docs/RELEASE_AND_VALIDATION.md` so both the in-app settings hint and release docs now warn that some manual sources require direct subject-code entry.

**Reason**
- “重新加载科目” is the wrong recovery path when the selected provider never supported subject lists in the first place. That weakens the manual source workflow and points the user toward an action that cannot succeed.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`

**Risks / Notes**
- This change only special-cases the explicit “暂不支持科目列表” contract. Other subject-loading failures still remain retryable because they may reflect transient upstream or network conditions.

### 2026-06-18 — Verify manual source mode preserves clear selected-source failures

**Task**
- Continue release hardening by proving that manual source mode not only avoids fallback, but also preserves a clear selected-source failure reason when the chosen provider degrades.

**Changed**
- Expanded `macos/Tests/CPaperNativeTests/SourceRegistryTests.swift` with a contract test proving manual `PapaCambridge` search preserves the selected provider's unavailable reason and never falls through to another source.
- Expanded `macos/Tests/CPaperNativeTests/LiveSourceTests.swift` with a live canary for manual `PapaCambridge` mode that accepts either a PapaCambridge-owned downloadable PDF or a clear `sourceUnavailable` message that still names the selected source.
- Updated `docs/RELEASE_AND_VALIDATION.md` so the opt-in live canary expectations now explicitly include clear selected-source failure semantics for manual mode.

**Reason**
- “不切源” is only half the contract. If manual mode fails, the user still needs a selected-source-specific reason instead of a generic or silently altered failure.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter SourceRegistryTests`
- `swift test --jobs 1 --filter LiveSourceTests`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests/testLiveManualPapaCambridgeKeepsClearUnavailableReasonOrReturnsOwnPDF`

**Risks / Notes**
- The real-network canary remains opt-in because PapaCambridge's upstream state is intentionally unstable. The fixture contract now covers the no-fallback plus clear-failure rule even when live verification is skipped.

### 2026-06-18 — Strengthen manual source mode verification for subjects and live search

**Task**
- Continue release hardening by proving that manual source mode stays on the selected source for both subject loading semantics and real search execution.

**Changed**
- Expanded `macos/Tests/CPaperNativeTests/SourceRegistryTests.swift` with fixture coverage for manual subject loading so an empty selected-source subject list now explicitly proves there is no fallback to another provider.
- Expanded `macos/Tests/CPaperNativeTests/LiveSourceTests.swift` with a live canary that runs the real `SourceRegistry` in manual `EasyPaper` mode, verifies attempts only contain the selected source, and confirms the returned question paper is still directly downloadable as a PDF.
- Updated `docs/RELEASE_AND_VALIDATION.md` so the optional live source canary expectations now explicitly include manual source mode staying on the selected provider.

**Reason**
- Automatic fallback is only half of the source contract. Manual mode is a separate user-visible promise: use exactly the chosen provider, and fail there instead of silently switching sources.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter SourceRegistryTests`
- `swift test --jobs 1 --filter LiveSourceTests`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests/testLiveManualEasyPaperSearchStaysOnSelectedSource`

**Risks / Notes**
- The real-network canary remains opt-in because it depends on upstream site stability. The fixture coverage now locks the no-fallback subject-loading rule even when live sites are unavailable.

### 2026-06-18 — Add a live canary for the real automatic source fallback path

**Task**
- Continue release hardening by strengthening live source verification around the real automatic search fallback path instead of only individual source checks.

**Changed**
- Expanded `macos/Tests/CPaperNativeTests/LiveSourceTests.swift` with a live canary that forces FrankCIE unavailable, runs the real `SourceRegistry` automatic search chain, verifies fallback attempts are recorded, and confirms the returned question paper is still directly downloadable as a PDF.
- Updated `docs/RELEASE_AND_VALIDATION.md` so release validation now documents the opt-in `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests` canary and the concrete expectations it is meant to prove.

**Reason**
- The project already had live checks for individual sources, but the most production-relevant path is the automatic fallback chain itself. Without a dedicated canary, local fixture tests could stay green while the real fallback workflow had silently regressed.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter LiveSourceTests`

**Risks / Notes**
- This canary remains opt-in because it depends on unstable third-party sites. The default CI/local test path still skips it unless `RUN_LIVE_SOURCE_TESTS=1` is set.

### 2026-06-18 — Detect unusable completed downloads instead of only missing files

**Task**
- Continue release hardening by extending the downloads integrity workflow so completed files that still exist but are no longer usable do not remain in a false-success state.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so completed-download integrity checks now detect both missing files and invalid local files, including directory collisions, unreadable files, non-regular files, and zero-byte files.
- Extended `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` so `DownloadIntegrityNotice` can distinguish missing-file and invalid-file counts and render a more accurate recovery message.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for empty completed files becoming contextual integrity failures and for clearing the integrity notice after a damaged file becomes usable again.

**Reason**
- “文件路径还在” does not guarantee “下载结果可用”. Leaving zero-byte or otherwise invalid completed files in a pure success state weakens the download workflow and hides the right recovery action.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests/testRefreshDownloads`

**Risks / Notes**
- This pass intentionally stops at filesystem-level integrity checks. It does not try to parse downloaded PDFs or prove file contents match the original remote asset.

### 2026-06-18 — Make all-failed batch preview runs surface a real retryable failure

**Task**
- Continue release hardening by fixing the batch preview workflow so a run where every year/season query fails no longer looks like a warning-only empty success.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` so batch preview now tracks whether any per-query source lookup actually succeeded, promotes an all-failed run into a source-unavailable error, and keeps partial-failure runs as successful payloads with warnings.
- Added a small `sourceRegistryBuilder` injection point in `NativeBackendService` so workflow tests can validate batch preview semantics without hitting live network sources.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with async workflow coverage for both all-failed batch preview runs that must become `.retryBatchPreview` failures and partial-success runs that must still return results plus warning-only source notices.

**Reason**
- “空结果 + warning” is the wrong contract when the backend never succeeded on any batch subquery. That weakens retry semantics, hides real source failure, and diverges from the single-search failure model.

**Tested**
- `swift test --jobs 1 --filter ModelTests/testPreviewBatch`

**Risks / Notes**
- This change intentionally treats “至少一个子查询成功” as the success boundary. A fully successful lookup that later gets filtered down to zero visible paper groups still remains a successful empty result, because the source workflow itself did succeed.

### 2026-06-18 — Type unusable downloaded updates as a retryable install state

**Task**
- Continue release hardening by distinguishing “downloaded update file is gone” from “downloaded update file still exists but is no longer a usable DMG”.

**Changed**
- Extended `UpdateInstallState` in `macos/Sources/CPaperNativeApp/Models/UpdateModels.swift` with `.invalidFile`, and updated the downloaded-file access rules so unusable update files hide open/reveal actions just like missing files.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so update install actions now validate downloaded files before opening or revealing them, treating directories, unreadable files, non-regular files, and zero-byte files as a contextual retry-download state instead of falling through to generic open failure.
- Simplified the post-download auto-open path so the initial install attempt now reuses the same typed validation and recovery logic as later manual open/reveal actions.
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift` so unusable downloaded updates render with warning styling alongside missing-file states.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for an empty downloaded DMG that must never be opened and for a downloaded update path that is later replaced by a directory.

**Reason**
- “路径还在” does not mean “安装物可用”. If a downloaded update is replaced, truncated, or otherwise invalid, treating it as a normal open failure weakens the update state machine and suggests the wrong recovery action.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- This still does not prove that a non-empty regular file is a valid DMG image; it only closes the obvious local-file boundary failures. Full installer validity would require a deeper platform-specific verification step.

### 2026-06-18 — Surface missing completed downloads inside the downloads workflow

**Task**
- Continue release hardening by making the downloads page report when previously completed files have disappeared from disk.

**Changed**
- Added a dedicated `downloadIntegrity` diagnostic context plus `DownloadIntegrityNotice` in `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift` and `WorkflowStateModels.swift` so missing completed files no longer have to share the interrupted-download diagnostic channel.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+PaperWorkflow.swift` so `refreshDownloads()` now checks completed download items for missing save paths after the queue is idle, records a contextual integrity diagnostic, avoids rewriting the same diagnostic repeatedly, and clears the notice once the files are back.
- Added `DownloadIntegrityNoticeCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it from `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift`, with actions to copy the integrity diagnostic, reveal the configured download folder, and dismiss the notice.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for surfacing a missing completed file and for clearing the integrity notice after the file reappears.

**Reason**
- A completed queue item only proves the file existed when the download finished. If the file is deleted later, leaving the downloads page in a pure success state weakens observability and can mislead the user about what is still available locally.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- This pass intentionally does not mutate backend queue history or auto-retry missing completed files, because the current completed-item snapshot does not retain enough source information for a safe automatic requeue. Recovery remains an explicit user action.

### 2026-06-18 — Fail unreadable preview files inside the preview workflow

**Task**
- Continue release hardening by making preview loads fail explicitly when the local preview file exists but is no longer a readable PDF.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` so preview loads now validate that the resolved local file both exists and can be parsed as a PDF before moving to `PreviewLoadState.loaded`.
- Added unreadable-preview failure handling that distinguishes managed preview-cache corruption from an unreadable downloaded file, clears corrupt managed cache files when safe, and records a contextual preview diagnostic instead of leaving the failure implicit inside `PDFView`.
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` with a helper that deletes only files inside the managed preview cache, so preview recovery can clean stale cache artifacts without touching user-downloaded files.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for corrupt preview-cache cleanup, unreadable downloaded files that must not be deleted, and a valid-PDF version of the stale-preview completion test.

**Reason**
- “缓存文件存在” does not guarantee “预览可用”. Leaving corrupt or non-PDF files to fail only inside `PDFView` weakened the preview state machine and made retry semantics unreliable.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- The unreadable-downloaded-file path now reports a contextual failure, but it does not auto-repair the user’s downloaded file. Recovery there is intentionally manual: re-download or open the source URL in the browser.

### 2026-06-18 — Stop swallowing startup support-folder reveal failures

**Task**
- Continue release hardening by making the startup failure screen report support-folder reveal problems instead of silently swallowing them inside the view.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppBootCoordinator.swift` so `AppBootFailure` now exposes a testable support-folder reveal helper and a contextual fallback message for reveal failures.
- Updated `macos/Sources/CPaperNativeApp/Views/RootView.swift` so the startup failure screen no longer uses `try?` for support-folder creation and now shows a local alert if the support folder cannot be prepared for Finder.
- Expanded `macos/Tests/CPaperNativeTests/StartupBootCoordinatorTests.swift` with coverage for both successful startup support-folder reveal preparation and a blocked-path failure that must not reach Finder.

**Reason**
- Startup failure is already its own workflow surface. Leaving “显示支持文件夹” as a silent no-op undermined diagnostics exactly when the app had already failed to boot.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter StartupBootCoordinatorTests`
- `swift test --jobs 1`

**Risks / Notes**
- This closes the directory-creation silent failure path, but Finder reveal itself still relies on `NSWorkspace.activateFileViewerSelecting(...)`, which does not expose a structured failure result. If Finder-open failures become important, that needs a deeper abstraction instead of another view-local patch.

### 2026-06-18 — Stop swallowing support-directory reveal failures

**Task**
- Continue release hardening by making support-directory reveal failures report a real diagnostic instead of silently failing when the support path cannot be created as a directory.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` so `revealSupportDirectory()` now catches support-directory creation errors and routes them through the existing app-level diagnostic alert with path and reason details.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for a blocked support-directory path that collides with an existing file.

**Reason**
- Support diagnostics are part of the release/debugging story. If the support folder itself cannot be opened, silently swallowing that failure makes the app much harder to troubleshoot.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter StartupBootCoordinatorTests`
- `swift test --jobs 1`

**Risks / Notes**
- This still assumes `NSWorkspace.activateFileViewerSelecting` succeeds once the directory exists. A later pass could wrap Finder-opening behavior more deeply if local-environment open failures become a recurring issue.

### 2026-06-18 — Fail missing cached preview files inside the preview workflow

**Task**
- Continue workflow hardening by making “在访达中显示” for a loaded preview fail contextually when the cached preview file has disappeared.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` with `revealPreviewFile()`, which now checks the loaded preview file before opening Finder and converts missing-cache cases into a contextual preview diagnostic plus `PreviewLoadState.failed`.
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` so the preview toolbar uses the new model-driven reveal path instead of calling `NSWorkspace` directly.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for a loaded preview whose cached file has been removed before the reveal action runs.

**Reason**
- A missing cached preview file is a preview-workflow failure, not a generic Finder action problem. Leaving the toolbar action to fail silently weakened the preview recovery model.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- This only covers the explicit Finder reveal action. If the PDF view itself needs to detect externally deleted files while still visible, that would require a deeper runtime observer instead of this action-path hardening.

### 2026-06-18 — Type missing downloaded-update files as a retryable update state

**Task**
- Continue update workflow hardening by distinguishing “DMG failed to open” from “downloaded DMG is gone and must be downloaded again”.

**Changed**
- Extended `UpdateInstallState` in `macos/Sources/CPaperNativeApp/Models/UpdateModels.swift` with `.missingFile`, plus `UpdateStatus.canAccessDownloadedFile` so Settings can hide open/reveal actions once the file is known missing.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so `openDownloadedUpdate()` and `revealDownloadedUpdate()` now detect a missing DMG, record an update diagnostic, move the typed update state to `.missingFile`, and surface a retry-download notice instead of silently failing.
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift` so missing-file update states render as warning-colored status and stop showing “打开 DMG / 显示文件” buttons that can no longer succeed.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for missing-file detection from both open and reveal actions.

**Reason**
- A deleted DMG is not the same failure mode as an `NSWorkspace` open failure. Treating both as “try opening again” weakened the release/install state machine and hid the correct recovery action.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- The update workflow still treats missing downloaded files as a downloaded-state install problem rather than a separate failure phase. That keeps the change small, but a future pass could split install-access failures into a distinct typed state if more cases appear.

### 2026-06-18 — Make manual DMG open failures stay inside the update workflow

**Task**
- Continue the update workflow hardening by making failed manual “打开 DMG” actions produce contextual recovery state instead of silently failing.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so downloaded-update open failures now reuse one helper that records an update diagnostic, keeps the typed downloaded state, and sets `installState` to `.requiresManualOpen`.
- Reused the same open-failure path for both post-download auto-open failures and later manual open attempts from Settings, so all DMG open failures now surface the same contextual `UpdateNotice`.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for a manual open failure that happens after an otherwise successful download/open cycle.

**Reason**
- A downloaded update that cannot be opened is still an update-workflow problem. Leaving the manual open button with a silent no-op weakened recovery semantics and made it harder to diagnose release/install issues.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- The update workflow now converges auto-open and manual-open failures onto one notice message and one recovery action. If the project later needs to distinguish Finder/path problems from `NSWorkspace` open failures, that should likely become a more typed install state.

### 2026-06-18 — Move invalid save-directory reveal failures into the downloads workflow

**Task**
- Continue the workflow cleanup by keeping invalid save-directory reveal failures inside the downloads/settings workflow instead of falling back to the app-wide error alert.

**Changed**
- Added `SaveDirectoryNotice` and `SaveDirectoryNoticeAction` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift`, plus a dedicated `.saveDirectory` diagnostic context in `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` so `revealSaveDirectory()` now records a contextual diagnostic and notice with an “open settings” recovery action instead of writing `errorMessage`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Setup.swift` so a successful settings save clears stale save-directory notices once the path has been reconfigured.
- Added `SaveDirectoryNoticeCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it from `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` above the queue summary.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for missing/file-path notice routing, opening settings from the notice action, and clearing the notice after a successful settings save.

**Reason**
- “显示下载文件夹” is a local workflow action tied to download storage configuration. Routing that failure through the root alert made the downloads page inconsistent with the rest of the typed workflow cleanup.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- The menu command still disables “显示下载文件夹” when the configured directory is obviously unusable, so the new notice mainly covers in-view actions and any state that becomes invalid after the menu was enabled.

### 2026-06-18 — Move favorites add/remove failures into contextual notices

**Task**
- Continue the workflow cleanup by making favorites add/remove failures stay inside the favorites/search workflow instead of falling back to the app-wide error alert.

**Changed**
- Added `FavoriteNotice` and `FavoriteNoticeAction` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift`, plus a dedicated `.favorites` diagnostic context in `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+Setup.swift` so favorites add/remove failures now record contextual diagnostics, expose retry/dismiss actions, and stop writing `errorMessage`.
- Added `FavoriteNoticeCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it from `macos/Sources/CPaperNativeApp/Views/SidebarView.swift` next to the favorites controls.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for add/remove failure routing and for retrying a failed add-favorite action through the notice path.

**Reason**
- Favorites add/remove are local workflow actions tied to the search/sidebar experience. Routing their persistence failures through the root alert blurred the boundary between contextual workflow issues and true app-level problems.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- The favorites notice is rendered from the sidebar so it stays visible for both search-page and sidebar-triggered favorite actions. Other local-environment actions such as revealing an invalid save directory still remain intentionally global.

### 2026-06-18 — Keep settings save failures inside the settings workflow

**Task**
- Continue the workflow cleanup by making settings-save failures stay inside the settings sheet instead of closing the sheet and falling back to the app-wide error alert.

**Changed**
- Added `SettingsNotice` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` and introduced a dedicated `settings` diagnostic context in `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+Setup.swift` so `saveSettings` now returns success/failure, clears stale settings notices on success, and records a contextual settings notice on failure instead of writing `errorMessage`.
- Added `dismissSettingsNotice()` and rendered the new inline `SettingsNoticeCard` from `macos/Sources/CPaperNativeApp/Views/SettingsView.swift`, with the save button now dismissing the sheet only after a successful save.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for successful save return values and for a forced persistence failure that must keep the old settings intact while surfacing a settings notice.

**Reason**
- Saving settings was a high-risk workflow bug: if persistence failed, the settings sheet still closed, which falsely implied the new settings had been committed.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`

**Risks / Notes**
- Settings save failures are now contextual to the settings sheet. Other setup actions such as favorites add/remove still use the general error path and are good candidates for the next cleanup pass.

### 2026-06-18 — Move subject-load failures into contextual source notices

**Task**
- Continue the source workflow cleanup by making subject-list loading failures behave like contextual source notices instead of falling back to the app-wide error alert.

**Changed**
- Extended `SourceNoticeAction` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` with `retryLoadSubjects`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Setup.swift` so `loadSubjects()` clears stale source notices up front, records source diagnostics on failure, and publishes a typed retryable source notice instead of calling `handleBackendError`.
- Updated `performSourceNoticeAction()` in `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so source notices can now retry subject loading directly.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for subject-load failure routing, retry action typing, and fallback restoration of the saved manual subject code.

**Reason**
- Search failures and source warnings had already moved to contextual notices, but an inability to load the subject list still escaped into the root global alert even though it was the same source-provider workflow.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`

**Risks / Notes**
- Subject-load failures are now visible through the search/batch source notice channel. General alerts are becoming more concentrated on truly app-level or local-environment issues.

### 2026-06-18 — Move download-start failures into contextual notices

**Task**
- Continue the native workflow cleanup by making download-start failures from the search/batch surfaces behave like contextual download notices instead of falling back to the app-wide error alert.

**Changed**
- Added `DownloadNotice` and `DownloadNoticeAction` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` to model retryable download-start failures for search, batch, and single-file launches.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+PaperWorkflow.swift` so download-start failures now record a download diagnostic and publish a contextual retry notice instead of writing `errorMessage`.
- Added `dismissDownloadNotice()`, `performDownloadNoticeAction()`, and `handleDownloadStartFailure()` to keep the download-start failure path explicit and testable.
- Added `DownloadNoticeCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it from `SearchView.swift` and `BatchPreviewPanel.swift` only on the relevant source route.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for contextual download-start failure routing and for retrying a single-file download launch through the notice action path.

**Reason**
- Search and batch failures had already moved into contextual source notices, but clicking download could still send workflow-local problems back to the root alert. That left download-start semantics inconsistent with the rest of the typed workflow cleanup.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`

**Risks / Notes**
- Bulk search/batch download start still relies on the existing directory-picker flow, so the new retry notice re-enters the same UI path when a user retries. The remaining global alert is now more concentrated on truly app-level or local environment errors.

### 2026-06-18 — Move source search failures into contextual notices

**Task**
- Continue the native workflow cleanup by making search and batch source-provider failures behave like contextual workflow notices instead of falling back to the app-wide error alert.

**Changed**
- Replaced the warning-only source notice with typed source workflow state in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift`: `SourceNotice`, `SourceNoticeLevel`, and `SourceNoticeAction`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+PaperWorkflow.swift` so source warnings and source failures now share one contextual notice channel, and search/batch failures record diagnostics plus explicit retry actions without populating `errorMessage`.
- Added `dismissSourceNotice()` and `performSourceNoticeAction()` so source failures can be retried directly from the inline workflow notice.
- Updated `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift`, `SearchView.swift`, and `BatchPreviewPanel.swift` so the inline source card can render either a passive warning or a failure notice with retry/dismiss actions.
- Updated `macos/Tests/CPaperNativeTests/ModelTests.swift` to cover failure-routing, warning semantics, and explicit dismissal for the new source notice model.

**Reason**
- Source warnings were already contextual, but a real search/batch failure still escaped into the root global alert. That left the source workflow split across two unrelated UI channels and weakened retry/error semantics.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`

**Risks / Notes**
- Source failures are now contextual to the search/batch surfaces. The remaining global alert is still used for truly general or cross-workflow errors such as invalid local save-directory actions.

### 2026-06-18 — Type update failure and install workflow state

**Task**
- Continue the native update workflow cleanup by moving failure phase and post-download install semantics into the typed update state machine instead of leaving them implicit in notices and string messages.

**Changed**
- Added typed update workflow helpers in `macos/Sources/CPaperNativeApp/Models/UpdateModels.swift`: `UpdateDownloadState`, `UpdateFailureState`, `UpdateFailurePhase`, `DownloadedUpdateState`, and `UpdateInstallState`.
- Updated `UpdateStatus` so downloading, failed, and downloaded states now preserve release context, destination/file URLs, manual-open requirement, and recovery action hints.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so manual check failure becomes a typed `.failed(.check)` state, download failure becomes a typed `.failed(.download)` state that still keeps the retry target, and post-download auto-open failure becomes a typed downloaded state requiring manual open.
- Updated successful manual-open handling so resolving a manual-open-required update also clears that install requirement from the typed status.
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift` and targeted tests in `macos/Tests/CPaperNativeTests/ModelTests.swift` and `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift` to consume the new state shape.

**Reason**
- Update notices already carried explicit next-step actions, but `UpdateStatus` still collapsed materially different workflow states into `.failed(String)` and `.downloaded(URL)`, which left retry/install semantics partially hidden outside the main state machine.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests|AppMenuCommandCenterTests'`

**Risks / Notes**
- The update workflow is now more explicit, but `UpdateNotice` still mirrors part of the recovery action semantics for diagnostics/UI rendering. A later step could decide whether that duplication is still worth keeping once more workflow chains are aligned.

### 2026-06-18 — Give update notices explicit next-step actions

**Task**
- Continue the native update workflow cleanup by making update notices encode what the user should do next, not just what went wrong.

**Changed**
- Added `UpdateNoticeAction` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` and extended `UpdateNotice` to carry an explicit recovery action for retry-check, retry-download, or open-downloaded-DMG flows.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so each update notice now records the correct next-step action and exposes `performUpdateNoticeAction()` to execute it through the existing update workflow.
- Updated manual open success handling so resolving a post-download auto-open failure clears the update notice automatically.
- Updated `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift` so the update notice card renders a contextual primary action instead of only passive support actions.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for action typing on update notices and for executing retry/open actions through the notice path.

**Reason**
- Contextual notices improved observability, but without typed next-step actions they still left part of the recovery semantics implicit in button placement and human interpretation.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- The action executor intentionally reuses the existing update workflow entry points instead of introducing a parallel control path. Future work could push this further by typing the whole `UpdateStatus` failure/install state machine instead of only the notice layer.

### 2026-06-18 — Move update download issues out of the global error alert

**Task**
- Continue the release-quality cleanup by making update-check and update-download problems behave like contextual workflow notices instead of app-wide fatal alerts.

**Changed**
- Added `UpdateNotice` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` and stored it on `macos/Sources/CPaperNativeApp/State/AppModel.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so update-check failure, update-download failure, and post-download auto-open failure now record update diagnostics and surface a contextual notice instead of populating the global `errorMessage` alert.
- Kept `UpdateStatus` as the authoritative state machine while making successful manual DMG opening clear the update notice as the issue is resolved.
- Added `UpdateNoticeCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it in `macos/Sources/CPaperNativeApp/Views/SettingsInfoSections.swift` with actions to copy the update diagnostic, reveal the support folder, or dismiss the notice.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for manual update-check failure notice routing, update-download failure notice routing, auto-open failure notice routing, and clearing the notice after a later successful manual open.

**Reason**
- Update problems are important but not app-fatal, and routing them through the same global alert channel as general failures broke the workflow distinction that had already been cleaned up for source warnings and recovered downloads.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- Update notices are scoped to the update workflow only. The global alert remains for truly app-wide errors, while update-specific follow-up now lives next to the update controls in Settings.

### 2026-06-18 — Show recovered download-session notice inline in the download page

**Task**
- Continue the native download recovery work by surfacing recovered-session state directly in the downloads UI instead of only leaving it inside support diagnostics.

**Changed**
- Added `DownloadRecoveryNotice` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` and stored it on `macos/Sources/CPaperNativeApp/State/AppModel.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so recovered-session diagnostics now also populate a visible notice, and so the notice clears when the queue starts running again or the recovered failure state is resolved.
- Added `DownloadRecoveryCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it from `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` above the queue summary with actions to copy the download diagnostic or reveal the support folder.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for the visible recovered-session notice text and for clearing the notice once a retry restarts the queue.

**Reason**
- After adding recovery diagnostics, the download center still required the user to open diagnostics or infer from failure rows that the queue had been restored from an interrupted app run. The main workflow page should communicate that state explicitly.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'ModelTests|DownloadManagerTests'`
- `swift test --jobs 1`

**Risks / Notes**
- The recovered-session notice is intentionally scoped to the current recovered failure set. Once the queue restarts or the recovered failures disappear, the page falls back to the normal queue summary and diagnostic flow.

### 2026-06-18 — Surface interrupted-download recovery details in diagnostics

**Task**
- Continue the native download-session recovery work by making relaunch recovery observable instead of only silently mutating queue state.

**Changed**
- Added `DownloadSessionRecoverySummary` in `macos/Sources/CPaperNativeApp/Backend/Persistence/DownloadSessionStore.swift` and updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift` so restored-session cleanup metadata can be consumed exactly once.
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so `refreshDownloads()` can consume the recovery summary and fold it into the download diagnostic path.
- Added a dedicated recovered-session diagnostic path that records how many interrupted tasks were restored and how many stale `.part` files were removed before the queue became retryable again.
- Normalized restored interrupted-item raw error text to match the typed user-facing failure summary so download diagnostics do not emit redundant raw-error lines for this case.
- Expanded `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift` and `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for one-shot recovery-summary consumption and end-to-end diagnostic generation after relaunch.

**Reason**
- Persisting queue state across relaunch fixed recovery semantics, but without recovery metadata in diagnostics it was still hard to tell whether the app had only marked tasks failed or had also cleaned stale partial files and preserved a meaningful retry path.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'DownloadManagerTests|ModelTests'`
- `swift test --jobs 1`

**Risks / Notes**
- Recovery diagnostics are intentionally one-shot per restored session. After the first refresh they fall back to the normal download-failure dedupe path, with the richer recovered-session diagnostic preserved as the latest recorded download report.

### 2026-06-18 — Persist interrupted download sessions across app relaunches

**Task**
- Continue the native download reliability push by making the queue recover coherently after the app is closed mid-download.

**Changed**
- Added `downloadSessionURL` to `macos/Sources/CPaperNativeApp/Backend/Persistence/AppStoragePaths.swift` and introduced `DownloadSessionStore` in `macos/Sources/CPaperNativeApp/Backend/Persistence/DownloadSessionStore.swift` to persist the active download session snapshot, task list, queue items, options, and proxy configuration.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift` so `DownloadDestinationTask` is codable and can be stored/restored as part of the persisted session.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift` to save session state during queue lifecycle changes, restore the last session on startup, normalize unfinished `pending`/`downloading` items into a typed interrupted failure, and keep queue retry working after relaunch.
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` to wire the new session store into the active download manager.
- Updated `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` so download failures now include the typed `.interrupted` case with retry-now semantics.
- Expanded `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift` and `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for interrupted-session restore, retry-after-relaunch behavior, and the new typed recovery mapping.

**Reason**
- The queue had become much clearer within a single app run, but closing the app during a download still dropped context and left the next launch unable to explain what happened or continue from a meaningful recovery state.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter 'DownloadManagerTests|ModelTests|PersistenceTests'`
- `swift test --jobs 1`

**Risks / Notes**
- This restores queue semantics across relaunches, not byte-range resume. Interrupted items are intentionally reclassified as retryable failures and any orphan `.part.*` files for those tasks are cleaned before retry.

### 2026-06-18 — Model post-failure recovery actions for download items

**Task**
- Continue the native download workflow cleanup by making “what the user should do next” explicit instead of leaving it implicit in failure strings.

**Changed**
- Added `DownloadTaskRecoveryAction` in `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` and exposed `DownloadTaskItem.recoveryAction` to model retry-now, retry-later, inspect-diagnostic, restart-if-needed, and no-action states.
- Updated `DownloadTaskItem` so failed and cancelled downloads now expose both a typed recovery action and optional recovery guidance alongside the existing message/raw-error split.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so download failure diagnostics include `Suggested Action` in addition to typed reason, raw error, and save path.
- Updated `macos/Sources/CPaperNativeApp/Views/DownloadsView.swift` so the queue table shows the typed guidance line under each item’s main status message when follow-up action matters.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for recovery-action mapping, cancelled/done behavior, and the new diagnostic detail shape.

**Reason**
- Even after separating display text from raw errors, the download chain still left retry/manual follow-up semantics implicit, which weakens the state model and makes user-facing recovery behavior harder to keep consistent.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- This is still descriptive state only; the app does not yet offer per-item retry buttons or action routing based on `DownloadTaskRecoveryAction`.

### 2026-06-18 — Separate download failure display text from raw error details

**Task**
- Continue the native download-state cleanup by splitting stable user-facing failure semantics from raw backend error strings.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` so `DownloadTaskErrorType` now provides stable user-visible failure messages and `DownloadTaskItem` exposes both `message` and `rawErrorMessage`.
- Changed `DownloadTaskItem.message` to prefer the typed failure summary for failed/cancelled items instead of directly surfacing raw backend error strings into the table UI.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so download failure diagnostics record a typed `Reason`, optionally a separate `Raw Error`, and the `Save Path`.
- Expanded the download failure dedupe signature to include `errorType` so a semantic failure-kind change still counts as a new diagnostic.
- Added regression coverage in `macos/Tests/CPaperNativeTests/ModelTests.swift` for typed failure messaging and download diagnostics that keep typed reason and raw error separate.

**Reason**
- The download item model had already typed failure kinds, but the UI and diagnostics still depended directly on the raw `error` string, which mixed machine detail with user-facing state and made failure reporting easier to drift.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- This turn keeps wire compatibility by preserving the stored raw `error` field. A later step could push the same semantic split down into any retry/manual-action policy if the app starts exposing per-item retry affordances.

### 2026-06-18 — Move preview cancellation and retry semantics into AppModel

**Task**
- Continue the native preview workflow hardening by fixing cancellation/retry semantics and moving preview load orchestration out of the view layer.

**Changed**
- Extended `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift` with `PreviewLoadRequest`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` to own `previewLoadState`, `previewLoadRevision`, `previewLoadRequest`, and the new preview workflow helpers `retryPreview()`, `closePreview()`, and `loadSelectedPreviewIfNeeded()`.
- Reset preview state automatically when `selectedPreview` changes so stale preview results do not bleed across file switches.
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` to render and drive preview loading entirely from `AppModel` instead of its own local async state.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for preview request resets, cancellation that should not emit failure diagnostics, and stale completion from an older preview request not overwriting a newer selection.

**Reason**
- Preview loading was still orchestrated in the view, which made cancellation semantics hard to verify and allowed normal task cancellation during file switches or retries to be treated like real preview failures.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- Preview work is now model-driven, but the actual async task is still launched from the view via `.task(id:)`. A future step could move preview execution ownership even lower if the app later needs prefetching or cross-view preview reuse.

### 2026-06-18 — Model source warnings and preview load state explicitly

**Task**
- Continue the native release-quality push by replacing two remaining implicit UI workflow states in the source and preview chains with explicit models.

**Changed**
- Added `SourceWarningNotice` and `PreviewLoadState` in `macos/Sources/CPaperNativeApp/Models/WorkflowStateModels.swift`.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+PaperWorkflow.swift` so source warnings are stored as a diagnostic-backed notice instead of a bare message string.
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift` and `BatchPreviewPanel.swift` so inline source warning actions use the exact diagnostic carried by the visible notice.
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` so preview loading now uses a single explicit load state (`idle/loading/loaded/failed`) instead of separate `isDownloading/localURL/loadingError` flags.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` to cover the new source-warning notice semantics and preview load state behavior.

**Reason**
- Source warnings and preview failures had already become user-visible contextual flows, but their state still depended on split strings and parallel flags, which made the workflow semantics harder to reason about and easier to drift.

**Tested**
- `git diff --check`
- `swift test --jobs 1 --filter ModelTests`
- `swift test --jobs 1`

**Risks / Notes**
- This turn only models the state more explicitly; it does not yet move preview loading orchestration into `AppModel` or add dedicated UI interaction tests for the retry/copy actions.

### 2026-06-18 — Type download queue phase state

**Task**
- Continue the native reliability push by removing stringly-typed download queue phases from the core status model.

**Changed**
- Added `DownloadQueuePhase` and updated `DownloadStatusSnapshot` in `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` to use the enum instead of raw phase strings.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift` and `macos/Sources/CPaperNativeApp/State/AppModel.swift` to read and write the typed phase.
- Added a round-trip regression test in `macos/Tests/CPaperNativeTests/ModelTests.swift`.

**Reason**
- The download state machine still depended on magic strings for `idle`, `running`, and `done`, which is fragile and spreads semantic drift across code and tests.

**Tested**
- Not yet run in this turn; verification follows after the code changes.

**Risks / Notes**
- This is a state-model change only. It should not alter queue behavior, but it does require the existing tests to be updated to the typed phase.

### 2026-06-18 — Finish typed download phase test migration

**Task**
- Unblock the typed download queue phase change by migrating the remaining `DownloadManager` assertions off raw `"done"` strings.

**Changed**
- Updated `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift` so the two remaining queue completion assertions now check `DownloadQueuePhase.done`.

**Reason**
- The implementation had already switched to the enum-backed phase model, but stale string assertions were still breaking the targeted download/model test build.

**Tested**
- Verification runs follow immediately after this test-only sync.

**Risks / Notes**
- This is a test-only migration. If broader phase string assumptions still exist elsewhere, the next verification pass should expose them.

### 2026-06-18 — Type download task error kinds

**Task**
- Continue the native download-state cleanup by removing raw string error kinds from `DownloadTaskItem`.

**Changed**
- Added `DownloadTaskErrorType` in `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` and changed `DownloadTaskItem.errorType` to the typed enum.
- Added compatibility decoding so legacy empty `error_type` strings decode as no error kind, while unknown future values degrade to `.unknown`.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift` and `DownloadDestinationBuilder.swift` to write enum-backed error kinds instead of magic strings.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with compatibility and round-trip coverage for the typed error kind.

**Reason**
- The queue phase was already typed, but download-item error kinds still relied on ad hoc strings for cancellation, rate limiting, and network failures, which left another fragile state channel in the core download path.

**Tested**
- Verification follows immediately after the model and test updates.

**Risks / Notes**
- This keeps wire compatibility for empty legacy `error_type` values. Unknown future raw values are intentionally normalized to `.unknown` instead of failing decoding.

### 2026-06-18 — Unify source warning visibility and diagnostic flow

**Task**
- Continue the source/preview consistency cleanup by making successful searches and batch previews handle source warnings through the same visible diagnostic path.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so both `search()` and `previewBatch()` call a shared `applySourceWarnings(_:)` helper.
- The new helper records source warnings into diagnostics, mirrors the first warning into `errorMessage`, and clears only the currently visible source-provider alert when a later successful source operation returns no warnings.
- Added regression coverage in `macos/Tests/CPaperNativeTests/ModelTests.swift` for warning presentation, stale source-warning clearing, and preserving unrelated visible errors.

**Reason**
- Search success and batch-preview success were handling warnings differently, and successful source refreshes could leave a stale source warning visible even after the condition disappeared.

**Tested**
- Verification follows immediately after the workflow and test updates.

**Risks / Notes**
- This intentionally clears only visible source-provider alerts tied to the latest source diagnostic. Unrelated download/update/general alerts remain untouched.

### 2026-06-18 — Move source warnings out of the global error alert

**Task**
- Continue the source workflow cleanup by separating non-fatal source warnings from fatal app-wide alerts.

**Changed**
- Added `sourceWarningMessage` to `macos/Sources/CPaperNativeApp/State/AppModel.swift` and changed `AppModel+PaperWorkflow.swift` so search/batch source warnings populate that contextual field instead of `errorMessage`.
- Cleared stale source warnings at the start of source refreshes and on fatal source failures so old partial-warning state does not bleed into a new run.
- Added reusable `SourceWarningCard` in `macos/Sources/CPaperNativeApp/Views/WorkflowChrome.swift` and rendered it in both `SearchView.swift` and `BatchPreviewPanel.swift`, with inline actions to copy diagnostics or reveal the support folder.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` to cover the new non-modal warning state and stale-warning clearing on source failures.

**Reason**
- Source warnings represent partial degradation on otherwise successful search/preview flows, so showing them through the same modal alert channel as fatal errors was too disruptive and muddied the distinction between degraded success and outright failure.

**Tested**
- Verification follows immediately after the state/view/test updates.

**Risks / Notes**
- The warning card still reflects only the first warning in its headline text while the copied diagnostic keeps the fuller warning list for support.

### 2026-06-18 — Add inline preview retry and support actions

**Task**
- Continue the preview workflow hardening by making preview failures recoverable in place instead of forcing the user to reselect the file.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` so failed preview loads render inline actions for `重试预览`、`复制诊断`、`显示支持文件夹`.
- Added a local preview load revision token so retrying the same selected file actually reruns the preview load task without changing selection state.

**Reason**
- Preview failures were diagnosable but not locally recoverable; the user had to close and re-open the same file to trigger another load attempt.

**Tested**
- Verification follows immediately after the view update.

**Risks / Notes**
- This is a view-layer interaction change, so validation is compile/full-test coverage plus static inspection rather than a focused unit test for button taps.

### 2026-06-18 — Preserve diagnostics by context while keeping a global latest

**Task**
- Continue the diagnostics lifecycle cleanup by preventing context-specific support actions from accidentally copying an unrelated later failure.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` to keep `diagnosticsByContext` alongside the existing global `lastDiagnostic`, and added helpers to read/copy the latest diagnostic for a specific `SupportDiagnosticContext`.
- Marked `SupportDiagnosticContext` as `Hashable` in `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift` so it can key the per-context map.
- Updated source warning cards and the preview failure panel to copy the diagnostic for their own context instead of blindly copying the most recent diagnostic from anywhere in the app.
- Added `macos/Tests/CPaperNativeTests/ModelTests.swift` coverage proving source/preview/download diagnostics stay independently addressable while `lastDiagnostic` still tracks the global latest failure.

**Reason**
- Inline source/preview recovery surfaces had already become context-specific, but their “复制诊断” actions still depended on the shared `lastDiagnostic`, so a later failure in another workflow could make them copy the wrong report.

**Tested**
- Verification follows immediately after the model/view/test updates.

**Risks / Notes**
- Settings and menu-bar actions intentionally keep using the global latest diagnostic because their copy affordance is explicitly framed as “最近一次失败”.

### 2026-06-18 — Deduplicate repeated download failure diagnostics

**Task**
- Continue the diagnostics lifecycle cleanup by stopping completed download refreshes from rewriting the same failure report over and over.

**Changed**
- Added `lastDownloadFailureDiagnosticSignature` in `macos/Sources/CPaperNativeApp/State/AppModel.swift`.
- Updated `AppModel+PaperWorkflow.swift` so `recordDownloadFailuresIfNeeded` resets when downloads are running or fully clean, but only writes a new download diagnostic when the failed-item set actually changes.
- Expanded `macos/Tests/CPaperNativeTests/ModelTests.swift` with coverage for both deduping an unchanged failure set and regenerating the diagnostic when the failure set grows.

**Reason**
- The downloads view can refresh repeatedly after a run finishes, and without deduping it kept rewriting the same download failure diagnostic, which adds report churn without new signal.

**Tested**
- Verification follows immediately after the state and test updates.

**Risks / Notes**
- The dedupe key intentionally tracks failed item id, filename, error text, and save path. A changed failure message for the same file still counts as a new diagnostic.

### 2026-06-18 — Localize remaining low-level backend errors

**Task**
- Continue the native quality push by removing the last obvious English error strings from shared download and source-parsing paths.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadDestinationBuilder.swift` to localize invalid save-directory errors.
- Updated `macos/Sources/CPaperNativeApp/Backend/Sources/FrankcieSource.swift` and `macos/Sources/CPaperNativeApp/Backend/Sources/EasyPaperSource.swift` so invalid JSON, invalid encrypted data, and AES failure errors use Chinese text.
- Added/updated regression coverage in `macos/Tests/CPaperNativeTests/DownloadDestinationBuilderTests.swift` and `macos/Tests/CPaperNativeTests/PaperSourceFixtureTests.swift`.

**Reason**
- These remaining low-level messages still surfaced directly into user-visible and diagnostic paths, making the app’s failure reporting inconsistent.

**Tested**
- `swift test --jobs 1 --filter 'DownloadDestinationBuilderTests|PaperSourceFixtureTests|HTTPFileTransferClientTests|CircuitBreakerTests|ModelTests|SourceRegistryTests|SupportDiagnosticsTests'`
- `git diff --check`

**Risks / Notes**
- This is still a messaging-only cleanup. Parsing and destination logic stay unchanged.

### 2026-06-18 — Localize shared network and breaker errors

**Task**
- Continue the native quality push by localizing low-level network and breaker errors that surface through search, preview, download, and update diagnostics.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Networking/NetworkClient.swift` so shared HTTP/429/decoding errors return Chinese localized descriptions.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/CircuitBreaker.swift` so the breaker-open error also uses Chinese text.
- Added regression coverage in `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift` and `macos/Tests/CPaperNativeTests/CircuitBreakerTests.swift`.

**Reason**
- These low-level English errors were still leaking directly into multiple user-visible chains and support diagnostics.

**Tested**
- Not yet run in this turn; verification follows after the code changes.

**Risks / Notes**
- This is a messaging/observability change only; it does not alter retry, transfer, or breaker behavior.

### 2026-06-18 — Localize source attempt and error messages

**Task**
- Continue the native quality cleanup by making source/search failure reporting consistent with the rest of the Chinese UI and diagnostics.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Sources/PaperSource.swift` so source attempt messages and source-availability errors use localized Chinese text.
- Added regression coverage in `macos/Tests/CPaperNativeTests/SourceRegistryTests.swift` for localized attempt messages and error descriptions.

**Reason**
- Search-chain diagnostic text still mixed English and Chinese, which made failures less consistent for users and support reports.

**Tested**
- Not yet run in this turn; verification follows after the code changes.

**Risks / Notes**
- This is a text/observability change only; it does not alter source-selection behavior.

### 2026-06-18 — Unify visible errors with support diagnostics

**Task**
- Continue the native maintainability push by tightening the link between user-visible failures and the support-diagnostic path.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel.swift` to add a shared `presentDiagnosticError` path and routed invalid save-directory errors through it.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so update check failures, download failures, and DMG auto-open failures all use the same diagnostic-backed error presentation path.
- Added regression coverage in `macos/Tests/CPaperNativeTests/ModelTests.swift` for save-directory errors and update open failures so the latest visible error always matches the latest diagnostic.

**Reason**
- Several failures still wrote `errorMessage` directly, which could leave `lastDiagnostic` pointing at an older issue and weaken support/debugging value.

**Tested**
- `swift test --jobs 1 --filter 'ModelTests|SupportDiagnosticsTests'`
- `git diff --check`

**Risks / Notes**
- This keeps the current alert UX intact; it only makes the alert and copied diagnostic refer to the same latest failure.

### 2026-06-18 — Factor shared staged file finalize helper

**Task**
- Continue the long-term native quality push by reducing duplicated finalization logic across download, preview, and update flows.

**Changed**
- Added `macos/Sources/CPaperNativeApp/Backend/Downloads/StagedFileSystem.swift` as a shared helper for staged writes, cancellation checks, partial cleanup, and atomic promotion.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift`, `macos/Sources/CPaperNativeApp/Backend/Downloads/PreviewFileService.swift`, and `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift` to use the shared staged-write path.
- Added `macos/Tests/CPaperNativeTests/StagedFileSystemTests.swift` to cover shared finalize and cancellation behavior directly.

**Reason**
- The same partial-file finalization pattern was duplicated in three critical code paths, which made cancellation and cleanup semantics easy to drift apart.

**Tested**
- `swift test --jobs 1 --filter 'StagedFileSystemTests|NativeBackendServicePreviewTests|UpdateServiceTests|ModelTests|DownloadManagerTests'`
- `git diff --check`

**Risks / Notes**
- This is a structural consolidation, so the main risk is an accidental semantic drift in one of the three call sites; the new helper tests are meant to catch that.

### 2026-06-18 — Harden preview cache cancellation before finalize

**Task**
- Continue the native reliability cleanup by closing the remaining preview-cache cancellation window after tightening the update download path.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/PreviewFileService.swift` to propagate outer cancellation into the in-flight preview task and to check cancellation again after the preview transfer finishes but before promoting the cached file into place.
- Added regression coverage in `macos/Tests/CPaperNativeTests/NativeBackendServicePreviewTests.swift` for cancellation after partial preview data is written but before final cache commit.

**Reason**
- Preview caching still had the same finalize-phase race that was just fixed in the update downloader, so cancellation could otherwise leave a final cache file behind.

**Tested**
- `swift test --jobs 1 --filter 'NativeBackendServicePreviewTests/testPreviewURLCancelsInFlightTransferBeforeFinalCacheCommit|NativeBackendServicePreviewTests/testPreviewURLDoesNotLeaveFinalCacheFileWhenTransferFailsAfterWritingPartialData|UpdateServiceTests/testDownloadUpdateDoesNotCommitFinalFileWhenCancelledBeforeFinalize|ModelTests/testDownloadAvailableUpdateFailureRestoresAvailableStatusForRetry'`

**Risks / Notes**
- This change only tightens preview-cache finalization; it does not alter download-queue cancellation behavior.

### 2026-06-18 — Fix update retry state and finalize cancellation window

**Task**
- Repair the native update flow after review found that a failed update download lost its retry affordance and that final file commit could still slip past cancellation.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Updates.swift` so update download failures keep the update status available for retry instead of only surfacing an error.
- Added a pre-finalize cancellation checkpoint to `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift`.
- Added regression coverage in `macos/Tests/CPaperNativeTests/ModelTests.swift` and `macos/Tests/CPaperNativeTests/UpdateServiceTests.swift`.

**Reason**
- The retry path and final commit boundary both needed tighter handling with minimal code changes.

**Tested**
- `swift test --jobs 1 --filter 'ModelTests/testDownloadAvailableUpdateFailureRestoresAvailableStatusForRetry|ModelTests/testDownloadAvailableUpdateOpenFailureKeepsDownloadedURLAndShowsGuidance|UpdateServiceTests/testDownloadUpdateDoesNotCommitFinalFileWhenCancelledBeforeFinalize|UpdateServiceTests/testDownloadUpdateDoesNotMoveFileIntoFinalLocationAfterCancellation|UpdateServiceTests/testDownloadUpdateStreamsThroughSharedTransferAndAtomicallyReplacesExistingFile'`
- `swift test --jobs 1 --filter 'ModelTests|UpdateServiceTests|NativeBackendServicePreviewTests|DownloadDestinationBuilderTests'`

**Risks / Notes**
- This change intentionally stayed focused on the update path; broader staged-write consolidation was handled separately.

### 2026-06-09 — Fix native parsing, preview cache, update download, and stale state edges

**Task**
- Implement the minimal native-only fixes for confirmed settings compatibility, version parsing, proxy coverage, PastPapers entry parsing, preview cache safety, update partial-file handling, stale result clearing, and preview diagnostic redaction gaps.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Models/DownloadModels.swift` to make `DownloadSettings` decode legacy partial JSON with defaults for missing keys.
- Tightened `AppVersion` parsing in `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift`, switched update downloads to unique `.part.<UUID>` files, and added a cancellation gate before final replace/move.
- Expanded `macos/Sources/CPaperNativeApp/Backend/Networking/ProxyConfiguration.swift` so `http://...` proxies also configure HTTPS requests.
- Reworked `macos/Sources/CPaperNativeApp/Backend/Sources/PastPapersModels.swift` to decode flat entry objects without depending on JSON key order.
- Hardened `macos/Sources/CPaperNativeApp/Backend/Downloads/PreviewFileService.swift` and `DownloadDestinationBuilder.swift` so preview caching validates filenames, uses one in-flight transfer per cache target, and writes through unique temporary files before atomically promoting the final cache file.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` to clear stale search/batch results on failure and expanded preview diagnostic query-secret redaction in `macos/Sources/CPaperNativeApp/Models/SupportDiagnostics.swift`.
- Added regression coverage in `PersistenceTests`, `UpdateServiceTests`, `HTTPFileTransferClientTests`, `PaperSourceFixtureTests`, `NativeBackendServicePreviewTests`, `ModelTests`, and `SupportDiagnosticsTests`.

**Reason**
- The native app had confirmed upgrade-compatibility bugs, proxy misconfiguration for HTTPS traffic, parser fragility against upstream field reordering, preview cache path/concurrency holes, update partial-file edge cases, stale UI state after failed fetches, and incomplete query-secret redaction in support diagnostics.

**Tested**
- `swift test --jobs 1 --filter 'PersistenceTests|UpdateServiceTests|HTTPFileTransferClientTests|PaperSourceFixtureTests'`
- `swift test --jobs 1 --filter 'NativeBackendServicePreviewTests|UpdateServiceTests'`
- `swift test --jobs 1 --filter 'ModelTests|SupportDiagnosticsTests'`

**Risks / Notes**
- This change intentionally does not expand scope into startup update timing, `relPath` trust hardening, or download-plan deduplication; those remain separate concerns unless a future task explicitly pulls them in.

### 2026-06-08 — Fix native release workflow secret gating

**Task**
- Repair the native GitHub Actions workflow after `Prepare 6.0.5 release` failed before any jobs started with a workflow-file error.

**Changed**
- Updated `.github/workflows/build.yml` so the optional Developer ID / notarization setup step no longer uses `secrets.*` directly inside the step-level `if`.
- Moved the “are all optional signing secrets present?” check into the shell script itself, and made the step exit cleanly back to the ad hoc signing path when any optional secret is missing.

**Reason**
- GitHub Actions rejected the workflow definition itself because `secrets` is not available in that `if` expression context, so the release workflow never reached `validate`, `package`, or `release`.

**Tested**
- `/Users/yimingwu/Documents/C-Paper/.tmp-bin/actionlint .github/workflows/build.yml`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "ok"'`

**Risks / Notes**
- The release tag needs to be pushed again after this workflow fix so GitHub Actions can rerun the `v6.0.5` release path with the corrected workflow.

### 2026-06-08 — Prepare native 6.0.5 release

**Task**
- Bump the native release version after the download/update experience fixes and prepare the next GitHub Release payload.

**Changed**
- Updated `version.json`, `README.md`, and `BackendConstants.version` from `6.0.4` to `6.0.5`.
- Added `.github/release-notes/native-v6.0.5.md`.
- Refreshed release metadata so the GitHub release URL, release notes summary, and published date point to `v6.0.5`.

**Reason**
- The repository now includes the download 429 recovery, clearer save-location/update feedback, and searchable subject picker improvements, so the published native version needs to move past the existing `v6.0.4` release.

**Tested**
- `bash scripts/check_version_drift.sh`
- `swift test --jobs 1`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

**Risks / Notes**
- Tag push is still the actual GitHub Release trigger; metadata prep alone does not publish the release.

### 2026-06-08 — Fix download throttling, update download UX, and subject picker

**Task**
- Complete `cpaper-download-update-experience-plan.md` through the implementation wave for download 429 recovery, clearer download/update destinations, update auto-open behavior, and the compact searchable subject picker.

**Changed**
- Added queue-wide HTTP 429 cooldown handling in the native download manager, including `Retry-After` metadata, shared request gating, Chinese retry-wait messaging, and real byte progress for shared transfers.
- Updated the downloads page to show the active save directory, expose a `显示文件夹` action, and distinguish processed progress from successful downloads.
- Updated native update downloads to expose their destination path, preserve progress/location state, automatically open the downloaded DMG, and keep a manual-open hint if auto-open fails.
- Replaced the long subject menu with a searchable fixed-size popover backed by `SubjectPickerLogic`.
- Kept the initial subject picker state unselected when there is no saved subject, so the default remains `选择科目` instead of auto-selecting the first loaded subject.

**Reason**
- User screenshots and diagnostics showed 148 download failures after HTTP 429, unclear download/update destinations, weak update download feedback, no automatic DMG opening, and an oversized subject picker menu.

**Tested**
- GREEN: `swift test --jobs 1 --filter DownloadManagerTests`
- GREEN: `swift build --jobs 1`
- GREEN: `swift test --jobs 1 --filter 'ModelTests|AppMenuCommandCenterTests|UpdateServiceTests'`
- GREEN: `swift test --jobs 1 --filter 'DownloadManagerTests|DownloadDestinationBuilderTests|HTTPFileTransferClientTests|UpdateServiceTests|ModelTests|AppMenuCommandCenterTests|SubjectPickerLogicTests'`
- GREEN: `swift test --jobs 1`: 122 executed tests, 4 intentionally skipped live-source tests, 0 failures.
- GREEN: `git diff --check`
- `swift run CPaperNative` built and launched the native app; user-confirmed visual QA passed.
- Follow-up GREEN: `swift test --jobs 1 --filter ModelTests`
- Follow-up GREEN: `swift build --jobs 1`
- Follow-up GREEN: `swift test --jobs 1`

**Risks / Notes**
- Live third-party source availability is still external and intentionally not used as deterministic validation; 429 recovery is covered with injected deterministic test transfers.
- SwiftUI popover behavior was checked manually in the launched app and confirmed by the user.

### 2026-06-08 — Plan download and update experience fixes

**Task**
- Create a swarm-ready implementation plan for fixing download 429 handling, download destination/progress visibility, update DMG feedback/auto-open behavior, and the long subject picker.

**Changed**
- Added `cpaper-download-update-experience-plan.md`.
- Revised the plan after subagent review to specify queue-wide 429 cooldown gating, update-open failure handling, testable subject filtering helpers, deterministic QA stubs, and single-owner work-log consolidation.

**Reason**
- The reported latest build issues span networking, state, and SwiftUI surfaces, so the follow-up implementation needs explicit dependencies for parallel execution.

**Tested**
- `git diff --check -- cpaper-download-update-experience-plan.md`
- Read-only review of relevant active macOS files and subagent plan review.

**Risks / Notes**
- This entry records planning only; no application code was changed or tested.

### 2026-06-06 — Prepare native 6.0.4 release

**Task**
- Bump the native release version, sync release metadata, and prepare a new GitHub release from `main`.

**Changed**
- Updated `version.json`, `README.md`, and `macos/Sources/CPaperNativeApp/Backend/Core/BackendConstants.swift` from `6.0.3` to `6.0.4`.
- Added `.github/release-notes/native-v6.0.4.md`.
- Updated update-related Swift tests to use `6.0.3 -> 6.0.4` as the release progression.

**Reason**
- `main` now contains the Chinese macOS menu bar and the broader native professionalization work, so the published version needed to move forward from the already-existing GitHub `v6.0.3` release.

**Tested**
- `bash scripts/check_version_drift.sh`
- `swift test --jobs 1 --filter 'ModelTests|UpdateServiceTests'`
- `swift test --jobs 1`: passed with 95 executed tests, 4 skipped live-source tests, and 0 failures.
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`
- `hdiutil verify dist/C-Paper-Native-6.0.4-standalone-20260606.dmg`
- Mounted `dist/C-Paper-Native-6.0.4-standalone-20260606.dmg` and ran `codesign --verify --deep --strict` on the mounted `CPaperNative.app`.

**Risks / Notes**
- Release publication should happen from a new `v6.0.4` tag after local validation passes.

### 2026-06-06 — Complete Chinese macOS menu bar validation

**Task**
- Complete final validation and screenshot QA for `cpaper-chinese-macos-menu-plan.md`.

**Changed**
- Updated `cpaper-chinese-macos-menu-plan.md` to mark T6 complete and record final validation evidence.
- Added this work-log entry for the final menu-bar QA pass.

**Reason**
- The Chinese menu bar implementation needed final full-suite validation, release packaging confirmation, and visual proof before closing the plan.

**Tested**
- `swift test --jobs 1`: passed with 95 executed tests, 4 skipped live-source tests, and 0 failures.
- `git diff --check`: passed with no output before final record edits.
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`: passed and rebuilt `dist/CPaperNative.app` plus `dist/C-Paper-Native-6.0.3-standalone-20260606.dmg`.
- Launched `dist/CPaperNative.app`.
- User-provided screenshot confirmed the macOS menu bar shows `C-Paper`, `文件`, `编辑`, `显示`, `窗口`, and `帮助`.

**Risks / Notes**
- No merge, push, or `main` branch edit was performed.
- Live source tests remain skipped unless `RUN_LIVE_SOURCE_TESTS=1` is set.
- No download-start or update-download action was triggered during QA.

### 2026-06-06 — Document Chinese macOS menu bar integration

**Task**
- Update active project documentation after the native Chinese AppKit menu bar landed.

**Changed**
- Updated `docs/PROJECT_INDEX.md` to list the active AppKit menu layer and its startup/binding roles.
- Updated `cpaper-chinese-macos-menu-plan.md` to mark T5 complete and record static validation evidence.
- Appended this `docs/WORK_LOG.md` entry.

**Reason**
- The active native file map needed to reflect the new menu infrastructure without naming legacy or inactive paths as current UI.

**Tested**
- Static validation only for this documentation task:
- `git diff --check` -> no output
- Reviewed active native menu files referenced by the docs: `macos/Sources/CPaperNativeApp/AppDelegate.swift`, `AppMenuCommand.swift`, `AppMenuCommandCenter.swift`, `AppMenuController.swift`, `Views/RootView.swift`
- Manual screenshot validation was not performed in T5; screenshot QA remains owned by T6.

**Risks / Notes**
- This task intentionally did not rerun menu behavior tests; implementation and smoke coverage were already recorded by T1-T4.

### 2026-06-06 — Correct active architecture boundaries

**Task**
- Correct misleading active/legacy/site documentation before deeper implementation tasks.

**Changed**
- Updated `MAINTENANCE_BASELINE.md`, `docs/PROJECT_INDEX.md`, `README.md`, and `native/CPaperNative/README.md`.
- Reframed the active implementation as root `Package.swift`, `macos/`, Swift-native backend, and active `scripts/`, `assets/`, `docs/`.
- Moved Python bridge/backend references to archived `legacy/python-backend/` and replaced in-repo `site/` claims with an external project-site note marked link pending.
- Updated `cpaper-professionalization-plan.md` to mark T0.3 completed.

**Reason**
- Several current docs still described removed root Python backend paths and an in-repo `site/` directory as part of the active implementation.

**Tested**
- Ran static text checks on the four target docs with `rg -n` for `bridge/`, `backend/`, `site/`, `requirements.txt`, and `pytest`.
- Confirmed no target doc now describes root `bridge/`, root `backend/`, or in-repo `site/` as active implementation.

**Risks / Notes**
- This task intentionally did not revise broader release-flow or signing/notarization documentation; later plan tasks own that work.

### 2026-05-29 — Add project memory documentation

**Task**
- Add lightweight AI-facing project documentation files for future coding sessions.

**Changed**
- Created `AGENTS.md`.
- Created `docs/PROJECT_INDEX.md`.
- Created `docs/WORK_LOG.md`.
- Documented project purpose, detected stack, directory map, safe working rules, and a reusable work-log format.

**Reason**
- The repository needed a compact project memory system so future agents can orient themselves quickly without scanning the entire codebase.

**Tested**
- Checked repository structure and key metadata files before writing docs.
- Reviewed `README.md`, `requirements.txt`, `src/`, `native/`, `scripts/`, and `tests/` at a directory/file level.
- No application code changes were made or executed.

**Risks / Notes**
- Some native macOS details remain `Unknown / not yet documented` because they were not deeply inspected.
- Commands were recorded only where they could be supported by existing repository docs or file layout.

### 2026-05-29 — Repository cleanup pass

**Task**
- Safely clean the repository structure, remove obvious junk, and delete obsolete documentation drafts confirmed for cleanup.

**Changed**
- Removed `.DS_Store` files from tracked source/documentation directories.
- Removed obsolete documentation drafts: `README 2.md`, `handoff.md`, `handoff-inline-pdf-preview.md`, `native-inline-pdf-preview-plan.md`, and the files under `docs/superpowers/`.
- Removed the empty `examples/plugins/notify/` directory and its empty parent directories if applicable.
- Updated `AGENTS.md` and `docs/PROJECT_INDEX.md` to reflect the cleaned structure and cleanup guidance.

**Reason**
- The repository contained obvious macOS junk files, empty example directories, and stale planning/handoff documents that made future navigation harder.

**Tested**
- Checked candidate files for references before deletion.
- Ran `pytest`.
- Verified the cleanup scope was limited to documentation/junk items and did not include application code changes.

**Risks / Notes**
- `.claude/worktrees/`, `.agents/`, `.codex/`, `bin/claude-haha`, and `script/build_and_run.sh` were left in place because their purpose is not fully confirmed.
- The main application, native source, assets, configs, and static site were intentionally left untouched.

### 2026-05-29 — Native-first repository reorganization

**Task**
- Reorganize the repository so the native macOS version becomes the clear primary project and the old pywebview frontend becomes legacy.

**Changed**
- Moved the Swift package root to `Package.swift` and the active Swift source/test trees to `macos/`.
- Moved the active Python bridge to `bridge/` and the active shared Python backend to `backend/`.
- Moved the old pywebview frontend and its packaging scripts to `legacy/pywebview/`.
- Updated native bridge lookup, native build scripts, Python test bootstrap, and legacy packaging paths.
- Replaced the old dual GitHub workflow setup with one native-first workflow at `.github/workflows/build.yml`.
- Updated `README.md`, `AGENTS.md`, `docs/PROJECT_INDEX.md`, and `MAINTENANCE_BASELINE.md` to document the new maintenance model.

**Reason**
- The repository direction changed: the native macOS app is now the only actively maintained product line, while the pywebview frontend is retained only as legacy source.

**Tested**
- `swift test`
- `pytest`
- `python -m py_compile bridge/cpaper_bridge.py backend/*.py legacy/pywebview/main.py`
- `bash -n scripts/build_native_dmg.sh`
- `bash -n legacy/pywebview/packaging/build_mac.sh`
- `bash scripts/build_native_dmg.sh`

**Risks / Notes**
- The native app still depends on Python bridge + shared backend, so `backend/` remains active and is not legacy.
- Git branch consolidation to leave only `main` was not completed in-file; it still requires an explicit Git merge/delete operation after the workspace is clean.
- Native DMG build completed successfully, but the build log still showed best-effort codesign warnings for the assembled app bundle.

### 2026-05-29 — Prepare final legacy 5.2.1 release flow

**Task**
- Prepare a GitHub Actions-based final legacy release for the Python + pywebview version, including DMG and EXE artifacts, versioned as 5.2.1, with detailed release notes and the old icon.

**Changed**
- Added a dedicated legacy release workflow at `.github/workflows/legacy-release.yml`.
- Added detailed release notes at `.github/release-notes/legacy-v5.2.1.md`.
- Added a legacy-only old icon copy at `legacy/pywebview/assets/icon.icns`.
- Updated legacy packaging scripts to use the legacy icon and explicit backend search paths needed after the repository reorganization.

**Reason**
- The repository still needs one final archival release for legacy users even though the main maintained product has moved to the native macOS version.

**Tested**
- Checked the legacy packaging scripts and workflow inputs statically.

**Risks / Notes**
- The Windows EXE artifact is intended to be built on GitHub Actions, not locally on this macOS machine.
- This workflow is a special-purpose legacy release path and should not replace the native main release workflow.

### 2026-05-29 — Fix legacy release publish conflict

**Task**
- Fix the final legacy 5.2.1 GitHub Actions release flow after the publish job failed with a duplicate-release conflict on the same tag.

**Changed**
- Updated `.github/workflows/legacy-release.yml` so the publish job deletes any existing GitHub release objects for the target legacy tag before creating the final release.

**Reason**
- A previous failed/native-mismatched release object already existed on `v5.2.1-legacy`, which caused the final publish step to fail with `already_exists` even after the correct DMG and Windows archive had been uploaded.

**Tested**
- Reviewed the failed Actions logs for run `26614755058`.
- Verified duplicate release objects existed for the same tag before applying the workflow fix.

**Risks / Notes**
- This workflow now recreates the release object for the final legacy tag on rerun, which is acceptable because the release is archival and the artifacts are rebuilt in the same workflow.

### 2026-05-29 — Add Windows installer for final legacy release

**Task**
- Change the final legacy Windows release artifact from a portable ZIP to an installer EXE generated inside GitHub Actions.

**Changed**
- Added `legacy/pywebview/assets/icon.ico` derived from the legacy icon set for Windows installer branding.
- Added `legacy/pywebview/packaging/legacy_installer.nsi` for NSIS-based Windows installer packaging.
- Updated `legacy/pywebview/packaging/build_win.bat` so the packaged Windows app executable uses the legacy icon.
- Updated `.github/workflows/legacy-release.yml` to install NSIS on `windows-latest`, build `C-Paper-legacy-5.2.1-setup.exe`, and publish that installer instead of the ZIP archive.
- Updated `.github/release-notes/legacy-v5.2.1.md` to describe the Windows installer flow and final asset name.

**Reason**
- The requested final legacy Windows artifact should be a direct installer EXE rather than only a compressed application folder.

**Tested**
- Verified the existing Windows packaging step already produces a runnable `dist\\C-Paper` application directory suitable for NSIS wrapping.
- Checked the workflow and installer inputs statically.

**Risks / Notes**
- NSIS packaging is validated on GitHub Actions rather than locally because this macOS environment does not provide the Windows installer toolchain.
- The installer shell no longer forces a custom icon; the legacy icon is applied to the packaged Windows app executable to keep the release stable.

### 2026-05-29 — Legacy Windows installer handoff status

**Task**
- Record the current blocking state before handing off the remaining legacy Windows installer issue.

**Changed**
- No new product behavior changes were completed in this step.
- Documented the latest GitHub Actions runs and the current suspected blocker for the Windows installer packaging.

**Reason**
- The session needed a clean handoff point with the current failure mode and next investigation steps written down before continuing.

**Tested**
- Reviewed failed GitHub Actions runs:
- `26615356038`: Windows installer failed in NSIS while trying to load a custom installer icon.
- `26615489670`: After removing the installer-shell icon and moving the legacy icon usage to the packaged Windows app executable, the Windows installer step still failed and needs the next log pull before further edits.

**Risks / Notes**
- Current branch: `codex/swift-native-ui`.
- Latest pushed commits related to this issue include:
- `9a9b535` `fix(ci): make legacy release publish idempotent`
- `d0b4b17` `feat(legacy): publish final windows installer exe`
- `003ec4c` `fix(legacy): use nsis-compatible windows icon`
- There is an uncommitted follow-up change that removes the NSIS installer-shell icon requirement and applies the legacy icon through `build_win.bat`; it should be committed before the next rerun.
- The next person should fetch the full failed log for run `26615489670`, job `78430150249`, specifically the `Build legacy Windows installer` step, before changing the workflow again.

### 2026-05-29 — Fix NSIS source path for legacy Windows installer

**Task**
- Fix the remaining Windows installer packaging failure after NSIS could not find the packaged application directory during GitHub Actions.

**Changed**
- Updated `.github/workflows/legacy-release.yml` so the NSIS step runs from `legacy/pywebview/` and passes `dist\\C-Paper` and `dist\\C-Paper-legacy-5.2.1-setup.exe` as local paths instead of repo-root-relative paths.

**Reason**
- The failing run `26615919694` showed that NSIS resolved `legacy\\pywebview\\dist\\C-Paper\\*.*` against the wrong working-directory base and aborted with `no files found`.

**Tested**
- Reviewed failed Actions log for run `26615919694`, job `78431499217`, step `Build legacy Windows installer`.

**Risks / Notes**
- This fix only changes the NSIS invocation base path; it does not change the packaged app contents or release naming.

### 2026-05-29 — Harden NSIS file copy pattern

**Task**
- Continue debugging the remaining legacy Windows installer failure after NSIS still reported `no files found` for the packaged app directory.

**Changed**
- Updated `legacy/pywebview/packaging/legacy_installer.nsi` to use `File /r "${SOURCE_DIR}\\*"` instead of the more brittle `*.*` pattern.
- Updated `.github/workflows/legacy-release.yml` to print `dist\\C-Paper` contents before running `makensis` so the next failure, if any, includes direct evidence of the packaged app directory.

**Reason**
- The failing run `26616003953` showed that NSIS still aborted on the `File /r` line even after the invocation base path was corrected.

**Tested**
- Reviewed failed Actions log for run `26616003953`, job `78431754806`, step `Build legacy Windows installer`.

**Risks / Notes**
- This is still isolated to the legacy Windows installer flow and does not affect the native mainline release path.

### 2026-05-29 — Align NSIS paths with script directory

**Task**
- Fix the next legacy Windows installer failure after confirming the packaged app directory existed but NSIS still could not read it.

**Changed**
- Updated `.github/workflows/legacy-release.yml` so the NSIS defines use `..\\dist\\C-Paper` and `..\\dist\\C-Paper-legacy-5.2.1-setup.exe`, matching the fact that `packaging/legacy_installer.nsi` resolves relative file paths from inside `legacy/pywebview/packaging/`.

**Reason**
- The failed run `26616293330` showed `Get-ChildItem` proving `legacy/pywebview/dist/C-Paper/C-Paper.exe` existed, while NSIS still failed on `File: "dist\\C-Paper\\*" -> no files found`, which indicates a script-directory-relative path mismatch.

**Tested**
- Reviewed failed Actions log for run `26616293330`, job `78432653101`, step `Build legacy Windows installer`.

**Risks / Notes**
- This change only retargets NSIS compile-time file paths; the packaged app directory itself is unchanged.

### 2026-05-29 — Refresh shared app icon assets

**Task**
- Decide what to do with the remaining local icon asset changes after consolidating development onto `main`.

**Changed**
- Updated the shared macOS app icon assets in `assets/icon.icns` and `assets/icon.iconset/`.

**Reason**
- The icon changes are product-facing assets, not temporary build output, and they align with the repository's native-first direction.

**Tested**
- Verified the iconset image metadata.

**Risks / Notes**
- No application code changed in this step.

### 2026-05-29 — Fix native download controls and bump to 5.2.2

**Task**
- Check native frontend functionality, fix local functional issues, and advance the active native release metadata to 5.2.2.

**Changed**
- Updated native download polling so refreshes do not cancel and recreate the active polling task while downloads are still running.
- Disabled the search results "download all" action when no backend groups are available, loading is active, or the backend is unavailable.
- Disabled the batch download action while loading or when the backend is unavailable.
- Bumped active native/backend metadata from 5.2.1 to 5.2.2 in `scripts/build_native_dmg.sh`, `version.json`, `backend/const.py`, and `backend/__init__.py`.

**Reason**
- Download controls should not trigger no-op or unavailable backend actions, and active native release metadata should match the functional fix release.

**Tested**
- `swift test --jobs 1`
- `pytest`
- Bridge smoke test for settings, status, download list, and favorites JSON-lines methods.

**Risks / Notes**
- No UI visual styling was changed.
- Search endpoint verification was not treated as a local blocker because the current VPN environment can prevent access to the upstream site.

### 2026-05-29 — Refresh README and native 5.2.2 release workflow

**Task**
- Rewrite the project README for the current native-first state and prepare the GitHub Actions native release flow for C-Paper Native 5.2.2.

**Changed**
- Rewrote `README.md` around the native macOS product line, current 5.2.2 status, install steps, architecture, development commands, release process, legacy boundary, privacy, and disclaimer.
- Updated `.github/workflows/build.yml` so native DMG builds use release configuration.
- Added a generated detailed native release notes document for tag-triggered GitHub Releases.
- Updated the tag-triggered release title format to `C-Paper Native <version>`.

**Reason**
- The public repository landing page and release notes should match the current native mainline and give users enough install, architecture, and release context.

**Tested**
- `swift test --jobs 1`
- `pytest`
- `git diff --check`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml")'`
- `bash -n scripts/build_native_dmg.sh`

**Risks / Notes**
- The workflow release build will be validated by GitHub Actions after pushing the `v5.2.2` tag.

### 2026-05-29 — Tighten native PDF preview layout

**Task**
- Fix the native 5.2.2 PDF preview layout after the inline preview appeared cramped and visually unbalanced.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` with a compact preview header, icon-only preview actions, a stable PDF content area, and safer PDFView document updates.
- Updated `macos/Sources/CPaperNativeApp/Views/SearchView.swift` and `macos/Sources/CPaperNativeApp/Views/BatchView.swift` so results lists and inline previews fill the available panel height consistently.

**Reason**
- The previous inline preview reused a full-width toolbar inside a narrow side panel, which compressed the file controls and left the PDF area undersized.

**Tested**
- `swift package clean`
- `swift test`

**Risks / Notes**
- Visual behavior was verified by code review and Swift tests; a live native window screenshot was not captured in this session.

### 2026-06-03 — Fix non-maximized native PDF and minimum-height pages for 5.2.3

**Task**
- Fix native PDF preview behavior when the app window is not maximized, keep downloads and batch download usable at minimum window height, and prepare release 5.2.3.

**Changed**
- Added a shared adaptive PDF preview pane layout that keeps search results and batch preview lists side-by-side with the PDF only when both panes fit; otherwise the selected PDF preview uses the available width instead of overflowing.
- Reused the adaptive preview layout in `SearchView.swift` and `BatchView.swift`.
- Added a shared scrollable workflow page scaffold and applied it to the downloads and batch download pages so short windows can scroll instead of clipping content.
- Reduced the PDF document area's minimum height and refreshed PDFKit auto-scaling after layout changes.
- Added Swift tests for the preview pane layout breakpoints.
- Bumped active native/backend release metadata to 5.2.3.

**Reason**
- The previous inline preview required list and PDF panes to fit at the same time, so narrower windows could squeeze or overflow the PDF preview.
- Downloads and batch download pages had fixed vertical expectations that did not degrade well at the minimum window height.

**Tested**
- `swift build --jobs 1`
- `swift test --jobs 1`
- `pytest`
- `bash -n scripts/build_native_dmg.sh`
- `python3 -m py_compile bridge/cpaper_bridge.py backend/*.py`
- `python3 -m json.tool version.json`
- `git diff --check`
- Active release metadata search for stale `5.2.2` and old repository URLs.
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

**Risks / Notes**
- Generated release artifact: `dist/C-Paper-Native-5.2.3-standalone-20260603.dmg`
- SHA-256: `851c5f7ea572c0a01fcd868f011c93711947a42826ff9e1d46d15f99dd80767c`
- Live native window reading was intentionally stopped after the user asked not to continue that inspection path; verification is through code review and automated checks.

### 2026-06-03 — Publish native 5.2.3 to GitHub and correct release notes

**Task**
- Push the native 5.2.3 layout release to GitHub and make the published release notes match the actual fix.

**Changed**
- Pushed `main` commit `4a9134e` and tag `v5.2.3` to GitHub.
- Updated the native GitHub Actions release-note generation so future tag releases read the current `version.json` `release_notes` field instead of hardcoded old bullets.
- Added `.github/release-notes/native-v5.2.3.md` with the corrected native 5.2.3 release body.
- Updated the published GitHub Release `v5.2.3` body to describe the PDF preview and minimum-height page fixes.

**Reason**
- The initial GitHub Release was created successfully, but its body still described the previous 5.2.2 download polling work.

**Tested**
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml")'`
- `gh run watch 26895176342 --repo yimingwu425/C-Paper --exit-status`
- `gh release view v5.2.3 --repo yimingwu425/C-Paper`

**Risks / Notes**
- GitHub Actions reported a Node.js 20 deprecation annotation for upstream actions; the native 5.2.3 release workflow itself completed successfully.

### 2026-06-04 — Add native networking and source providers

**Task**
- Implement the Swift-native Networking and Sources modules for C-Paper 6.0.0 with offline tests.

**Changed**
- Added URLSession-backed networking helpers, request building, proxy configuration, source health checking, provider registry, Frankcie JSON parsing, HTML source provider skeletons, and SwiftSoup-based HTML PDF link extraction.
- Added tests for Frankcie fixture parsing, HTML link extraction, automatic source fallback, and manual no-fallback behavior.

**Reason**
- The native backend needs maintainable source/provider infrastructure before replacing the Python bridge-backed search flow.

**Tested**
- `swift test --jobs 1 --filter SourceRegistryTests`
- `swift test --jobs 1 --filter PaperSourceFixtureTests`

**Risks / Notes**
- HTML providers intentionally start as direct-link skeletons and report unavailable when an entry page does not expose parseable CIE PDF links.
- This work was integrated around concurrently added shared parsing/model files in the same worktree.

### 2026-06-04 — Add native Downloads module

**Task**
- Implement the Swift-native Downloads module and focused tests for C-Paper 6.0.0.

**Changed**
- Added destination building from `NativePaperGroup` / `PaperComponent` direct URLs with folder merge behavior, mark-scheme filtering, duplicate handling, PDF/path safety checks, and task metadata mapping.
- Added a deque-backed download queue, actor-based rate limiter, actor-based circuit breaker, and actor-based download manager with injected writers, cancellation, retry handling, and atomic `.part.<uuid>` replacement.
- Added `DownloadManagerTests` for destination layout, mark-scheme filtering, duplicate skip/missing modes, cancellation, retry, and status statistics.

**Reason**
- The native backend needs Downloads behavior independent of the Python `DownloadEngine` and without reconstructing Frankcie fetch URLs.

**Tested**
- `swift test --jobs 1 --filter DownloadManagerTests`

**Risks / Notes**
- `DownloadQueue` uses `Collections.Deque` through the Swift Collections package added for the 6.0.0 native backend.

### 2026-06-04 — Migrate active app to Swift-native backend for 6.0.0

**Task**
- Implement the C-Paper 6.0.0 native backend plan, remove the active Python bridge dependency, add multi-source support, and update release metadata.

**Changed**
- Added modular Swift backend layers under `macos/Sources/CPaperNativeApp/Backend/` for core service orchestration, data sources, parsing, networking, downloads, and persistence.
- Replaced `AppModel` bridge calls with `NativeBackendService`.
- Added Settings data source selection and updated backend status UI text.
- Added SwiftPM dependencies for SwiftSoup and Swift Collections.
- Archived `bridge/`, `backend/`, root Python `tests/`, and `requirements.txt` under `legacy/python-backend/`.
- Removed active `PythonBridge.swift` and `PythonBridgeTests.swift`.
- Updated native DMG build and GitHub Actions release flow to stop packaging Python bridge resources.
- Updated `README.md`, `AGENTS.md`, `docs/PROJECT_INDEX.md`, `version.json`, and native release notes for 6.0.0.

**Reason**
- The active app should be Swift-native end to end, easier to maintain, faster to package, and able to fall back across multiple third-party paper sources.

**Tested**
- `swift test --jobs 1`

**Risks / Notes**
- PapaCambridge, PastPapers, and EasyPaper providers currently use direct-link HTML extraction skeletons and report unavailable when entry pages do not expose parseable CIE PDF links.
- Live source behavior still needs UI smoke testing and release build verification before publishing 6.0.0.

### 2026-06-04 - Fix native app launch window creation for 6.0.0

**Task**
- Ensure the packaged Swift-native 6.0.0 app reliably creates and foregrounds its main window.

**Changed**
- Added explicit AppKit launch completion and delegate lifetime retention in `main.swift`.
- Extracted `AppDelegate.showMainWindow()` so both lifecycle callback and explicit startup path can create or refocus the single main window.
- Kept the main window ordered front after creation to avoid launch smoke-test false negatives.

**Reason**
- Release smoke testing showed the process could remain alive while accessibility-based window enumeration returned no windows. Runtime diagnostics confirmed the hand-written SwiftPM AppKit entrypoint needed a more explicit startup path.

**Tested**
- Rebuilt the release binary after the startup change.
- Rebuilt the release app bundle and DMG path with `CONFIGURATION=release SKIP_SWIFT_BUILD=1 bash scripts/build_native_dmg.sh`.
- Confirmed the running bundle exposes an on-screen CoreGraphics window named `C-Paper`.

### 2026-06-04 - Replace source skeletons with real provider behavior

**Task**
- Fix 6.0.0 third-party source support after verifying that the earlier non-Frankcie providers were only skeletons and did not match each website's real structure.

**Changed**
- Replaced the generic HTML provider path with independent PapaCambridge, PastPapers, and EasyPaper source implementations.
- Added shared challenge detection for Cloudflare-protected sources.
- Changed automatic fallback order to Frankcie, EasyPaper, PastPapers, then PapaCambridge.
- Implemented EasyPaper's encrypted `dir_v3` API flow and refreshed EasyPaper download tokens immediately before downloading.
- Implemented PastPapers parsing for Next.js/RSC `entries` and best-effort static PDF probing using real CAIE `relPath` URLs.
- Implemented PapaCambridge's CAIE session path, filename extraction, direct upload URL construction, and HEAD verification before returning components.
- Kept PapaCambridge explicit about Cloudflare challenge unavailability instead of returning false success.
- Added fixture and live smoke tests for provider behavior, PastPapers non-seed discovery, PapaCambridge challenge handling, EasyPaper download URL refresh, and live PDF GET verification when a source returns components.
- Updated README, project index, version metadata, and release notes to describe the real source reliability model.
- Tightened native DMG codesign verification by clearing extended attributes again after ad hoc signing and immediately before strict verification.

**Reason**
- PapaCambridge, PastPapers, and EasyPaper do not share the same HTML/path structure. Treating them as generic link pages made manual source selection misleading and automatic fallback unreliable.

**Tested**
- `swift test --jobs 1 --filter PaperSourceFixtureTests`
- `swift test --jobs 1 --filter DownloadManagerTests`
- `swift test --jobs 1 --filter SourceRegistryTests`
- `swift test --jobs 1 --filter LiveSourceTests`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
- `swift test --jobs 1`
- `swift build`
- `bash -n scripts/build_native_dmg.sh`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

**Risks / Notes**
- EasyPaper is the only current non-Frankcie source verified as a stable automatic fallback API in live smoke testing.
- PastPapers static PDF URLs are usable, but directory discovery can be Cloudflare-challenged and static probing is slower.
- PapaCambridge currently uses Cloudflare managed challenge for non-browser clients in live testing; the provider reports unavailable instead of attempting to bypass it.

### 2026-06-04 - Prepare native 6.0.1 source-provider hotfix release

**Task**
- Prepare the verified real-source provider fixes as C-Paper Native 6.0.1 for GitHub publication.

**Changed**
- Bumped native release metadata from 6.0.0 to 6.0.1 in `version.json`, `BackendConstants.swift`, `HTTPRequestBuilder.swift`, `scripts/build_native_dmg.sh`, and `README.md`.
- Added `.github/release-notes/native-v6.0.1.md` for the source-provider hotfix.
- Restored the 6.0.0 release-note file to describe the already-published 6.0.0 release rather than the 6.0.1 hotfix.

**Reason**
- The source-provider fixes should ship as a hotfix release instead of silently changing the already-published 6.0.0 artifact metadata.

**Tested**
- `python3 -m json.tool version.json`
- `bash -n scripts/build_native_dmg.sh`
- `git diff --check`
- `swift test --jobs 1`
- `swift build`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`

### 2026-06-04 - Harden native DMG metadata cleanup for 6.0.1

**Task**
- Remove strict codesign verification warnings seen during the 6.0.1 release DMG build.

**Changed**
- Strengthened bundle metadata cleanup by clearing all extended attributes recursively before deleting known macOS metadata keys.
- Retried strict codesign verification after metadata cleanup so transient Finder/file-provider attributes do not produce a release-build warning.
- Moved the DMG staging workspace to the system temporary directory and verify strict codesign against a clean temporary copy when checking staged bundles.

**Reason**
- The generated app bundle could inherit `com.apple.FinderInfo`, `com.apple.provenance`, or file-provider attributes that make `codesign --verify --deep --strict` complain even after ad hoc signing.
- Running the DMG staging tree inside the repository worktree can inherit file-provider metadata from the user's Documents folder; the final artifact still lands in `dist/`.

**Tested**
- `bash -n scripts/build_native_dmg.sh`
- `python3 -m json.tool version.json`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

### 2026-06-04 - Restore native backend source usability and Python parity

**Task**
- Diagnose why the Swift-native backend could still feel unusable after the 6.0.1 provider hotfix, and close concrete behavior gaps against the archived Python backend.

**Changed**
- Added source-level subject fetching and `SourceRegistry.fetchSubjects()` so automatic mode can populate subjects through EasyPaper/PastPapers when Frankcie's subject API is unavailable.
- Added manual subject-code fallback in Search and Batch views, allowing users to search/download by a 4-digit Cambridge code even when every subject-list provider is temporarily unavailable.
- Moved Frankcie subject parsing into `FrankcieSource` and added directory-name subject parsing for EasyPaper/PastPapers directory formats.
- Connected Swift download history to the active download path: successful downloads now record history, and duplicate `skip`/`missing` modes use history like the archived Python backend.
- Fixed the settings data-source hint so it matches the actual automatic order: Frankcie, EasyPaper, PastPapers, PapaCambridge.
- Strengthened live source smoke tests with subject fallback coverage and short PDF retry logic for transient EasyPaper TLS/handshake failures.

**Reason**
- The old Swift path still loaded subjects only from Frankcie, so fallback sources were unreachable from the UI whenever Frankcie failed before search.
- The Swift download manager had a history store but did not use it to implement duplicate behavior, which diverged from the Python backend.
- Live testing showed EasyPaper can transiently fail a direct PDF request even after search succeeds; production downloads retry, so live verification should reflect that behavior.

**Tested**
- `swift test --jobs 1 --filter 'DownloadManagerTests|SourceRegistryTests|ModelTests|PaperParsingTests'`
- `swift test --jobs 1`
- `swift build`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
- `python3 -m pytest legacy/python-backend/tests`

### 2026-06-04 - Prepare native 6.0.2 backend parity release

**Task**
- Package the Swift-native backend source usability and Python parity fixes as C-Paper Native 6.0.2.

**Changed**
- Bumped native metadata from 6.0.1 to 6.0.2 in `version.json`, `BackendConstants.swift`, `HTTPRequestBuilder.swift`, `scripts/build_native_dmg.sh`, and `README.md`.
- Added `.github/release-notes/native-v6.0.2.md`.
- Updated README release commands and current-version notes for 6.0.2.

**Reason**
- The source usability and duplicate-history parity fixes should ship as a new hotfix release instead of changing the already-published 6.0.1 release.

**Tested**
- `python3 -m json.tool version.json`
- `bash -n scripts/build_native_dmg.sh`
- `git diff --check`
- `swift test --jobs 1`
- `swift build`
- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`
- `python3 -m pytest legacy/python-backend/tests`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

### 2026-06-04 - Add native update checking and simplify backend status UI

**Task**
- Improve the native app settings and startup experience after the Swift backend migration.

**Changed**
- Added glass-styled reusable input/menu controls and updated the subject selector to match the rest of the app chrome.
- Removed Python-bridge-era backend availability badges, banners, button gating, and empty-state copy.
- Added Settings "About" content for author, website, GitHub repository, paper sources, and copyright/disclaimer text.
- Added a native GitHub Release update service with startup checking, user-confirmed DMG download, `.part` temporary files, and Settings update status/actions.
- Added tests for update version comparison, release asset parsing, update download movement, and startup update prompt behavior.
- Updated `docs/PROJECT_INDEX.md` for the new update backend module.

**Reason**
- The Swift-native backend does not have a bridge connection state that users need to monitor.
- Update checking should be available inside the app without mixing app DMGs into the paper download queue.

**Tested**
- `swift test --jobs 1`

### 2026-06-04 - Normalize FrankCIE display name

**Task**
- Correct the user-facing source name spelling from Frankcie to FrankCIE.

**Changed**
- Updated `PaperSourceID.title` and Settings source/about copy to display `FrankCIE`.
- Updated current README and project index source-order text.

**Reason**
- The data source should be presented with the intended capitalization in the app UI.

**Tested**
- `swift test --jobs 1 --filter 'SourceRegistryTests|ModelTests|UpdateServiceTests'`
- `swift test --jobs 1`
- `swift build`

### 2026-06-05 - Split active code files over 300 lines

**Task**
- Break up active Swift and native build script files that exceeded 300 lines.

**Changed**
- Split large SwiftUI views into focused view, panel, control, and shared chrome files.
- Split model DTOs into paper, download, and update model files.
- Split `AppModel` workflow methods into setup, paper/download, and update extensions.
- Moved PastPapers support models/extractor and EasyPaper download URL resolution into dedicated backend helpers.
- Split download tests into destination-builder tests, manager tests, and shared test support.
- Moved native DMG shell helper functions into `scripts/lib/native_dmg_helpers.sh`.
- Updated `docs/PROJECT_INDEX.md` for the new script helper location.

**Reason**
- Keep active code files below the requested 300-line threshold while preserving existing behavior.

**Tested**
- `bash -n scripts/build_native_dmg.sh`
- `bash -n scripts/lib/native_dmg_helpers.sh`
- `git diff --check`
- `swift test --jobs 1`

### 2026-06-05 - Combine 6.0.3 download hotfix with native UI update release

**Task**
- Preserve the GitHub 6.0.3 download retry/circuit-breaker fix while keeping the local subject-control, settings, and update-checking UI improvements.

**Changed**
- Re-added circuit-breaker recovery waiting to the split `DownloadManager` and `CircuitBreaker` code.
- Restored the 6.0.3 download recovery regression tests in the split download test layout.
- Carried the native DMG mount path wait fix into the split script helper layout.
- Unified release metadata, README current-version text, build script version, and release notes around native `6.0.3`.

**Reason**
- The existing GitHub 6.0.3 release fixed download retry behavior, but did not include the newer native UI/settings/update experience.

**Tested**
- `bash -n scripts/build_native_dmg.sh`
- `bash -n scripts/lib/native_dmg_helpers.sh`
- `python3 -m json.tool version.json`
- `git diff --check`
- `swift test --jobs 1`
- `swift build`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`

### 2026-06-06 - Add swarm-ready professionalization plan

**Task**
- Create a dependency-aware implementation plan for the full-repository C-Paper professionalization and maintenance cleanup effort.

**Changed**
- Added `cpaper-professionalization-plan.md` with explicit task dependencies, parallel execution waves, validation criteria, risks, and execution constraints.
- Incorporated review feedback to remove dependency/wave conflicts, clarify dirty-worktree cleanup limits, split documentation tasks, and make CI/quality gate ordering explicit.

**Reason**
- The repository needs a staged plan before implementing cleanup, stability fixes, CI hardening, release governance, and professional polish.

**Tested**
- Read-only plan structure review with `rg`.
- Subagent plan review for dependency ordering, parallelization conflicts, and missing edge cases.

### 2026-06-06 - Clean workspace pollution baseline

**Task**
- Complete `T0.1` from `cpaper-professionalization-plan.md`.

**Changed**
- Removed byte-identical Finder-style duplicate `* 2.*` files after comparing each source/doc/script duplicate to its canonical counterpart.
- Removed ignored generated outputs and `.DS_Store` files.
- Added `.codex/` as an explicit local ignore.
- Updated the professionalization plan with completion status and validation evidence.

**Reason**
- The repository must be free of duplicate Swift source files and generated pollution before restoring the parsing baseline.

**Tested**
- `find . -name '* 2.*' -print`
- `find . -name '.DS_Store' -print`
- `git status --short`
- Generated output existence check for `build/`, `dist/`, `.build/`, `scripts/dist/`, `.pytest_cache/`, and `.git/objects/maintenance 2.lock`

### 2026-06-06 — Restore paper filename parser baseline

**Task**
- Restore the missing active Swift parser file so parsing tests compile and pass again.

**Changed**
- Restored `macos/Sources/CPaperNativeApp/Backend/Parsing/PaperFilenameParser.swift` from the latest git-tracked version.
- Updated `cpaper-professionalization-plan.md` to mark T0.2 completed and record RED/GREEN evidence.

**Reason**
- The active source tree was missing `PaperFilenameParser.swift`, which broke parsing-related compilation across current sources and tests.

**Tested**
- RED: `swift test --jobs 1 --filter PaperParsingTests` failed to compile because `PaperFilenameParser` and `ParsedPaperFilename` were missing.
- GREEN: `swift test --jobs 1 --filter PaperParsingTests`

**Risks / Notes**
- No parser behavior was expanded; the file was restored to the current git-tracked contract used by active call sites and tests.

### 2026-06-06 — Record deterministic Swift baseline

**Task**
- Complete `T0.4` from `cpaper-professionalization-plan.md` by recording the post-cleanup deterministic Swift test baseline without changing product code.

**Changed**
- Updated `cpaper-professionalization-plan.md` to mark `T0.4` completed and record `reason_not_testable` plus baseline evidence.
- Appended this baseline entry to `docs/WORK_LOG.md`.

**Reason**
- Wave 1 work needs the true current repository state captured after cleanup and parser restoration, before any feature fixes begin.

**Tested**
- `swift test --jobs 1`
- Exit status: `0`
- Output summary: build completed, all suites passed, `58` tests executed, `4` skipped, `0` failures.

**Risks / Notes**
- `reason_not_testable`: this was a baseline measurement task rather than a code-fix/TDD task, so no new RED/GREEN test was introduced.
- The four skipped tests are the existing live-source checks gated by `RUN_LIVE_SOURCE_TESTS=1`.

### 2026-06-06 — Centralize native version metadata

**Task**
- Complete `T2.1` from `cpaper-professionalization-plan.md` by making `version.json` the native version single source of truth and adding a drift check.

**Changed**
- Added `scripts/check_version_drift.sh` to validate `version.json`, Swift version constants, User-Agent reuse, DMG build-script version loading, and the README current-version display.
- Added `scripts/lib/version_helpers.sh` so shell scripts can read `version.json` without duplicating JSON parsing.
- Updated `scripts/build_native_dmg.sh` to load `VERSION` from `version.json` before deriving bundle and DMG artifact metadata.
- Updated `BackendConstants.swift` so the native User-Agent derives from `BackendConstants.version`, and updated `HTTPRequestBuilder.swift` to reuse that shared User-Agent.
- Reduced README hardcoded release-version duplication by keeping the current-version display explicit and making tag command examples version-agnostic.

**Reason**
- Native version metadata had drift-prone duplicates across Swift constants, the HTTP layer, release packaging, and documentation.

**Tested**
- RED: `bash scripts/check_version_drift.sh`
- RED controlled mismatch: `bash scripts/check_version_drift.sh --backend-constants <temporary BackendConstants.swift copy with version changed to 9.9.9>`
- GREEN: `bash scripts/check_version_drift.sh`
- `bash -n scripts/build_native_dmg.sh`
- `python3 -m json.tool version.json`
- `swift build --product CPaperNative`
- Attempted: `swift test --jobs 1 --filter UpdateServiceTests`

**Risks / Notes**
- `swift test --jobs 1 --filter UpdateServiceTests` is currently blocked by pre-existing compile errors in `macos/Tests/CPaperNativeTests/StartupBootCoordinatorTests.swift` from parallel T1.1 work (`cannot find 'AppBootCoordinator' in scope`), so T2.1 validation used drift/build checks plus an app-target build instead of a passing focused test run.

### 2026-06-06 — Make settings cancel revert drafts

**Task**
- Complete `T1.5` from `cpaper-professionalization-plan.md` so Settings edits happen on a draft copy, Save commits and persists, and Cancel closes without mutating live app state.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsView.swift` to initialize a local `draftSettings` copy, bind editable sections to that draft, and commit only on Save.
- Updated `macos/Sources/CPaperNativeApp/Views/SettingsFormSections.swift` so save directory, source, proxy, and download controls edit `Binding<DownloadSettings>` instead of mutating `model.settings` directly.
- Updated `macos/Sources/CPaperNativeApp/State/AppModel+Setup.swift` with `saveSettings(_:)`, plus draft-friendly save-directory and proxy helper flows.
- Added focused draft rollback / save-persistence coverage in `macos/Tests/CPaperNativeTests/ModelTests.swift`.
- Updated `cpaper-professionalization-plan.md` to mark `T1.5` completed and record validation evidence.

**Reason**
- The Settings sheet previously bound controls directly to `model.settings`, so tapping Cancel left edited values in live memory even without saving.

**Tested**
- RED: `swift test --jobs 1 --filter ModelTests`
- GREEN: `swift build --product CPaperNative`
- GREEN: temporary built-module harness covering the two new draft scenarios, output `settings-draft-check: ok`
- Static check: confirmed `SettingsView.swift` browse action only updates `draftSettings.saveDirectory`, Cancel still only dismisses, and proxy testing uses the draft proxy URL while only mutating local `proxyStatus`

**Risks / Notes**
- The focused SwiftPM test run is currently blocked after the T1.5 fix by concurrent untracked `macos/Tests/CPaperNativeTests/StartupBootCoordinatorTests.swift` from parallel T1.1 work (`cannot find 'AppBootCoordinator' in scope`), so final behavior validation used the built app target plus a temporary compiled harness against the real `CPaperNativeApp` module.

### 2026-06-06 — Make startup initialization recoverable

**Task**
- Complete `T1.1` from `cpaper-professionalization-plan.md` by replacing eager crashing startup with a recoverable boot state.

**Changed**
- Added `AppBootCoordinator` with loading, ready, and failed phases, retry handling, and stale-attempt protection.
- Changed `AppModel` to require an injected backend and added `AppModel.live()` for fallible live initialization.
- Updated `RootView` to render startup loading and failure states before showing the ready app shell.
- Added `StartupBootCoordinatorTests` for initialization failure recovery and overlapping retry idempotency.
- Updated `cpaper-professionalization-plan.md` to mark `T1.1` completed.

**Reason**
- `AppModel` previously used `try! NativeBackendService()`, so startup storage or migration failures could crash the app before the UI could show a recoverable error.

**Tested**
- RED: parallel T1.1 test phase produced a compile failure for `StartupBootCoordinatorTests` while `AppBootCoordinator` was missing from the target.
- GREEN: `swift test --jobs 1 --filter StartupBootCoordinatorTests`
- GREEN: `swift test --jobs 1`

### 2026-06-06 — Refresh architecture boundary documentation

**Task**
- Complete `T3.1` from `cpaper-professionalization-plan.md` by making the contributor-facing architecture docs consistently native-first and legacy-bounded.

**Changed**
- Updated `README.md` to identify the active source, active tests, active script/support directories, external project-site status, and archived legacy paths without mixing in release-flow steps.
- Updated `docs/PROJECT_INDEX.md` to keep the repo map focused on the active native target, Swift tests, build-script locations, and legacy boundaries.
- Updated `MAINTENANCE_BASELINE.md` to describe only the current native maintenance boundary and the default `swift test --jobs 1` validation command.
- Updated `native/CPaperNative/README.md` so the moved-project note points contributors to the root package, `macos/`, active tests, and active script directories.

**Reason**
- The boundary docs still mixed native architecture guidance with release-flow details and older directory assumptions, which made it harder for a new contributor to identify the active implementation quickly.

**Tested**
- `reason_not_testable`: this task is a documentation-boundary refresh, so no meaningful RED/GREEN runtime test applies.
- `rg -n "Package\\.swift|macos/Tests/CPaperNativeTests|scripts/lib|swift test --jobs 1|legacy/python-backend|legacy/pywebview|site/" README.md docs/PROJECT_INDEX.md MAINTENANCE_BASELINE.md native/CPaperNative/README.md`
- `rg -n "Build Native macOS|workflow|GitHub Actions|site/.*active|active app directory|main implementation under legacy|legacy is active" README.md docs/PROJECT_INDEX.md MAINTENANCE_BASELINE.md native/CPaperNative/README.md`

**Risks / Notes**
- The second `rg` still matches the unchanged README workflow badge link, but the refreshed architecture sections no longer describe release flow or suggest that legacy/site paths are part of the active app tree.

### 2026-06-06 — Add lightweight quality gates

**Task**
- Complete `T2.4` from `cpaper-professionalization-plan.md` by adding lightweight check-only Swift quality gates and a repo hygiene scan without mass-formatting existing code.

**Changed**
- Added `.swiftlint.yml` with a small active-tree-only rule set covering `Package.swift`, `macos/Sources`, and `macos/Tests`.
- Added `.swiftformat` with a minimal Swift 6 lint configuration and exclusions for legacy and generated directories.
- Added `scripts/check_swift_quality.sh` to run SwiftLint and SwiftFormat in check-only mode when those binaries are installed, and otherwise skip with explicit messages.
- Added `scripts/check_repo_hygiene.sh` to fail on `.DS_Store`, Finder duplicate `* 2.*` files, and related metadata pollution while pruning generated/cache directories.
- Updated `cpaper-professionalization-plan.md` to mark `T2.4` completed and record the validation evidence.

**Reason**
- The repo needed lightweight local validation entrypoints for style and hygiene before CI wiring, without introducing a mass-formatting diff or a new package dependency.

**Tested**
- RED: `bash scripts/check_repo_hygiene.sh --root <temporary fixture containing .DS_Store and subdir/Notes 2.md>`
- GREEN: `bash scripts/check_repo_hygiene.sh`
- `bash scripts/check_swift_quality.sh`
- `bash -n scripts/check_repo_hygiene.sh`
- `bash -n scripts/check_swift_quality.sh`
- `git diff --check`

**Risks / Notes**
- `swiftlint` and `swiftformat` are not installed in the current environment, so `scripts/check_swift_quality.sh` currently prints explicit skip messages instead of running those tools; T2.2 can still wire the script into CI as-is because it already handles both installed and unavailable-tool states.

### 2026-06-06 — Add shared file transfer layer

**Task**
- Complete `T1.2` from `cpaper-professionalization-plan.md` by adding a shared HTTP file transfer client for future download/update reuse.

**Changed**
- Added `macos/Sources/CPaperNativeApp/Backend/Networking/HTTPFileTransferClient.swift`.
- Reused `HTTPRequestBuilder` for GET request construction and `ProxyConfiguration` for proxy-aware `URLSession` setup.
- Reused `NetworkClientError` plus shared `NetworkClient.validate(_:)` HTTP status validation for non-2xx handling.
- Implemented chunked file writes, progress callbacks, and destination cleanup on failure or cancellation.
- Added `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift` covering successful transfer, non-2xx response, proxy configuration, progress reporting, cancellation, and partial-file cleanup.
- Updated `cpaper-professionalization-plan.md` to mark `T1.2` completed.

**Reason**
- Download and update flows both need the same proxy, request-header, status-validation, file-write, and cleanup behavior, and that logic should live in one narrow reusable module before later migration tasks.

**Tested**
- RED: `swift test --jobs 1 --filter HTTPFileTransferClientTests`
- GREEN: `swift test --jobs 1 --filter HTTPFileTransferClientTests`
- GREEN: `swift test --jobs 1`

**Risks / Notes**
- This task intentionally did not migrate `DownloadManager` or `UpdateService` to the new client yet; those call-site integrations remain for later plan tasks.

### 2026-06-06 — Split native CI into validate, package, and release jobs

**Task**
- Complete `T2.2` from `cpaper-professionalization-plan.md` by refactoring the native GitHub Actions workflow into separate validate, package, and release jobs with native-only path ownership.

**Changed**
- Updated `.github/workflows/build.yml` to add a `validate` job for pull requests and native-relevant pushes, covering shell syntax, JSON metadata parsing, workflow YAML parsing, version drift, repo hygiene, Swift quality checks, and `swift test --jobs 1`.
- Split DMG build, mount/verify, and artifact upload into a `package` job gated by `needs: validate`.
- Split GitHub release publication into a `release` job gated by `needs: package`, added artifact download there, and kept the existing release notes generation flow.
- Added workflow-level `concurrency` and removed `legacy/python-backend/**` from the native workflow path triggers.

**Reason**
- The native CI path was still a single build-and-release job with legacy Python trigger overlap, so validation, packaging, and tag publishing were not separated cleanly.

**Tested**
- `reason_not_testable`: this is CI/workflow wiring, so verification used static parsing/graph checks and the concrete validate commands rather than a RED/GREEN unit test.
- `python3 - <<'PY' ... yaml.load(..., Loader=yaml.BaseLoader) ... PY` asserting `package -> validate`, `release -> package`, tag-only release gating, no `legacy/python-backend/**` native trigger, and workflow `concurrency`
- `python3 - <<'PY' ... for path in .github/workflows/*.yml: yaml.load(..., Loader=yaml.BaseLoader) ... PY`
- `python3 -m json.tool version.json`
- `bash scripts/check_version_drift.sh`
- `bash scripts/check_repo_hygiene.sh`
- `bash scripts/check_swift_quality.sh`
- `swift test --jobs 1`
- `git diff --check`

**Risks / Notes**
- `package` still runs on `workflow_dispatch` in addition to `push` because the previous native workflow already exposed manual dispatch, while `release` remains tag-only.

### 2026-06-06 — Isolate download sessions and stream default transfers

**Task**
- Complete `T1.3` from `cpaper-professionalization-plan.md` by isolating overlapping download runs and routing default downloads through the shared transfer layer with proxy support.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadManager.swift` to invalidate stale runs with a run id, keep rate limiter/circuit breaker instances per run, block late stale completions before atomic replace/history recording, and route the default writer through `HTTPFileTransferClient`.
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` and `macos/Sources/CPaperNativeApp/State/AppModel+PaperWorkflow.swift` so the app passes `settings.proxyURL` into download startup.
- Expanded `macos/Tests/CPaperNativeTests/DownloadManagerTests.swift` and `macos/Tests/CPaperNativeTests/DownloadTestSupport.swift` with regression coverage for start-while-running, cancel-then-start, late stale completion isolation, EasyPaper token refresh on the shared-transfer path, and proxy propagation through the backend start API.
- Updated `cpaper-professionalization-plan.md` to mark `T1.3` completed.

**Reason**
- Without run/session isolation, cancelled or superseded workers could finish late and mutate the latest in-memory download state; the remaining default download path also still bypassed the shared chunked transfer client and its proxy-aware streaming behavior.

**Tested**
- RED: `swift test --jobs 1 --filter DownloadManagerTests`
- GREEN: `swift test --jobs 1 --filter DownloadManagerTests`
- GREEN: `swift test --jobs 1`

**Risks / Notes**
- This task isolates download runs and default file transfer only; PDF preview and update-download migration onto the shared transfer client remain owned by later tasks.

### 2026-06-06 — Prepare optional native signing and notarization path

**Task**
- Complete `T2.3` from `cpaper-professionalization-plan.md` by keeping ad hoc signing as the default native packaging path while adding an optional Developer ID signing + notarization route that activates only when the expected CI secrets are present.

**Changed**
- Updated `scripts/lib/native_dmg_helpers.sh` with signing-mode detection, Developer ID signing via `CPAPER_CODESIGN_IDENTITY`, ad hoc fallback when no identity is configured, and optional DMG notarization/stapling via `CPAPER_NOTARY_KEYCHAIN_PROFILE`.
- Updated `scripts/build_native_dmg.sh` to report the active signing mode, sign the app bundle through the shared helper before DMG packaging, and notarize/staple the final DMG only after it has been created.
- Updated `.github/workflows/build.yml` so the `package` job documents the exact optional secret names, conditionally imports a Developer ID certificate into a temporary keychain, stores a `notarytool` profile, and exports signing env vars only when all signing/notarization secrets are present.
- Added a concise README note documenting the default ad hoc behavior, local env vars, and optional GitHub Actions secret names for the secret-backed release path.

**Reason**
- The native release path needed a real place for Developer ID signing and notarization without making local builds or no-secret CI runs depend on Apple credentials.

**Tested**
- `reason_not_testable`: this is release-script and workflow wiring, so verification used static and dry-path checks instead of live Apple credential execution.
- `bash -n scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`
- `python3 - <<'PY' ... yaml.load(..., Loader=yaml.BaseLoader) ... PY` parsing `.github/workflows/build.yml`
- `python3 - <<'PY' ... assert secret names in package configure-step gate ... PY`
- `python3 - <<'PY' ... assert 'codesign' < 'xcrun notarytool submit' < 'xcrun stapler staple' ... PY`
- `bash -lc 'unset CPAPER_CODESIGN_IDENTITY CPAPER_NOTARY_KEYCHAIN_PROFILE; source scripts/lib/native_dmg_helpers.sh; test "$(current_signing_mode)" = "ad hoc"; ! notarization_configured; echo no-secret-path-ok'`
- `git diff --check`

**Risks / Notes**
- The workflow now has a documented optional path, but the actual secret values and Apple account material still need to be provisioned in GitHub before a notarized release can run end to end.

### 2026-06-06 — Route preview and update downloads through shared transfer

**Task**
- Complete `T1.4` from `cpaper-professionalization-plan.md` by moving PDF preview caching and update downloads onto the shared transfer path while preserving preview local-file reuse and update `.part` atomic replacement behavior.

**Changed**
- Updated `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift` to add `previewURL(for:settings:)`, which first reuses already-downloaded local files, then reuses cache hits under the native cache directory, and finally downloads preview PDFs through `HTTPFileTransferClient` with the current proxy setting.
- Updated `macos/Sources/CPaperNativeApp/Backend/Downloads/DownloadSourceURLResolver.swift` so preview and download code can both resolve refreshed EasyPaper download URLs from either `PaperComponent` or `PaperFile`.
- Updated `macos/Sources/CPaperNativeApp/Views/PDFPreviewView.swift` to remove direct `URLSession.shared.download` usage and rely on the backend preview path instead.
- Updated `macos/Sources/CPaperNativeApp/Backend/Updates/UpdateService.swift` so the default update download path uses `HTTPFileTransferClient`, keeps `.part` staging plus atomic replace/move, and removes leftover partials when transfer fails.
- Added `macos/Tests/CPaperNativeTests/NativeBackendServicePreviewTests.swift` to cover local preview reuse plus EasyPaper/proxy/cache behavior.
- Expanded `macos/Tests/CPaperNativeTests/UpdateServiceTests.swift` to cover chunked shared-transfer success, non-2xx failure, partial cleanup, and replacement of an existing final DMG.
- Added `macos/Tests/CPaperNativeTests/TransferTestSupport.swift` and reused it from `macos/Tests/CPaperNativeTests/HTTPFileTransferClientTests.swift` for shared mock transfer plumbing.
- Updated `cpaper-professionalization-plan.md` to mark `T1.4` completed.

**Reason**
- Preview and update downloads still bypassed the shared proxy-aware transfer layer added in earlier tasks, which meant EasyPaper preview resolution, proxy behavior, chunked writes, and cleanup semantics were inconsistent across download surfaces.

**Tested**
- RED: `swift test --jobs 1 --filter UpdateServiceTests`
- RED: `swift test --jobs 1 --filter NativeBackendServicePreviewTests`
- GREEN: `swift test --jobs 1 --filter UpdateServiceTests`
- GREEN: `swift test --jobs 1 --filter NativeBackendServicePreviewTests`
- GREEN: `swift test --jobs 1`

**Risks / Notes**
- Preview cache keys still use the remote filename, matching the previous UI-side temp-cache behavior; if future sources can serve distinct preview documents under the same filename across hosts, T1.6 is the right place to revisit cache-keying without widening this task.

### 2026-06-06 — Freeze legacy archive boundary

**Task**
- Complete `T3.2` from `cpaper-professionalization-plan.md` by making the legacy area clearly archival and keeping the final legacy release workflow understandable.

**Changed**
- Added `legacy/README.md` describing `legacy/` as archival, pointing active maintenance to root `Package.swift` + `macos/`, and documenting that legacy-only changes should not trigger the native workflow.
- Updated `.github/workflows/legacy-release.yml` with final archived legacy release naming, run name, job names, and comments tying it to the final 5.2.1 pywebview release path.
- Updated `.github/workflows/build.yml` comments to make the native-owned path filter boundary explicit.
- Tightened `.github/release-notes/legacy-v5.2.1.md` wording so the final legacy release cannot be mistaken for part of the active native product line.
- Updated `cpaper-professionalization-plan.md` to mark `T3.2` completed.

**Reason**
- Legacy code and its final release workflow should remain understandable for archival/reproducibility purposes without implying that Python/pywebview is still part of the active native app or routine native CI path.

**Tested**
- `reason_not_testable`: this is documentation and workflow-boundary work, so no meaningful RED/GREEN runtime test applies.
- `ruby - <<'RUBY' ... YAML.load_file(...) ... RUBY` parsing `.github/workflows/build.yml` and `.github/workflows/legacy-release.yml`.
- `ruby - <<'RUBY' ... assert path filters exclude legacy/ and archival terms exist ... RUBY`.
- `git diff --check`.

**Risks / Notes**
- Python dependency locking was intentionally not added because the legacy workflow only runs manually or from `v*-legacy` tags, not from ordinary legacy file changes.

### 2026-06-06 — Clean transfer-related backend facade glue

**Task**
- Complete `T1.6` from `cpaper-professionalization-plan.md` by removing temporary preview-transfer glue and duplicate downloaded-file lookup logic from `NativeBackendService`.

**Changed**
- Added `macos/Sources/CPaperNativeApp/Backend/Downloads/PreviewFileService.swift` to own preview local-file reuse, cache location, EasyPaper source URL resolution, shared-transfer preview download, and proxy forwarding.
- Added `DownloadDestinationBuilder.existingDownloadURL(for:saveDirectory:fileManager:)` so preview and download destination rules share the same merged/split file-location helper.
- Reduced `NativeBackendService.previewURL(for:settings:)` to a narrow facade method that delegates to `PreviewFileService`.
- Added `DownloadDestinationBuilderTests` coverage for finding already-downloaded files in both merged and split destination layouts.
- Updated `cpaper-professionalization-plan.md` to mark `T1.6` completed.

**Reason**
- After downloads, preview, and updates moved onto the shared transfer path, `NativeBackendService` still contained preview-specific transfer wiring and local file lookup details that belonged in smaller backend support modules.

**Tested**
- RED: `swift test --jobs 1 --filter DownloadDestinationBuilderTests/testExistingDownloadURLFindsMergedAndSplitDestinations`
- GREEN: `swift test --jobs 1 --filter DownloadDestinationBuilderTests/testExistingDownloadURLFindsMergedAndSplitDestinations`
- GREEN: `swift test --jobs 1 --filter NativeBackendServicePreviewTests`
- GREEN: `swift test --jobs 1 --filter DownloadManagerTests`
- GREEN: `swift test --jobs 1 --filter UpdateServiceTests`
- GREEN: `swift test --jobs 1 --filter ModelTests`
- GREEN: `swift test --jobs 1`
- Static cleanup: `rg -n "PreviewTransferWriter|localDownloadedFileURL|defaultPreviewTransfer|URLSession\\.shared\\.download|data\\(from:" macos/Sources/CPaperNativeApp/Backend macos/Sources/CPaperNativeApp/Views`
- `git diff --check`

**Risks / Notes**
- Preview cache filenames still intentionally match the existing filename-based behavior from T1.4; this task only moved ownership out of the facade.

### 2026-06-06 — Refresh release and validation documentation

**Task**
- Complete `T3.3` from `cpaper-professionalization-plan.md` by updating release, validation, install, signing/notarization, privacy/disclaimer, and data-source reliability documentation.

**Changed**
- Updated `README.md` with the current native `validate/package/release` flow, tag-only release behavior, manual `workflow_dispatch` packaging behavior, install notes, ad hoc default signing, optional Developer ID/notary setup, external-link pending project-site wording, and data-source reliability boundaries.
- Added `docs/RELEASE_AND_VALIDATION.md` as the focused native release and validation reference.
- Updated `docs/PROJECT_INDEX.md` to index the release/validation guide and summarize the active workflow behavior.
- Updated `.github/release-notes/native-v6.0.3.md` with current release/install/signing/privacy/source-reliability notes.
- Updated `cpaper-professionalization-plan.md` to mark `T3.3` completed.

**Reason**
- CI and optional signing/notarization behavior had stabilized, but public docs still needed to describe the actual validation, packaging, release, install, privacy/disclaimer, and data-source reliability boundaries.

**Tested**
- `reason_not_testable`: this is a documentation-only task with no meaningful RED/GREEN runtime test.
- Ruby parsed `.github/workflows/build.yml` and asserted `package -> validate`, `release -> package`, package gating for `workflow_dispatch`/`push`, and tag-only release gating.
- Ruby static doc consistency check confirmed public docs include the required release terms and do not contradict workflow behavior.
- `rg -n "validate/package/release|tag-only|workflow_dispatch|ad hoc|Developer ID/notary|external-link pending|privacy/disclaimer/data source reliability" README.md docs/PROJECT_INDEX.md docs/RELEASE_AND_VALIDATION.md .github/release-notes/native-v6.0.3.md`
- `git diff --check`

**Risks / Notes**
- Unrelated in-progress `macos/` support/diagnostics files were present in the worktree during this task and were intentionally not edited, reverted, staged, or committed.

### 2026-06-06 — Add support diagnostics and redacted failure reports

**Task**
- Complete `T4.1` from `cpaper-professionalization-plan.md` by adding user-facing diagnostics for startup, source-provider, download, preview, and update failures.

**Changed**
- Added `SupportDiagnostic` and `SupportDiagnosticsStore` to redact sensitive context and write `Support/latest-diagnostic.txt` under app support.
- Exposed the support directory path and diagnostic writer through `NativeBackendService`.
- Updated `AppModel` to record the latest diagnostic, copy it to the pasteboard, and reveal the support directory.
- Wired source-provider warnings/failures, download failures, preview failures, update failures, and startup initialization failures into redacted support diagnostics.
- Added copy/reveal actions to the global error alert, startup failure view, downloads view, and settings support section.
- Added tests for proxy credential redaction, EasyPaper token/query secret redaction, home-path redaction, support report file writing, and app error diagnostic creation.
- Updated `cpaper-professionalization-plan.md` to mark `T4.1` completed.

**Reason**
- Failures were previously surfaced as short strings in alerts or local panels, which made support harder and risked copying raw URLs, proxy credentials, or private paths into bug reports.

**Tested**
- RED: `swift test --jobs 1 --filter SupportDiagnosticsTests`
- GREEN: `swift test --jobs 1 --filter SupportDiagnosticsTests`
- GREEN: `swift test --jobs 1 --filter ModelTests/testBackendErrorsCreateRedactedSupportDiagnosticReport`
- GREEN: `swift test --jobs 1 --filter StartupBootCoordinatorTests`
- GREEN: `swift test --jobs 1`
- `git diff --check`

**Risks / Notes**
- The support report currently stores the latest diagnostic only. That keeps local data small and avoids creating a long-lived log history.

### 2026-06-06 — Polish native UI states and support wording

**Task**
- Complete `T4.2` from `cpaper-professionalization-plan.md` with a focused product polish pass over state language, accessibility, settings copy, and visual restraint.

**Changed**
- Added cancelled and skipped download counts to `AppModel` and the downloads summary.
- Updated the downloads queue to show cancelled/skipped context, clearer queue summary text, and accessible progress labels/values.
- Added accessibility labels to startup, search, preview caching, status, and update progress indicators.
- Added a visible privacy row in Settings that explains local-only settings/history/diagnostics and redaction behavior.
- Clarified DMG install guidance in the update settings section.
- Removed local decorative light blobs from search, batch, and download summary surfaces while keeping the shared `ProductBackdrop` glass system.
- Expanded `ModelTests.testDownloadCounts` for cancelled/skipped counts.
- Updated `cpaper-professionalization-plan.md` to mark `T4.2` completed.

**Reason**
- The app already had the main workflows in place, but cancellation/skipped states, accessibility text, privacy/disclaimer visibility, and visual restraint needed a final product-quality pass.

**Tested**
- `reason_not_testable`: this is a UI/product polish pass, so validation is compilation, existing behavior tests, and static UI checks.
- `swift test --jobs 1`
- `rg -n "blur\\(radius|隐私|accessibilityLabel|已取消|已跳过|DMG 下载完成" macos/Sources/CPaperNativeApp/Views macos/Sources/CPaperNativeApp/State macos/Tests/CPaperNativeTests/ModelTests.swift`
- `git diff --check`

**Risks / Notes**
- The remaining large blur usage is the existing shared `ProductBackdrop`, not newly added panel decoration.

### 2026-06-06 — Normalize shared transfer cancellation errors

**Task**
- Fix a cancellation edge case found during `T5` final verification.

**Changed**
- Updated `HTTPFileTransferClient.transfer` to map URLSession `NSURLErrorCancelled` / task cancellation into `CancellationError` while preserving cleanup of partial destination files.

**Reason**
- Full-suite verification exposed a flaky mismatch where cancellation sometimes surfaced as `NSURLErrorCancelled` instead of Swift `CancellationError`, even though the behavior was a cancelled transfer.

**Tested**
- FAIL: `swift test --jobs 1` failed in `HTTPFileTransferClientTests.testTransferRemovesPartialFileWhenCancelled` with `NSURLErrorDomain Code=-999`.
- GREEN: `swift test --jobs 1 --filter HTTPFileTransferClientTests`
- GREEN: `swift test --jobs 1 --filter HTTPFileTransferClientTests/testTransferRemovesPartialFileWhenCancelled`

**Risks / Notes**
- Only cancellation errors are normalized; non-cancellation transfer failures still propagate unchanged.

### 2026-06-06 — Retry native codesign after metadata cleanup

**Task**
- Harden the release packaging path after `T5` release build surfaced local Finder metadata interfering with ad hoc signing.

**Changed**
- Updated `scripts/lib/native_dmg_helpers.sh` so `sign_app_bundle` clears bundle metadata inside the signing function and retries codesign once after cleanup for both Developer ID and ad hoc signing paths.

**Reason**
- The release build succeeded, but local Finder/file-provider metadata made the first ad hoc signing attempt fail with `resource fork, Finder information, or similar detritus not allowed`, causing the script to continue with an unsigned app bundle.

**Tested**
- FAIL evidence: `CONFIGURATION=release bash scripts/build_native_dmg.sh` produced the DMG but logged `ad hoc codesign failed ... continuing with unsigned bundle`.
- Manual confirmation: after clearing Finder/file-provider metadata, `codesign --force --deep --sign - dist/CPaperNative.app` succeeded.
- GREEN: `bash -n scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`
- GREEN: `CONFIGURATION=release bash scripts/build_native_dmg.sh` completed with clean ad hoc signing output and produced `dist/C-Paper-Native-6.0.3-standalone-20260606.dmg`.
- GREEN: `hdiutil verify dist/C-Paper-Native-6.0.3-standalone-20260606.dmg`
- GREEN: mounted the DMG and verified `CPaperNative.app`, `Applications` symlink, `.background/background.png`, and `codesign --verify --deep --strict` on the mounted app.

**Risks / Notes**
- This keeps no-secret builds on the ad hoc path and does not require Apple signing credentials.

### 2026-06-06 — Final verification and release readiness audit

**Task**
- Complete `T5` from `cpaper-professionalization-plan.md` with deterministic tests, static checks, release packaging, and DMG verification.

**Changed**
- Updated `cpaper-professionalization-plan.md` to mark `T5` completed and record final verification evidence.

**Reason**
- The full professionalization plan needed a final audit proving the repository, native app, CI/release docs, and packaging path are in a coherent release-ready state.

**Tested**
- `swift test --jobs 1`: final run passed with 78 tests, 4 skipped, and 0 failures.
- `bash -n scripts/build_native_dmg.sh scripts/lib/native_dmg_helpers.sh`
- `python3 -m json.tool version.json`
- Ruby YAML parse for `.github/workflows/build.yml` and `.github/workflows/legacy-release.yml`
- `bash scripts/check_version_drift.sh`
- `bash scripts/check_repo_hygiene.sh`
- `bash scripts/check_swift_quality.sh` (SwiftLint/SwiftFormat skipped because the binaries are not installed locally)
- `git diff --check`
- `CONFIGURATION=release bash scripts/build_native_dmg.sh`
- `hdiutil verify dist/C-Paper-Native-6.0.3-standalone-20260606.dmg`
- Mounted DMG verification for `CPaperNative.app`, `Applications` symlink, `.background/background.png`, and `codesign --verify --deep --strict` on the mounted app.

**Risks / Notes**
- Live third-party source tests remain opt-in with `RUN_LIVE_SOURCE_TESTS=1` because upstream sites are intentionally treated as unstable external dependencies.

### 2026-06-08 — Scope Swift quality gate to changed files in CI

**Task**
- Unblock the native `validate` GitHub Actions job for the `6.0.5` release after `Check Swift quality` started failing on repository-wide historical SwiftFormat drift.

**Changed**
- Updated `scripts/check_swift_quality.sh` so SwiftLint and SwiftFormat run only on changed active-tree Swift files plus `Package.swift`, instead of linting the full native tree on every CI run.
- Updated `.github/workflows/build.yml` to checkout full git history for `validate` and pass the pull request or push compare range into the Swift quality script.

**Reason**
- The original gate contradicted the earlier lightweight-quality goal by failing the release on long-standing formatting debt unrelated to the current release changes.

**Tested**
- `bash -n scripts/check_swift_quality.sh`
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "ok"'`
- manual script inspection against the failing release diff (`95da3a1^..cb80b31`) to confirm only changed native Swift files are selected

**Risks / Notes**
- This keeps the CI gate focused on newly changed Swift files. A future dedicated formatting cleanup can still run `swiftformat` across the full active tree separately.

### 2026-06-08 — Fix XCTest teardown concurrency compatibility on CI

**Task**
- Unblock the native `validate` job after GitHub Actions started failing `swift test --jobs 1` with a Swift 6/XCTest sendability diagnostic in `AppMenuCommandCenterTests`.

**Changed**
- Changed `AppMenuCommandCenterTests.tearDown()` from async to synchronous because the cleanup is purely synchronous and does not need `await super.tearDown()`.

**Reason**
- GitHub Actions compiled the async `tearDown()` under a stricter XCTest concurrency diagnostic and rejected sending the main-actor-isolated test case into nonisolated `super.tearDown()`.

**Tested**
- `swift test --jobs 1`
- `git diff --check`

**Risks / Notes**
- This change is test-only and keeps the same cleanup behavior while avoiding the runner-specific sendability error.

### 2026-06-24 — Add structured Code Wiki documentation for the native project

**Task**
- Generate a structured, complete Code Wiki (markdown) describing the project architecture, main module responsibilities, key classes and functions, dependencies, and how to run / build / release C-Paper, focused on the active native (Swift) implementation.

**Changed**
- Added `docs/CODE_WIKI.md` with 23 sections covering: project overview, layered architecture, repository layout, Swift package configuration, AppKit/SwiftUI startup, UI views, `AppModel` state layer, `NativeBackendService` backend facade, four `PaperSource` providers (FrankCIE / EasyPaper / PastPapers / PapaCambridge), parsing, networking, downloads (queue / rate limiter / circuit breaker / staged filesystem / preview), persistence, update service, design system, key models, error and diagnostic flow, test suite, build scripts, GitHub Actions workflow, local run/build/release steps, dependencies, privacy/disclaimer, and key invariants.
- No code, configuration, or build files were changed. The Wiki is documentation-only and uses `file:///` links to every referenced source file.

**Reason**
- User requested a complete Code Wiki so future maintainers can understand the native codebase, its boundaries, and how to run / build / release the app without scanning the full repository.

**Tested**
- Read `AGENTS.md`, `docs/PROJECT_INDEX.md`, `docs/WORK_LOG.md` first.
- Inspected relevant files only: `Package.swift`, `main.swift`, `AppDelegate`, `AppMenu*`, `RootView`, `AppModel*`, `AppBootCoordinator`, `NativeBackendService`, four `*Source.swift`, `PaperFilenameParser` / `PaperGrouper` / `SubjectNormalizer` / `HTMLPaperLinkExtractor`, `NetworkClient` / `HTTPRequestBuilder` / `HTTPFileTransferClient` / `ProxyConfiguration`, `DownloadManager` / `DownloadQueue` / `RateLimiter` / `CircuitBreaker` / `StagedFileSystem` / `DownloadDestinationBuilder` / `DownloadSourceURLResolver` / `PreviewFileService`, `AppStoragePaths` / `JSONFileStore` / `SettingsStore` / `FavoritesStore` / `DownloadHistoryStore` / `DownloadSessionStore` / `SearchCacheStore` / `SupportDiagnosticsStore` / `LegacyCacheMigrator`, `UpdateService` / `UpdateModels`, `BackendConstants` / `BackendError`, `Design*`, `Models/*`, test directory, and `scripts/build_native_dmg.sh` / `scripts/verify_native_dmg.sh` / `scripts/run_native_release_audit.sh` / `.github/workflows/build.yml` / `version.json`.
- No code or build commands were executed.

**Risks / Notes**
- The Wiki only describes the active native tree and explicitly excludes `legacy/`. If the live source canary or any recent source provider behavior changed without a code change, the Wiki may need a follow-up update. The Wiki is intentionally concise and relies on the user-facing `docs/RELEASE_AND_VALIDATION.md` for current workflow behavior; cross-check before tagging a release.
