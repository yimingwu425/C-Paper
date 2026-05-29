# AGENTS.md

## Read This First

Before making changes, read:

1. `AGENTS.md`
2. `docs/PROJECT_INDEX.md`
3. `docs/WORK_LOG.md`

Inspect only the files relevant to the current task. Do not scan the whole repository unless the task truly requires it.

## Project Purpose

C-Paper is a desktop tool for searching, previewing, and batch-downloading Cambridge International Education past papers and mark schemes.

The actively maintained product is now the native macOS version. The Swift/macOS client, the Python bridge, and the shared Python backend together form the current main implementation. The old Python + pywebview desktop shell is legacy.

## Active Architecture

- `Package.swift`: Root Swift package entrypoint
- `macos/`: Active native macOS app source and Swift tests
- `bridge/`: Active Python bridge used by the native app
- `backend/`: Active shared Python backend
- `tests/`: Active Python backend test suite

## Legacy Architecture

- `legacy/pywebview/`: Archived Python + pywebview frontend shell
- `legacy/pywebview/packaging/`: Archived pywebview packaging scripts

Do not treat `legacy/pywebview/` as the main implementation unless the task explicitly targets legacy maintenance.

## Detected Tech Stack

- Swift Package Manager
- SwiftUI / AppKit macOS client
- Python shared backend modules
- Python JSON-lines bridge
- `requests` and `urllib3`
- `pytest`
- Static project site in `site/`

## Key Directories

- `macos/`: Active macOS client
- `bridge/`: Active Python bridge
- `backend/`: Active Python backend logic
- `tests/`: Python backend tests
- `legacy/pywebview/`: Archived pywebview app shell
- `scripts/`: Active native build/release scripts
- `assets/`: Icons and image assets
- `docs/`: Internal project documentation and project memory
- `site/`: Static project site

## Important Commands

Safely inferred from repository docs and file layout:

- `swift run CPaperNative`: Run the active macOS app
- `swift test`: Run Swift tests
- `pytest`: Run the Python backend test suite
- `bash scripts/build_native_dmg.sh`: Build the active native macOS DMG
- `bash script/build_and_run.sh`: Build and launch the native app locally

Legacy-only commands:

- `python legacy/pywebview/main.py`
- `bash legacy/pywebview/packaging/build_mac.sh`
- `legacy\\pywebview\\packaging\\build_win.bat`

## Safety Rules For Future AI Agents

- Do not print, expose, or commit secrets, tokens, credentials, or private local data.
- Do not modify unrelated files.
- Do not casually edit build outputs, caches, generated files, or vendored content.
- Avoid scanning large or irrelevant directories such as `.git/`, `node_modules/`, build output folders, caches, `__pycache__/`, and generated artifacts.
- Prefer targeted inspection with file-level reads over broad repository sweeps.
- Treat release/build scripts, bridge path handling, backend persistence logic, and packaging files as sensitive areas; edit them only when the task requires it.
- Remove obvious junk such as `.DS_Store` and empty directories when encountered, but do not delete files with uncertain purpose without explicit confirmation.
- When details are unclear, write `Unknown / not yet documented` instead of guessing.

## Engineering Principles

When writing code or design, follow first-principles thinking.

Before implementing, clarify:

- What problem is being solved?
- What is the smallest reliable solution?
- What are the real constraints?
- What should be abstracted, and what should stay simple?
- What existing code can be reused?

Avoid adding complexity just because it looks more advanced. Prefer clear, boring, reliable solutions.

## Reusable Module Rules

Prefer reusable modules over one-off code when the same pattern appears more than once.

Use reusable modules for:

- Repeated UI components
- Repeated layout patterns
- Shared API/client logic
- Shared parsing or formatting logic
- Shared validation logic
- Repeated constants or configuration
- Repeated file/path handling
- Repeated error handling

Do not over-abstract too early. Create a reusable module only when:

- The same logic appears in multiple places, or
- The code is clearly a stable concept in the project, or
- Reuse would make future changes safer and simpler.

## Code Structure Rules

When adding new functionality:

- Check existing modules before creating new ones.
- Prefer extending existing components/utilities when appropriate.
- Keep business logic separate from UI rendering.
- Keep IO/network/file-system code separate from pure logic when possible.
- Keep modules small and focused.
- Give modules clear names based on responsibility.
- Avoid large files that mix unrelated concerns.
- Avoid duplicating logic across files.

## Design System Rules

When designing UI:

- Reuse existing visual patterns before creating new ones.
- Prefer shared components for buttons, cards, panels, inputs, modals, lists, and navigation.
- Keep spacing, typography, radius, shadows, and colors consistent.
- If the project has design tokens or CSS variables, use them instead of hardcoded values.
- Do not introduce a new visual style unless the task explicitly requires it.
- Keep interfaces simple, readable, and task-focused.

## Working Rules

- Read `AGENTS.md`, `docs/PROJECT_INDEX.md`, and `docs/WORK_LOG.md` before changing code or configuration.
- Inspect only the relevant files for the task instead of scanning the full repository.
- Prioritize `macos/`, `bridge/`, `backend/`, and `tests/` for active maintenance work.
- Only touch `legacy/pywebview/` when the task explicitly targets legacy code.
- After every code or configuration change, append a short entry to `docs/WORK_LOG.md`.
- For every implementation, prefer this order:
  1. Understand the existing structure.
  2. Reuse existing modules if suitable.
  3. Extract a reusable helper/component only when it reduces duplication or clarifies responsibility.
  4. Make the smallest safe change.
  5. Verify that behavior did not change unintentionally.
  6. Update `docs/PROJECT_INDEX.md` if structure changes.
  7. Update `docs/WORK_LOG.md` after code or configuration changes.
- Unless the user explicitly requests another language, reply to the user in Chinese.
- Keep documentation concise and factual.
