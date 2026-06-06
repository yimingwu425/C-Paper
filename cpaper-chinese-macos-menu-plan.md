# Plan: C-Paper Chinese macOS Menu Bar

**Generated**: 2026-06-06

## Overview

Add a professional Chinese macOS menu bar to the native C-Paper app without merging, pushing, or touching `main`. The current app starts through manual `NSApplication` / `NSWindow` setup, so the implementation should install an AppKit `NSMenu` explicitly and route product-specific commands through a small command center bound to the ready `AppModel`.

This is an implementation plan only. It is optimized for at most 6 concurrent agents; the recommended execution uses no more than 2 agents in parallel.

## Prerequisites

- Current branch: `codex/cpaper-professionalization`.
- Do not merge, push, or edit `main`.
- Do not edit `AGENTS.md`.
- Active app source is under `macos/Sources/CPaperNativeApp/`; tests are under `macos/Tests/CPaperNativeTests/`.
- Context7 was not available in this tool environment, so external documentation should be checked against official Apple Developer documentation:
  - `https://developer.apple.com/documentation/appkit/nsapplication`
  - `https://developer.apple.com/documentation/appkit/nsmenu`
  - `https://developer.apple.com/documentation/appkit/nsmenuitem`
  - `https://developer.apple.com/documentation/appkit/nsmenuitemvalidation`

## Dependency Graph

```text
T0 ──┬── T1 ──┬── T3 ──┐
     │        └── T4 ──┼── T5 ── T6
     └── T2 ──────────┘
```

## Tasks

### T0: Baseline Guard

- **depends_on**: []
- **location**: repository root
- **description**: Confirm the implementation starts from a clean `codex/cpaper-professionalization` worktree and that no merge/push/main change is attempted. Read `AGENTS.md`, `docs/PROJECT_INDEX.md`, and `docs/WORK_LOG.md` before editing.
- **validation**: `git status --short` is clean before implementation; `git branch --show-current` returns `codex/cpaper-professionalization`.
- **status**: Completed
- **log**:
  - Read `AGENTS.md`, `docs/PROJECT_INDEX.md`, and `docs/WORK_LOG.md` before editing.
  - Static baseline evidence captured at repo root:
    - `git status --short` -> `(no output)`
    - `git branch --show-current` -> `codex/cpaper-professionalization`
  - Confirmed this task is documentation-only baseline guarding; no menu implementation, merge, push, or `main` branch edit was attempted.
  - `reason_not_testable`: This is a non-testable static precondition check. Validation is limited to exact command evidence from `git status --short` and `git branch --show-current`.
- **files edited/created**: `cpaper-chinese-macos-menu-plan.md`

### T1: Build Chinese AppKit Menu Layer

- **depends_on**: [T0]
- **location**: `macos/Sources/CPaperNativeApp/AppMenuCommand.swift`, `macos/Sources/CPaperNativeApp/AppMenuCommandCenter.swift`, `macos/Sources/CPaperNativeApp/AppMenuController.swift`, `macos/Tests/CPaperNativeTests/AppMenuControllerTests.swift`, `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`
- **description**: Create the menu command contract, command center, and AppKit menu builder. `AppMenuCommand` should include `showAbout`, `showSettings`, `checkForUpdates`, `refreshCurrentView`, `showSearch`, `showBatch`, `showDownloads`, `revealSaveDirectory`, `copyLatestDiagnostic`, `revealSupportDirectory`, `openWebsite`, `openGitHub`, and `reportIssue`. `showAbout` must mean the standard AppKit About panel, not a custom window. `AppMenuCommandCenter` should expose `bind(handler:canPerform:)`, `unbind()`, `dispatch(_:)`, and `canPerform(_:)`, implement `NSMenuItemValidation`, and dispatch menu items through `representedObject`. Unbound product commands must be disabled by default and dispatching an unbound command must be a no-op. `AppMenuController` should build these top-level menus exactly: `C-Paper`, `文件`, `编辑`, `显示`, `窗口`, `帮助`.
- **validation**: Unit tests assert top-level menu titles, required Chinese item titles, `服务` submenu assignment, `NSApp.windowsMenu` / `NSApp.helpMenu` wiring after installation, and shortcuts: `设置...` = command-comma, `退出 C-Paper` = command-Q, `关闭窗口` = command-W, `搜索`/`批量`/`下载` = command-1/2/3. Command-center tests cover bound dispatch, unbound no-op behavior, `unbind()` disabling product commands, and command validation through `representedObject`.
- **status**: Completed
- **log**:
  - Added `AppMenuCommand` enum with the planned command set for the native menu layer.
  - Added `AppMenuCommandCenter` with `bind(handler:canPerform:)`, `unbind()`, `dispatch(_:)`, `canPerform(_:)`, `NSMenuItemValidation`, and `representedObject`-based dispatch.
  - Added `AppMenuController` to build the top-level AppKit menus `C-Paper`, `文件`, `编辑`, `显示`, `窗口`, and `帮助`, including Chinese item titles, services submenu wiring, and required shortcuts.
  - Wrote menu-layer unit tests first, captured RED failure from missing `AppMenuCommand`, `AppMenuCommandCenter`, and `AppMenuController` symbols, then implemented the minimal source needed to satisfy the tests.
  - Validation:
    - `swift build --target CPaperNativeApp`
    - `swift test --jobs 1 --filter 'AppMenu(CommandCenter|Controller)Tests'`
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/AppMenuCommand.swift`
  - `macos/Sources/CPaperNativeApp/AppMenuCommandCenter.swift`
  - `macos/Sources/CPaperNativeApp/AppMenuController.swift`
  - `macos/Tests/CPaperNativeTests/AppMenuControllerTests.swift`
  - `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`

### T2: Add Safe Save-Directory Reveal Helper

- **depends_on**: [T0]
- **location**: `macos/Sources/CPaperNativeApp/State/AppModel.swift`, `macos/Tests/CPaperNativeTests/ModelTests.swift`
- **description**: Add one shared usable-save-directory helper on `AppModel`, then use it for both `AppModel.revealSaveDirectory()` and menu validation. The helper should expand `settings.saveDirectory`, verify that it exists and is a directory, and return the resolved URL. `revealSaveDirectory()` should reveal that URL in Finder. If the path is empty, missing, or not a directory, set `errorMessage` to a concise Chinese message such as `下载文件夹不存在，请先在设置中选择有效的保存目录。` Do not create the directory automatically.
- **validation**: Model tests cover `~` expansion for an existing directory, missing paths producing the Chinese error message, and ordinary-file paths producing the same Chinese error message. Existing settings and diagnostics tests still pass.
- **status**: Completed
- **log**:
  - Added RED tests in `macos/Tests/CPaperNativeTests/ModelTests.swift` for `~` expansion and invalid save-directory reveal behavior.
  - RED evidence from repo root: `swift test --jobs 1 --filter ModelTests` failed before implementation because `AppModel` did not yet provide `usableSaveDirectoryURL()` or `revealSaveDirectory()`.
  - Implemented shared helper `usableSaveDirectoryURL()` in `macos/Sources/CPaperNativeApp/State/AppModel.swift` and reused it from new `revealSaveDirectory()`.
  - Helper expands `settings.saveDirectory`, verifies the path exists and is a directory, and returns a resolved file URL without creating directories.
  - Invalid empty/missing/file paths now set `errorMessage` to `下载文件夹不存在，请先在设置中选择有效的保存目录。`
  - GREEN evidence:
    - `swift build` passed in repo root for the active app target.
    - Isolated package harness under `/tmp/cpaper-t2-tests.iml674` ran `swift test --jobs 1 --filter ModelTests` and passed all 14 `ModelTests`, including existing settings and diagnostics coverage plus the new save-directory cases.
  - Note: repo-root `swift test` remains blocked by pre-existing T1 menu test files that reference not-yet-implemented menu types; T2 did not modify those files.
- **files edited/created**: `macos/Sources/CPaperNativeApp/State/AppModel.swift`, `macos/Tests/CPaperNativeTests/ModelTests.swift`, `cpaper-chinese-macos-menu-plan.md`

### T3: Install Main Menu During App Startup

- **depends_on**: [T1]
- **location**: `macos/Sources/CPaperNativeApp/AppDelegate.swift`, `macos/Sources/CPaperNativeApp/main.swift`
- **description**: Add a retained `AppMenuController` property to `AppDelegate` and install the menu before or during first window creation. Review the current startup chain where `applicationDidFinishLaunching` and `main.swift` can both call `showMainWindow()`, and keep that window behavior unchanged. Do not move the app to a SwiftUI `@main App` lifecycle.
- **validation**: App launches with the same main window size/title behavior; menu installation is idempotent and only installs one main menu; the menu is visible before the user can interact with the window; unbound product menu items are disabled during loading or startup failure states. `swift test --jobs 1 --filter AppMenuControllerTests` passes.
- **status**: Completed
- **log**:
  - Added a retained `AppMenuController` property to `AppDelegate` and installed the menu through a private `installMainMenuIfNeeded()` guard.
  - Kept the existing startup chain unchanged: `applicationDidFinishLaunching(_:)` still calls `showMainWindow()`, and `main.swift` may still call `showMainWindow()` again after `finishLaunching()`.
  - Installed the main menu before first-window creation by calling `installMainMenuIfNeeded()` immediately before `showMainWindow()` work in `applicationDidFinishLaunching(_:)`, and also at the start of `showMainWindow()` as a safe fallback for any direct call path.
  - Preserved existing main-window behavior by leaving the title, size, min size, toolbar style, and reactivation logic unchanged.
  - Added startup-layer tests that verify:
    - `applicationDidFinishLaunching(_:)` installs one menu and repeated `showMainWindow()` calls reuse the same main menu and same single window.
    - Direct `showMainWindow()` calls still install the menu and create the expected `C-Paper` window.
  - Validation:
    - `swift build --target CPaperNativeApp`
    - `swift test --jobs 1 --filter AppDelegateTests`
  - Validation blocker:
    - `swift test --jobs 1 --filter AppMenuControllerTests` is currently blocked by unrelated in-progress edits in `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`, which now references the not-yet-implemented T4 symbol `ReadyRootMenuBindings` and fails test-target compilation before `AppMenuControllerTests` can run.
  - `reason_not_testable`: The exact “menu becomes visible before the user can interact with the window” timing cannot be asserted reliably in a unit test here. Static validation is: `applicationDidFinishLaunching(_:)` calls `installMainMenuIfNeeded()` before `showMainWindow()`, and `showMainWindow()` itself also guards menu installation before any window creation path.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/AppDelegate.swift`
  - `macos/Tests/CPaperNativeTests/AppDelegateTests.swift`
  - `cpaper-chinese-macos-menu-plan.md`

### T4: Bind Menu Commands To Ready AppModel

- **depends_on**: [T1, T2]
- **location**: `macos/Sources/CPaperNativeApp/Views/RootView.swift`, `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`
- **description**: Bind `AppMenuCommandCenter.shared` from `ReadyRootView` when the model is ready. Menu actions should mirror existing toolbar/settings behavior: open settings sheet, run manual update check, refresh the current route, switch to search/batch/downloads, refresh downloads when switching to downloads, reveal the save directory through the shared usable-directory helper, copy the latest diagnostic, reveal the support directory, show the standard AppKit About panel, and open website/GitHub/issues URLs through `NSWorkspace`. Unbind when the ready view disappears so product commands return to disabled/no-op during loading or failure states. Menu validation should disable `刷新当前视图` while `model.isLoading`, disable `检查更新...` while `updateStatus` is `.checking` or `.downloading`, disable `复制最近诊断` when `model.lastDiagnostic == nil`, and disable `显示下载文件夹` when the shared usable-save-directory helper returns nil.
- **validation**: Command-center tests cover ready binding, `unbind()` after ready view disappearance, disabled startup/failure state behavior, update-check state gating, save-directory validation, and successful dispatch. Manual smoke testing confirms `设置...`, `搜索`, `批量`, and `下载` perform the expected UI actions without starting downloads. Manual update QA may click `检查更新...` only to perform the existing update check and must not click `下载更新`.
- **status**: Completed
- **log**:
  - Added `ReadyRootMenuBindings` in `RootView.swift` and bound it from `ReadyRootView` with `.onAppear` / `.onDisappear` so `AppMenuCommandCenter.shared` is only active while the ready app model is visible.
  - Routed menu commands to existing ready-state behaviors: settings sheet presentation, manual update check, route refresh, search/batch/downloads switching, downloads refresh when entering downloads, save-directory reveal, diagnostic copy, support-directory reveal, standard AppKit About panel, and website/GitHub/issues URL opening via `NSWorkspace`.
  - Implemented menu validation rules in the ready binding layer:
    - disable `刷新当前视图` while `model.isLoading`
    - disable `检查更新...` while `updateStatus` is `.checking` or `.downloading`
    - disable `复制最近诊断` when `model.lastDiagnostic == nil`
    - disable `显示下载文件夹` when `usableSaveDirectoryURL()` returns `nil`
  - RED evidence: `swift test --jobs 1 --filter AppMenuCommandCenterTests` failed before implementation because `ReadyRootMenuBindings` did not exist.
  - GREEN evidence: `swift test --jobs 1 --filter AppMenuCommandCenterTests` passed with 10/10 tests after implementation.
  - Manual smoke check: launched `dist/CPaperNative.app` and confirmed `设置` opens the settings sheet, `搜索` / `批量` / `下载` switch the visible product area correctly, and no download was started during the check.
- **files edited/created**:
  - `macos/Sources/CPaperNativeApp/Views/RootView.swift`
  - `macos/Tests/CPaperNativeTests/AppMenuCommandCenterTests.swift`
  - `cpaper-chinese-macos-menu-plan.md`

### T5: Update Project Documentation

- **depends_on**: [T3, T4]
- **location**: `docs/PROJECT_INDEX.md`, `docs/WORK_LOG.md`
- **description**: If new menu source files are added, update `docs/PROJECT_INDEX.md` to mention the AppKit menu layer as part of active UI infrastructure. Append a concise `docs/WORK_LOG.md` entry describing the Chinese menu bar implementation, tests, and any manual screenshot validation. Do not edit `AGENTS.md`.
- **validation**: Documentation is concise, factual, and names only active native files. `git diff --check` reports no whitespace issues.
- **status**: Completed
- **log**:
- Updated `docs/PROJECT_INDEX.md` so the active native file map now includes `AppDelegate`, `AppMenuCommand`, `AppMenuCommandCenter`, `AppMenuController`, and `Views/RootView.swift` as the AppKit menu startup/binding layer.
- Appended a concise `docs/WORK_LOG.md` entry describing the Chinese menu bar documentation update, prior T1-T4 test coverage, and that screenshot QA remains with T6.
- Static validation:
  - `git diff --check` -> `(no output)`
- `reason_not_testable`: This is documentation/static-check work, not a runnable behavior change. Exact validation evidence is `git diff --check` -> `(no output)`.
- **files edited/created**:
  - `docs/PROJECT_INDEX.md`
  - `docs/WORK_LOG.md`
  - `cpaper-chinese-macos-menu-plan.md`

### T6: Full Validation And Screenshot QA

- **depends_on**: [T3, T4, T5]
- **location**: full repo, local app window
- **description**: Run deterministic checks and create a visual proof for the user. Build a release app, launch `dist/CPaperNative.app`, capture a screenshot showing the Chinese macOS menu bar and at least one expanded menu. Do not click actions that start downloads or upload/transmit user files. The only allowed network action in manual QA is the existing `检查更新...` check; do not click `下载更新`.
- **validation**: `swift test --jobs 1`, `git diff --check`, and `CONFIGURATION=release bash scripts/build_native_dmg.sh` pass. Manual QA confirms the menu bar contains Chinese menus and product actions. Screenshot path is reported to the user.
- **status**: Completed
- **log**:
  - Ran final deterministic validation after T1-T5 completed.
  - `swift test --jobs 1` passed with 95 executed tests, 4 skipped live-source tests, and 0 failures.
  - `git diff --check` passed with no output before final record edits.
  - `CONFIGURATION=release bash scripts/build_native_dmg.sh` passed, rebuilding:
    - `dist/CPaperNative.app`
    - `dist/C-Paper-Native-6.0.3-standalone-20260606.dmg`
  - Launched `dist/CPaperNative.app` and confirmed the app used the new Chinese macOS menu bar.
  - Manual screenshot QA evidence was provided by the user at `/var/folders/tw/7g3xnj296rg901hqqb7g5sh40000gn/T/TemporaryItems/NSIRD_screencaptureui_H5DGuP/截屏2026-06-06 22.43.28.jpeg`, showing `C-Paper`, `文件`, `编辑`, `显示`, `窗口`, and `帮助` in the macOS menu bar.
  - No download-start or update-download action was triggered during final QA.
- **files edited/created**:
  - `cpaper-chinese-macos-menu-plan.md`
  - `docs/WORK_LOG.md`

## Parallel Execution Groups

| Wave | Tasks | Can Start When |
|------|-------|----------------|
| 1 | T0 | Immediately |
| 2 | T1, T2 | T0 complete |
| 3 | T3, T4 | T1 complete; T4 also needs T2 |
| 4 | T5 | T3 and T4 complete |
| 5 | T6 | T3, T4, and T5 complete |

## Testing Strategy

- Start with targeted tests for menu structure and `revealSaveDirectory()`.
- Run `swift test --jobs 1` after integrating menu installation and command binding.
- Run `git diff --check` before every commit.
- Run `CONFIGURATION=release bash scripts/build_native_dmg.sh` only after unit tests pass.
- Manually verify the launched release app menu bar and capture a screenshot for the user.

## Risks & Mitigations

- **Menu items appear but actions do nothing**: keep all product menu items routed through `AppMenuCommandCenter` and test dispatch separately from UI.
- **Retained object lifetime bug**: retain `AppMenuController` on `AppDelegate` and use `AppMenuCommandCenter.shared` as the stable target for command menu items.
- **Editing commands break text fields**: leave standard edit items on the responder chain with `target = nil` and standard selectors instead of routing them through C-Paper commands.
- **Services/window/help menus not recognized by macOS**: assign `NSApp.servicesMenu`, `NSApp.windowsMenu`, and `NSApp.helpMenu` when installing the menu.
- **Menu validation too aggressive**: only disable product-specific actions with clear state requirements; leave standard macOS items to the responder chain.
- **Accidental side effects during QA**: avoid clicking download-start actions; `检查更新...` is allowed because it reuses existing manual update check and does not download unless a later download action is chosen.
