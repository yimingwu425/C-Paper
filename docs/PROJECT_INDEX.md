# PROJECT_INDEX

## Purpose

This file is a compact native-first map of the repository so future contributors and AI agents can locate the active implementation quickly.

## Active Main Directories

- `macos/`: Active native macOS app source and Swift tests
- `bridge/`: Active Python bridge invoked by the macOS app
- `backend/`: Active shared Python backend
- `tests/`: Python backend tests
- `scripts/`: Active native build/release scripts
- `assets/`: Shared icons and image assets
- `docs/`: Project memory and internal documentation

## Legacy Directories

- `legacy/pywebview/`: Archived Python + pywebview frontend shell
- `legacy/pywebview/packaging/`: Legacy pywebview packaging scripts

These directories are preserved for reference and limited maintenance only. Do not treat them as the main app.

## Important Source Files

- `Package.swift`: Root Swift package definition
- `macos/Sources/CPaperNativeApp/`: Active Swift app source
- `macos/Tests/CPaperNativeTests/`: Swift test suite
- `bridge/cpaper_bridge.py`: Active native bridge process
- `backend/api.py`: Shared backend API surface
- `backend/engine.py`: Shared orchestration logic
- `backend/parser.py`: Shared parsing logic
- `backend/cache.py`: Shared cache logic
- `backend/limiter.py`: Shared rate limiting logic
- `backend/plugin_manager.py`: Shared plugin management logic
- `backend/updater.py`: Shared update logic
- `tests/conftest.py`: Python test bootstrap for the shared backend

## Runtime Relationships

- The macOS app is the active maintained product.
- The macOS app calls `bridge/cpaper_bridge.py`.
- The bridge imports and uses the shared Python backend from `backend/`.
- The legacy pywebview frontend also uses the same `backend/`, but that frontend is no longer the main implementation.

## UI Locations

- Active UI: `macos/Sources/CPaperNativeApp/`
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
- Active Python tests:
  - `tests/test_cache.py`
  - `tests/test_circuit_breaker.py`
  - `tests/test_download_cancel.py`
  - `tests/test_download_engine.py`
  - `tests/test_parsing.py`
  - `tests/test_persistence.py`
  - `tests/test_plugin_manager.py`
  - `tests/test_rate_limiter.py`
  - `tests/test_updater.py`

## Config And Metadata Files

- `Package.swift`: Active Swift package definition
- `requirements.txt`: Active Python backend/test dependencies
- `legacy/pywebview/requirements.txt`: Legacy pywebview dependencies
- `.github/workflows/build.yml`: Active GitHub Actions workflow for native macOS
- `scripts/build_native_dmg.sh`: Active native build/release script
- `legacy/pywebview/packaging/appveyor.yml`: Legacy Windows/AppVeyor config
- `LICENSE`
- `README.md`
- `MAINTENANCE_BASELINE.md`
- `version.json`

## Areas To Avoid Editing Casually

- `bridge/cpaper_bridge.py`: Path/bootstrap mistakes will break the active native app
- `backend/parser.py`: Sensitive to upstream format changes
- `backend/engine.py`: Core orchestration logic
- `backend/updater.py`: Update behavior can affect release flows
- `macos/Sources/CPaperNativeApp/Bridge/`: Bridge lookup and process handling
- `scripts/build_native_dmg.sh`: Main native release path
- `.github/workflows/build.yml`: Main release automation
- `legacy/pywebview/`: Archived implementation; only edit when explicitly required

## High-Noise Or Generated Paths To Ignore During Normal Inspection

- `.git/`
- `node_modules/` if ever added
- `dist/`, `build/`, `.build/`
- `.cache/`, `.turbo/`, `.pytest_cache/`
- `__pycache__/`
- `.claude/worktrees/`

## Notes

- Swift/macOS is the only actively maintained product line.
- The repository may still contain old native/pywebview-era reference paths in historical or nonessential files; prefer the paths documented here.
