#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_PACKAGE=0
WITH_LIVE_SOURCES=0
SWIFT_SCRATCH_PATH="${CPAPER_SWIFT_SCRATCH_PATH:-${TMPDIR:-/tmp}/cpaper-native-swiftpm}"

source "$ROOT_DIR/scripts/lib/swiftpm_retry_helpers.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/run_native_release_audit.sh [options]

Options:
  --with-package         Include native DMG build + verify steps.
  --with-live-sources    Include the opt-in live source canary.
  --release-candidate    Run the stronger RC pass by enabling both package and live-source checks.
  --help                 Show this help message.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-package)
      WITH_PACKAGE=1
      shift
      ;;
    --with-live-sources)
      WITH_LIVE_SOURCES=1
      shift
      ;;
    --release-candidate)
      WITH_PACKAGE=1
      WITH_LIVE_SOURCES=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"
mkdir -p "$SWIFT_SCRATCH_PATH"

echo "[1/8] Checking shell syntax..."
bash -n \
  scripts/build_native_dmg.sh \
  scripts/check_release_docs.sh \
  scripts/check_repo_hygiene.sh \
  scripts/check_swift_quality.sh \
  scripts/check_version_drift.sh \
  scripts/verify_native_dmg.sh \
  scripts/run_native_release_audit.sh \
  scripts/lib/native_dmg_helpers.sh \
  scripts/lib/swiftpm_retry_helpers.sh \
  scripts/lib/version_helpers.sh

echo "[2/8] Validating version metadata..."
python3 -m json.tool version.json >/dev/null

echo "[3/8] Parsing workflow YAML..."
ruby - <<'RUBY'
require "yaml"
YAML.load_file(".github/workflows/build.yml")
puts "Parsed .github/workflows/build.yml"
RUBY

echo "[4/8] Checking release documentation consistency..."
bash scripts/check_release_docs.sh

echo "[5/8] Checking version drift..."
bash scripts/check_version_drift.sh

echo "[6/8] Checking repo hygiene..."
bash scripts/check_repo_hygiene.sh

echo "[7/8] Running full Swift test suite..."
run_swiftpm_command_with_retry \
  "running the full Swift test suite" \
  swift test --jobs 1 --scratch-path "$SWIFT_SCRATCH_PATH"

if [ "$WITH_LIVE_SOURCES" = "1" ]; then
  echo "[8/8] Running live source canary..."
  RUN_LIVE_SOURCE_TESTS=1 run_swiftpm_command_with_retry \
    "running the live source canary" \
    swift test --jobs 1 --scratch-path "$SWIFT_SCRATCH_PATH" --filter LiveSourceTests
else
  echo "[8/8] Live source canary skipped."
fi

if [ "$WITH_PACKAGE" = "1" ]; then
  echo "[package] Building release DMG..."
  CONFIGURATION=release bash scripts/build_native_dmg.sh
  echo "[package] Verifying release DMG..."
  bash scripts/verify_native_dmg.sh
fi

if [ "$WITH_PACKAGE" = "1" ] && [ "$WITH_LIVE_SOURCES" = "1" ]; then
  echo "Native release audit passed (stronger RC mode)."
else
  echo "Native release audit passed."
fi
