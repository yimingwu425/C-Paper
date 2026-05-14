"""Auto-update checker — GitHub Releases API with version.json fallback"""
import json
import logging
from datetime import datetime, timezone

import requests

from .cache import read_json, write_json
from .const import UPDATE_STATE_PATH, VERSION

logger = logging.getLogger(__name__)

GITHUB_API_URL = "https://api.github.com/repos/Ja-son-WU/CIE-Downloader/releases/latest"
VERSION_JSON_URL = "https://raw.githubusercontent.com/Ja-son-WU/CIE-Downloader/main/version.json"


def _parse_version(v: str):
    """Parse '5.2.0' or 'v5.2.0' into (5, 2, 0) tuple."""
    return tuple(int(x) for x in v.lstrip("v").split(".")[:3])


def _version_gte(v1: str, v2: str) -> bool:
    return _parse_version(v1) >= _parse_version(v2)


def _should_check() -> bool:
    state = read_json(UPDATE_STATE_PATH, {})
    if not state.get("check_enabled", True):
        return False
    last = state.get("last_check", "")
    if not last:
        return True
    try:
        last_dt = datetime.fromisoformat(last)
        return (datetime.now(timezone.utc) - last_dt).total_seconds() > 86400
    except ValueError:
        return True


def _fetch_github() -> dict | None:
    try:
        resp = requests.get(GITHUB_API_URL, timeout=(5, 10), headers={"Accept": "application/vnd.github+json"})
        if resp.status_code == 200:
            data = resp.json()
            return {
                "version": data.get("tag_name", "").lstrip("v"),
                "download_url": data.get("html_url", ""),
                "release_notes": data.get("body", ""),
                "force_update": False,
                "published_at": data.get("published_at", ""),
            }
        logger.warning("GitHub API returned %s", resp.status_code)
    except Exception as e:
        logger.warning("GitHub API request failed: %s", e)
    return None


def _fetch_version_json() -> dict | None:
    try:
        resp = requests.get(VERSION_JSON_URL, timeout=(5, 10))
        if resp.status_code == 200:
            return resp.json()
    except Exception as e:
        logger.warning("version.json request failed: %s", e)
    return None


def check_update(force: bool = False) -> dict:
    """Check for updates. Returns dict with ok/has_update/etc."""
    if not force and not _should_check():
        return {"ok": True, "has_update": False, "message": "已是最新版或今日已检查"}

    state = read_json(UPDATE_STATE_PATH, {})
    skipped = state.get("skipped_version", "")

    info = _fetch_github()
    if info is None:
        info = _fetch_version_json()

    state["last_check"] = datetime.now(timezone.utc).isoformat()
    write_json(UPDATE_STATE_PATH, state)

    if info is None:
        return {"ok": False, "error": "无法获取版本信息", "has_update": False}

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
    state = read_json(UPDATE_STATE_PATH, {})
    state["skipped_version"] = version
    write_json(UPDATE_STATE_PATH, state)


def set_update_check(enabled: bool):
    state = read_json(UPDATE_STATE_PATH, {})
    state["check_enabled"] = enabled
    write_json(UPDATE_STATE_PATH, state)
