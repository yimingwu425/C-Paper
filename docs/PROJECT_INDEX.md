# PROJECT_INDEX

## Purpose

This file is a compact native-first map of the repository so future contributors and AI agents can locate the active implementation quickly.

## Active Main Directories

- `macos/`: Active SwiftUI/AppKit app, Swift-native backend, and Swift tests
- `scripts/`: Active native build/release scripts
- `assets/`: Shared icons and image assets
- `docs/`: Project memory and internal documentation
- `site/`: Static project site

## Legacy Directories

- `legacy/python-backend/`: Archived Python bridge/backend/test suite retained for historical reference
- `legacy/pywebview/`: Archived Python + pywebview frontend shell
- `legacy/pywebview/packaging/`: Legacy pywebview packaging scripts

These directories are preserved for reference and limited maintenance only. Do not treat them as the active app.

## Important Source Files

- `Package.swift`: Root Swift package definition
- `macos/Sources/CPaperNativeApp/State/AppModel.swift`: Active app state and UI workflow coordination
- `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift`: Swift backend facade used by the app
- `macos/Sources/CPaperNativeApp/Backend/Sources/`: Data source registry and providers
- `macos/Sources/CPaperNativeApp/Backend/Parsing/`: Filename, subject, grouping, and HTML link parsing
- `macos/Sources/CPaperNativeApp/Backend/Networking/`: URLSession request, proxy, and HTTP handling
- `macos/Sources/CPaperNativeApp/Backend/Downloads/`: Swift download queue, limiter, circuit breaker, and manager
- `macos/Sources/CPaperNativeApp/Backend/Persistence/`: Settings, favorites, history, cache, and legacy migration stores
- `macos/Tests/CPaperNativeTests/`: Active Swift test suite

## Runtime Relationships

- The macOS app is the active maintained product.
- The macOS app calls `NativeBackendService` directly.
- `NativeBackendService` coordinates persistence, source lookup, parsing, and downloads.
- `SourceRegistry` supports automatic fallback across Frankcie, PapaCambridge, PastPapers, and EasyPaper.
- The active app no longer starts or packages a Python bridge.

## UI Locations

- Active UI: `macos/Sources/CPaperNativeApp/Views/`
- Active state: `macos/Sources/CPaperNativeApp/State/`
- Legacy UI:
  - `legacy/pywebview/ui_v2.html`
  - `legacy/pywebview/ui_v2.css`
  - `legacy/pywebview/ui_v2.js`
- Static site:
  - `site/index.html`
  - `site/styles.css`
  - `site/script.js`

## Tests

- Active Swift tests: `macos/Tests/CPaperNativeTests/`
- Legacy Python tests: `legacy/python-backend/tests/`

## Config And Metadata Files

- `Package.swift`: Active Swift package definition
- `.github/workflows/build.yml`: Active GitHub Actions workflow for native macOS
- `scripts/build_native_dmg.sh`: Active native release script
- `legacy/python-backend/requirements.txt`: Archived Python backend/test dependencies
- `legacy/pywebview/requirements.txt`: Legacy pywebview dependencies
- `LICENSE`
- `README.md`
- `MAINTENANCE_BASELINE.md`
- `version.json`

## Areas To Avoid Editing Casually

- `macos/Sources/CPaperNativeApp/Backend/Sources/`: Sensitive to third-party source format changes
- `macos/Sources/CPaperNativeApp/Backend/Downloads/`: Core download safety, cancellation, and filesystem logic
- `macos/Sources/CPaperNativeApp/Backend/Persistence/`: User settings/history migration and local data handling
- `scripts/build_native_dmg.sh`: Main native release path
- `.github/workflows/build.yml`: Main release automation
- `legacy/`: Archived implementations; only edit when explicitly required

## High-Noise Or Generated Paths To Ignore During Normal Inspection

- `.git/`
- `.worktrees/`
- `node_modules/` if ever added
- `dist/`, `build/`, `.build/`
- `.cache/`, `.turbo/`, `.pytest_cache/`
- `__pycache__/`
- `.claude/worktrees/`

## Notes

- Swift/macOS is the only actively maintained product line.
- Python bridge/backend code is archived and not part of active packaging.
- The repository may still contain historical Python/pywebview references in legacy-only files.
