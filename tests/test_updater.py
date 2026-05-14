import os

import pytest

from backend import updater
from backend.cache import write_json


class TestVersionParse:
    def test_parse_simple(self):
        assert updater._parse_version("5.2.0") == (5, 2, 0)

    def test_parse_with_v(self):
        assert updater._parse_version("v5.2.0") == (5, 2, 0)

    def test_version_gte(self):
        assert updater._version_gte("5.2.0", "5.1.0") is True
        assert updater._version_gte("5.1.0", "5.2.0") is False
        assert updater._version_gte("5.1.0", "5.1.0") is True


class TestShouldCheck:
    def test_no_state_returns_true(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        assert updater._should_check() is True

    def test_disabled_returns_false(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        write_json(str(tmp_path / "update.json"), {"check_enabled": False})
        assert updater._should_check() is False

    def test_recent_check_returns_false(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        from datetime import datetime, timezone
        write_json(str(tmp_path / "update.json"), {
            "check_enabled": True,
            "last_check": datetime.now(timezone.utc).isoformat()
        })
        assert updater._should_check() is False
