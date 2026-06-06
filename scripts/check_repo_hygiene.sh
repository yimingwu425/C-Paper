#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN_ROOT="$ROOT_DIR"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      SCAN_ROOT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$SCAN_ROOT" ]; then
  echo "Repo hygiene root does not exist: $SCAN_ROOT" >&2
  exit 1
fi

tmp_matches="$(mktemp)"
trap 'rm -f "$tmp_matches"' EXIT

(
  cd "$SCAN_ROOT"
  find . \
    \( \
      -name .git -o \
      -name .worktrees -o \
      -name .build -o \
      -name build -o \
      -name dist -o \
      -name DerivedData -o \
      -name __pycache__ -o \
      -name .pytest_cache -o \
      -name .mypy_cache -o \
      -name .ruff_cache -o \
      -name node_modules \
    \) -prune -o \
    \( \
      -name '.DS_Store' -o \
      -name '.AppleDouble' -o \
      -name '.LSOverride' -o \
      -name '._*' -o \
      -name 'Thumbs.db' -o \
      -name '* 2.*' \
    \) -print | LC_ALL=C sort >"$tmp_matches"
)

if [ -s "$tmp_matches" ]; then
  echo "Repo hygiene check failed. Remove pollution files:" >&2
  sed 's#^\./#  #g' "$tmp_matches" >&2
  exit 1
fi

echo "Repo hygiene check passed for $SCAN_ROOT"
