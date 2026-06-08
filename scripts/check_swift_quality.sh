#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTLINT_CONFIG="$ROOT_DIR/.swiftlint.yml"
SWIFTFORMAT_CONFIG="$ROOT_DIR/.swiftformat"

is_quality_target() {
  local path="${1:-}"

  if [ "$path" = "Package.swift" ]; then
    return 0
  fi

  case "$path" in
    macos/*.swift | macos/*/*.swift | macos/*/*/*.swift | macos/*/*/*/*.swift | macos/*/*/*/*/*.swift)
      return 0
      ;;
  esac

  return 1
}

collect_quality_paths() {
  local diff_output=""
  local path=""

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "${CPAPER_SWIFT_QUALITY_BASE_REF:-}" ] && [ -n "${CPAPER_SWIFT_QUALITY_HEAD_REF:-}" ]; then
      diff_output="$(git diff --name-only --diff-filter=ACMR "$CPAPER_SWIFT_QUALITY_BASE_REF" "$CPAPER_SWIFT_QUALITY_HEAD_REF" || true)"
    elif [ -n "${GITHUB_ACTIONS:-}" ] && git rev-parse HEAD^ >/dev/null 2>&1; then
      diff_output="$(git diff --name-only --diff-filter=ACMR HEAD^ HEAD || true)"
    else
      diff_output="$(
        {
          git diff --name-only --diff-filter=ACMR --cached || true
          git diff --name-only --diff-filter=ACMR || true
        } | sort -u
      )"
    fi
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if is_quality_target "$path"; then
      printf '%s\n' "$ROOT_DIR/$path"
    fi
  done <<EOF
$diff_output
EOF
}

run_swiftlint() {
  local paths=("$@")

  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "Skipping SwiftLint check: swiftlint is not installed."
    return 0
  fi

  if [ "${#paths[@]}" -eq 0 ]; then
    echo "Skipping SwiftLint check: no changed Swift files to lint."
    return 0
  fi

  local path=""
  for path in "${paths[@]}"; do
    swiftlint lint --strict --config "$SWIFTLINT_CONFIG" --path "$path"
  done
}

run_swiftformat() {
  local paths=("$@")

  if ! command -v swiftformat >/dev/null 2>&1; then
    echo "Skipping SwiftFormat check: swiftformat is not installed."
    return 0
  fi

  if [ "${#paths[@]}" -eq 0 ]; then
    echo "Skipping SwiftFormat check: no changed Swift files to lint."
    return 0
  fi

  swiftformat "${paths[@]}" --lint --config "$SWIFTFORMAT_CONFIG"
}

QUALITY_PATHS=()

while IFS= read -r path; do
  [ -n "$path" ] || continue
  QUALITY_PATHS+=("$path")
done < <(collect_quality_paths)

if [ "${#QUALITY_PATHS[@]}" -eq 0 ]; then
  run_swiftlint
  run_swiftformat
else
  run_swiftlint "${QUALITY_PATHS[@]}"
  run_swiftformat "${QUALITY_PATHS[@]}"
fi
