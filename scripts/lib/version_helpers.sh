#!/usr/bin/env bash

version_json_value() {
  local key="$1"
  local version_json_path="$2"

  python3 - "$version_json_path" "$key" <<'PY'
import json
import sys
from pathlib import Path

version_json_path = Path(sys.argv[1])
key = sys.argv[2]

with version_json_path.open(encoding="utf-8") as handle:
    data = json.load(handle)

value = data[key]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("null")
else:
    print(value)
PY
}
