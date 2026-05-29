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
