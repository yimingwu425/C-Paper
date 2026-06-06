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
