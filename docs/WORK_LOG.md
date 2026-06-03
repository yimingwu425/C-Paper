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
