# Release And Validation

This document records the current native release and validation behavior for C-Paper. The project site remains external-link pending; do not treat `site/` as an active in-repo product site.

For the current requirement-to-evidence audit matrix behind the native release-quality goal, see `docs/RELEASE_CANDIDATE_AUDIT.md`.

## Workflow

The active native workflow is `.github/workflows/build.yml`. It is split into `validate/package/release` jobs:

| Event | Jobs | Notes |
| --- | --- | --- |
| Native-relevant pull request | `validate` | Runs validation only. Archived `legacy/` changes are intentionally outside the native path filters. |
| Native-relevant `main` push | `validate` -> `package` | Builds and verifies a DMG artifact, but does not publish a GitHub Release. |
| `v*` tag push | `validate` -> `package` -> `release` | This is the tag-only GitHub Release path for the native product line. |
| `workflow_dispatch` | `validate` -> `package` | Manual validation and packaging only; this does not publish a GitHub Release. |

`validate` runs shell syntax checks, `version.json` parsing, workflow YAML parsing, release-documentation consistency checks, version drift checks, repo hygiene checks, Swift quality checks, and `swift test --jobs 1` with a scratch directory redirected outside the repository tree.

`package` depends on `validate`. It optionally configures Developer ID signing and notarization, builds the native DMG, runs `bash scripts/verify_native_dmg.sh`, and uploads the DMG artifact. That verification step runs `hdiutil verify`, mounts the DMG, checks `CPaperNative.app`, checks the `Applications` symlink, checks the DMG background, and runs `codesign --verify --deep --strict` on the mounted app. The build script also keeps SwiftPM scratch output outside the repository tree so release builds are less exposed to workspace metadata noise, and local native scripts now retry the known transient SwiftPM `input file ... was modified during the build` failure a small number of times before surfacing a real error.

`release` depends on `package`. It downloads the packaged DMG artifact, prepares native release notes from `version.json`, and publishes the GitHub Release only when the event is a `push` to a tag.

## Signing And Notarization

Default local and CI packaging uses ad hoc signing. This is intentional so native validation and packaging continue to work without Apple credentials.

The optional Developer ID/notary path activates only when all configured inputs are present:

- Local Developer ID signing: `CPAPER_CODESIGN_IDENTITY`
- Local notarization profile: `CPAPER_NOTARY_KEYCHAIN_PROFILE`
- GitHub Actions secrets: `CPAPER_DEVELOPER_ID_CERT_P12_BASE64`, `CPAPER_DEVELOPER_ID_CERT_PASSWORD`, `CPAPER_CODESIGN_IDENTITY`, `CPAPER_NOTARY_KEYCHAIN_PROFILE`, `CPAPER_NOTARY_APPLE_ID`, `CPAPER_NOTARY_TEAM_ID`, `CPAPER_NOTARY_APP_PASSWORD`

If any GitHub Actions secret is missing, the package job skips Developer ID setup and the build script remains on the ad hoc path. When notarization is configured, the build script signs the app first, creates the final DMG, submits it with `xcrun notarytool submit --wait`, and staples it with `xcrun stapler staple`.

## Install Notes

Users should download `C-Paper-Native-*-standalone-*.dmg` from GitHub Releases, open the DMG, and drag `CPaperNative.app` into `Applications`.

For ad hoc builds, macOS may show a developer verification warning on first launch. In that case, right-click `CPaperNative.app`, choose **Open**, and confirm.

## Privacy And Disclaimer

C-Paper is a local desktop tool. It does not upload, collect, or share personal data. It stores settings, favorites, download history, and caches locally under `~/Library/Application Support/C-Paper/`, and stores downloaded files in the user-selected directory.

C-Paper does not own, store, host, or redistribute Cambridge International Education papers or mark schemes. Those materials remain owned by Cambridge Assessment International Education or the relevant rights holders. Users are responsible for using downloaded materials lawfully.

## Data Source Reliability

The app depends on third-party public data sources. In automatic mode, FrankCIE is the primary source, EasyPaper is the main fallback, PastPapers is best-effort, and PapaCambridge reports unavailable when Cloudflare blocks non-browser clients. Manual source mode keeps the selected source and does not auto-switch on failure. Some manual sources also do not expose a subject directory, so manual subject-code entry is an expected recovery path rather than a fallback bug.

This privacy/disclaimer/data source reliability boundary is part of the release documentation: C-Paper reports third-party source failures instead of pretending they are successful or bypassing anti-automation challenges.

When validating a release candidate against real upstream source behavior, use the opt-in live canary instead of assuming local fixture tests prove third-party availability. The current live canary command is:

- `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`

This canary is intentionally optional because upstream sites are unstable external dependencies. It should confirm at least these release-time expectations:

- Subject fallback can still populate search inputs when FrankCIE is unavailable.
- Automatic search fallback can still return a downloadable PDF when FrankCIE is unavailable.
- Manual source mode can still stay on the selected source instead of silently falling back.
- Manual source mode can still surface a clear selected-source unavailable reason when the chosen provider is degraded.
- Individual source checks still either return a downloadable PDF or fail with a clear unavailable reason.

## Documentation Validation

This document is not covered by a RED/GREEN runtime test. Use static checks instead:

- Run `bash scripts/run_native_release_audit.sh` for the default native release-candidate audit path.
- Run `bash scripts/check_release_docs.sh`.
- After packaging locally, run `bash scripts/verify_native_dmg.sh`.
- Parse `.github/workflows/build.yml` as YAML.
- Confirm public docs do not contradict the workflow graph.
- Search for the release terms: `validate/package/release`, `tag-only`, `workflow_dispatch`, `ad hoc`, `Developer ID/notary`, `external-link pending`, and `privacy/disclaimer/data source reliability`.
- Confirm the optional live canary command and expectations still match `LiveSourceTests`.
- Confirm local native scripts still retry the known transient SwiftPM `input file ... was modified during the build` failure.
- Run `git diff --check`.

Optional deeper audit:

- Add `--release-candidate` to run the stronger RC pass that includes both package verification and the live source canary in one command.
- Add `--with-package` to include a local `CONFIGURATION=release bash scripts/build_native_dmg.sh` plus `bash scripts/verify_native_dmg.sh`.
- Add `--with-live-sources` to include `RUN_LIVE_SOURCE_TESTS=1 swift test --jobs 1 --filter LiveSourceTests`.
