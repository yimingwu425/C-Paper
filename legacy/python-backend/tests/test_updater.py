import os

import pytest

from backend import updater
from backend.cache import read_json, write_json


class TestVersionParse:
    def test_parse_simple(self):
        assert updater._parse_version("5.2.0") == (5, 2, 0)

    def test_parse_with_v(self):
        assert updater._parse_version("v5.2.0") == (5, 2, 0)

    def test_parse_minor_only_pads_patch(self):
        assert updater._parse_version("5.3") == (5, 3, 0)

    def test_parse_prerelease_uses_base_version(self):
        assert updater._parse_version("5.3.0-beta") == (5, 3, 0)

    def test_parse_invalid_returns_zero_tuple(self):
        assert updater._parse_version("not-a-version") == (0, 0, 0)

    def test_version_gte(self):
        assert updater._version_gte("5.2.0", "5.1.0") is True
        assert updater._version_gte("5.1.0", "5.2.0") is False
        assert updater._version_gte("5.1.0", "5.1.0") is True
        assert updater._version_gte("5.3", "5.3.0-beta") is True


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

    def test_non_dict_state_returns_true(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        write_json(str(tmp_path / "update.json"), ["not", "a", "dict"])
        assert updater._should_check() is True


class TestCheckUpdate:
    def test_non_dict_version_info_returns_error(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        monkeypatch.setattr(updater, "_fetch_version_json", lambda: None)

        result = updater.check_update(force=True)

        assert result == {"ok": False, "error": "无法获取版本信息", "has_update": False}

    def test_missing_version_returns_no_update(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        monkeypatch.setattr(updater, "_fetch_version_json", lambda: {"download_url": "https://example.test"})

        result = updater.check_update(force=True)

        assert result["ok"] is True
        assert result["has_update"] is False
        assert result["latest_version"] == ""

    def test_non_dict_state_does_not_crash(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        write_json(str(tmp_path / "update.json"), "bad-state")
        monkeypatch.setattr(updater, "_fetch_version_json", lambda: None)

        result = updater.check_update(force=True)

        assert result == {"ok": False, "error": "无法获取版本信息", "has_update": False}

    def test_version_json_update_is_detected(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))
        monkeypatch.chdir(tmp_path)
        (tmp_path / "version.json").write_text(
            '{"version":"5.9.0","download_url":"https://example.test","release_notes":"notes","force_update":false}',
            encoding="utf-8",
        )

        result = updater.check_update(force=True)

        assert result["ok"] is True
        assert result["has_update"] is True
        assert result["latest_version"] == "5.9.0"


class TestSkipVersion:
    @pytest.mark.parametrize("version", ["5.3", "v5.3.0"])
    def test_skip_version_normalizes_parseable_version(self, tmp_path, monkeypatch, version):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))

        updater.skip_version(version)

        assert read_json(str(tmp_path / "update.json"))["skipped_version"] == "5.3.0"

    def test_skip_version_rejects_invalid_version(self, tmp_path, monkeypatch):
        monkeypatch.setattr(updater, "UPDATE_STATE_PATH", str(tmp_path / "update.json"))

        updater.skip_version("latest")

        assert read_json(str(tmp_path / "update.json")) is None
