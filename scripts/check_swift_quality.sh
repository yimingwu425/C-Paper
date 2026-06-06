#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTLINT_CONFIG="$ROOT_DIR/.swiftlint.yml"
SWIFTFORMAT_CONFIG="$ROOT_DIR/.swiftformat"

run_swiftlint() {
  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "Skipping SwiftLint check: swiftlint is not installed."
    return 0
  fi

  swiftlint lint --strict --config "$SWIFTLINT_CONFIG"
}

run_swiftformat() {
  if ! command -v swiftformat >/dev/null 2>&1; then
    echo "Skipping SwiftFormat check: swiftformat is not installed."
    return 0
  fi

  swiftformat "$ROOT_DIR/Package.swift" "$ROOT_DIR/macos" --lint --config "$SWIFTFORMAT_CONFIG"
}

run_swiftlint
run_swiftformat
