"""Auto-update checker — version.json driven update metadata"""
import json
import logging
import re
from datetime import datetime, timezone

from .cache import read_json, write_json
from .const import UPDATE_STATE_PATH, VERSION

logger = logging.getLogger(__name__)

def _parse_version(v: str):
    """Parse '5.2.0' or 'v5.2.0' into (5, 2, 0) tuple. Returns (0,0,0) for invalid input."""
    if not isinstance(v, str):
        return (0, 0, 0)
    match = re.match(r"^v?(\d+)\.(\d+)(?:\.(\d+))?(?:[-+].*)?$", v.strip(), re.IGNORECASE)
    if not match:
        return (0, 0, 0)
    return tuple(int(part) if part is not None else 0 for part in match.groups())


def _normalize_version(v: str) -> str | None:
    parsed = _parse_version(v)
    if parsed == (0, 0, 0):
        return None
    return ".".join(str(part) for part in parsed)


def _version_gte(v1: str, v2: str) -> bool:
    return _parse_version(v1) >= _parse_version(v2)


def _read_state() -> dict:
    state = read_json(UPDATE_STATE_PATH, {})
    return state if isinstance(state, dict) else {}


def _should_check() -> bool:
    state = _read_state()
    if not state.get("check_enabled", True):
        return False
    last = state.get("last_check", "")
    if not last:
        return True
    try:
        last_dt = datetime.fromisoformat(last)
        if last_dt.tzinfo is None:
            last_dt = last_dt.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - last_dt).total_seconds() > 86400
    except ValueError:
        return True


def _fetch_version_json() -> dict | None:
    try:
        with open("version.json", "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except Exception as e:
        logger.warning("version.json read failed: %s", e)
    return None


def check_update(force: bool = False) -> dict:
    """Check for updates. Returns dict with ok/has_update/etc."""
    if not force and not _should_check():
        return {"ok": True, "has_update": False, "message": "已是最新版或今日已检查"}

    state = _read_state()
    skipped = state.get("skipped_version", "")

    info = _fetch_version_json()

    state["last_check"] = datetime.now(timezone.utc).isoformat()
    write_json(UPDATE_STATE_PATH, state)

    if info is None:
        return {"ok": False, "error": "无法获取版本信息", "has_update": False}
    if not isinstance(info, dict):
        return {"ok": False, "error": "版本信息格式无效", "has_update": False}

    latest = info.get("version", "")
    if not latest or _version_gte(VERSION, latest):
        return {"ok": True, "has_update": False, "latest_version": latest}

    if skipped and _version_gte(skipped, latest):
        return {"ok": True, "has_update": False, "message": "已跳过此版本"}

    return {
        "ok": True,
        "has_update": True,
        "current_version": VERSION,
        "latest_version": latest,
        "download_url": info.get("download_url", ""),
        "release_notes": info.get("release_notes", ""),
        "force_update": info.get("force_update", False),
    }


def skip_version(version: str):
    normalized = _normalize_version(version)
    if normalized is None:
        logger.warning("Invalid version format in skip_version: %s", version)
        return
    state = _read_state()
    state["skipped_version"] = normalized
    write_json(UPDATE_STATE_PATH, state)


def set_update_check(enabled: bool):
    state = _read_state()
    state["check_enabled"] = enabled
    write_json(UPDATE_STATE_PATH, state)
