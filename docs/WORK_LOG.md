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
