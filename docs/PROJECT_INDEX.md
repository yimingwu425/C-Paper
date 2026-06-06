# PROJECT_INDEX

## Purpose

This file is a compact native-first map of the repository so future contributors and AI agents can locate the active implementation quickly.

## Active Main Directories

- `macos/`: Active SwiftUI/AppKit app, Swift-native backend, and Swift tests
- `scripts/`: Active native build/release scripts
- `scripts/lib/`: Shared shell helpers used by active native scripts
- `assets/`: Shared icons and image assets
- `docs/`: Project memory and internal documentation
- `docs/RELEASE_AND_VALIDATION.md`: Native release, validation, install, signing/notarization, privacy/disclaimer, and data source reliability notes

Project site note:

- External project site: external-link pending; do not treat `site/` as an active in-repo directory

## Legacy Directories

- `legacy/python-backend/`: Archived Python bridge/backend/test suite retained for historical reference
- `legacy/pywebview/`: Archived Python + pywebview frontend shell
- `legacy/pywebview/packaging/`: Legacy pywebview packaging scripts

These directories are preserved for reference and limited maintenance only. Do not treat them as the active app.

## Important Source Files

- `Package.swift`: Root Swift package definition
- `macos/Sources/CPaperNativeApp/AppDelegate.swift`: Native app startup and AppKit main-menu installation
- `macos/Sources/CPaperNativeApp/AppMenuCommand.swift`, `AppMenuCommandCenter.swift`, and `AppMenuController.swift`: Active menu command contract, routing, and Chinese macOS menu-bar construction
- `macos/Sources/CPaperNativeApp/State/AppModel.swift` and `AppModel+*.swift`: Active app state and UI workflow coordination
- `macos/Sources/CPaperNativeApp/Views/RootView.swift`: Root UI composition and ready-state menu command binding
- `macos/Sources/CPaperNativeApp/Backend/Core/NativeBackendService.swift`: Swift backend facade used by the app
- `macos/Sources/CPaperNativeApp/Backend/Sources/`: Data source registry and providers
- `macos/Sources/CPaperNativeApp/Backend/Parsing/`: Filename, subject, grouping, and HTML link parsing
- `macos/Sources/CPaperNativeApp/Backend/Networking/`: URLSession request, proxy, and HTTP handling
- `macos/Sources/CPaperNativeApp/Backend/Downloads/`: Swift download queue, limiter, circuit breaker, and manager
- `macos/Sources/CPaperNativeApp/Backend/Persistence/`: Settings, favorites, history, cache, and legacy migration stores
- `macos/Sources/CPaperNativeApp/Backend/Updates/`: GitHub Release update checking and native DMG download service
- `macos/Tests/CPaperNativeTests/`: Active Swift test suite
- `docs/RELEASE_AND_VALIDATION.md`: Current native `validate/package/release` flow and optional Developer ID/notary release notes

## Runtime Relationships

- The macOS app is the active maintained product.
- The root `Package.swift` builds and runs the active app target.
- The SwiftUI/AppKit UI in `macos/` calls `NativeBackendService` directly.
- `AppDelegate` installs the AppKit main menu, and `ReadyRootView` binds product menu actions into `AppMenuCommandCenter` only while the ready UI is active.
- `NativeBackendService` coordinates persistence, source lookup, parsing, and downloads.
- The active app no longer starts or packages a Python bridge.

## UI Locations

- Active UI: `macos/Sources/CPaperNativeApp/Views/`
- Active state: `macos/Sources/CPaperNativeApp/State/`
- Active menu layer: `macos/Sources/CPaperNativeApp/AppMenuCommand.swift`, `AppMenuCommandCenter.swift`, `AppMenuController.swift`
- Legacy UI:
  - `legacy/pywebview/ui_v2.html`
  - `legacy/pywebview/ui_v2.css`
  - `legacy/pywebview/ui_v2.js`
- Project site: external / link pending

## Tests

- Active Swift tests: `macos/Tests/CPaperNativeTests/`
- Default validation command: `swift test --jobs 1`
- Legacy Python tests: `legacy/python-backend/tests/`

## Release And Validation

- Native workflow: `.github/workflows/build.yml`
- `validate`: shell syntax, JSON metadata, workflow YAML, version drift, repo hygiene, Swift quality checks, and `swift test --jobs 1`
- `package`: runs after `validate` for `workflow_dispatch` and `push`, builds/verifies/mounts the native DMG, and uploads the DMG artifact
- `release`: tag-only GitHub Release job; runs only for `push` events to `v*` tags after `package`
- Signing defaults to ad hoc; optional Developer ID/notary signing and notarization require the documented local env vars or all GitHub Actions secrets
- Release/install/privacy/disclaimer/data source reliability details live in `docs/RELEASE_AND_VALIDATION.md`

## Config And Metadata Files

- `Package.swift`: Active Swift package definition
- `scripts/build_native_dmg.sh`: Active native build script
- `scripts/lib/native_dmg_helpers.sh`: Shared DMG build helper functions
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
- `scripts/build_native_dmg.sh`: Main native build path
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
- The project site is documented as external-link pending; do not assume an in-repo `site/` app tree.
- The repository may still contain historical Python/pywebview references in legacy-only files.
