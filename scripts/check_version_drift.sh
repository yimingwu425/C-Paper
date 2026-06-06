#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_JSON="$ROOT_DIR/version.json"
BACKEND_CONSTANTS="$ROOT_DIR/macos/Sources/CPaperNativeApp/Backend/Core/BackendConstants.swift"
HTTP_REQUEST_BUILDER="$ROOT_DIR/macos/Sources/CPaperNativeApp/Backend/Networking/HTTPRequestBuilder.swift"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_native_dmg.sh"
README_FILE="$ROOT_DIR/README.md"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version-json)
      VERSION_JSON="$2"
      shift 2
      ;;
    --backend-constants)
      BACKEND_CONSTANTS="$2"
      shift 2
      ;;
    --http-request-builder)
      HTTP_REQUEST_BUILDER="$2"
      shift 2
      ;;
    --build-script)
      BUILD_SCRIPT="$2"
      shift 2
      ;;
    --readme)
      README_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

source "$ROOT_DIR/scripts/lib/version_helpers.sh"

fail() {
  echo "VERSION DRIFT: $1" >&2
  exit 1
}

json_version="$(version_json_value version "$VERSION_JSON")"
json_download_url="$(version_json_value download_url "$VERSION_JSON")"
expected_download_url="https://github.com/yimingwu425/C-Paper/releases/tag/v$json_version"

if [ "$json_download_url" != "$expected_download_url" ]; then
  fail "version.json download_url expected $expected_download_url but found $json_download_url"
fi

backend_version="$(python3 - "$BACKEND_CONSTANTS" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'static let version = "([^"]+)"', text)
if not match:
    raise SystemExit("Missing BackendConstants.version")
print(match.group(1))
PY
)"

if [ "$backend_version" != "$json_version" ]; then
  fail "BackendConstants.version expected $json_version but found $backend_version"
fi

if ! python3 - "$BACKEND_CONSTANTS" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'static let userAgent = "C-Paper/\\(version) (macOS; SwiftNative)"'
raise SystemExit(0 if needle in text else 1)
PY
then
  fail "BackendConstants.userAgent must derive from BackendConstants.version"
fi

if ! python3 - "$HTTP_REQUEST_BUILDER" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
needle = "static let defaultUserAgent = BackendConstants.userAgent"
raise SystemExit(0 if needle in text else 1)
PY
then
  fail "HTTPRequestBuilder.defaultUserAgent must reuse BackendConstants.userAgent"
fi

if ! python3 - "$BUILD_SCRIPT" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    'VERSION_JSON="$ROOT_DIR/version.json"',
    'VERSION="$(version_json_value version "$VERSION_JSON")"',
]
raise SystemExit(0 if all(item in text for item in required) else 1)
PY
then
  fail "scripts/build_native_dmg.sh must read VERSION from version.json"
fi

readme_version="$(python3 - "$README_FILE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'当前 native 主线版本：`([^`]+)`', text)
if not match:
    raise SystemExit("Missing README current version line")
print(match.group(1))
PY
)"

if [ "$readme_version" != "$json_version" ]; then
  fail "README current version expected $json_version but found $readme_version"
fi

echo "Version drift check passed for $json_version"
