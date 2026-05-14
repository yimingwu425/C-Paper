"""Cache and persistence helpers"""
import json
import logging
import os
import time

from .const import CACHE_DIR, CACHE_MAX, CACHE_TTL

logger = logging.getLogger(__name__)


def read_json(path, default=None):
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            logger.warning("Failed to read JSON from %s", path, exc_info=True)
    return default


def write_json(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        logger.error("Failed to write JSON to %s", path, exc_info=True)


def load_cache(key):
    p = os.path.join(CACHE_DIR, f"{key}.json")
    if not os.path.exists(p):
        return None
    try:
        if time.time() - os.path.getmtime(p) > CACHE_TTL:
            os.remove(p)
            return None
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        logger.warning("Failed to load cache for key %s", key, exc_info=True)
        return None


def _cleanup_cache_directory():
    try:
        files = [os.path.join(CACHE_DIR, f) for f in os.listdir(CACHE_DIR) if f.endswith(".json")]
        files.sort(key=os.path.getmtime)  # LRU: oldest first
        return files
    except OSError:
        return []


def save_cache(key, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        files = _cleanup_cache_directory()
        while len(files) >= CACHE_MAX:
            try:
                os.remove(files.pop(0))
            except OSError:
                pass
        path = os.path.join(CACHE_DIR, f"{key}.json")
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        logger.error("Failed to save cache for key %s", key, exc_info=True)
