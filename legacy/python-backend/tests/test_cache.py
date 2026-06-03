import json
import os

from backend.cache import read_json, write_json


def corrupt_backups(path):
    return list(path.parent.glob(f"{path.name}.corrupt.*"))


def test_read_json_returns_default_and_moves_corrupt_json(tmp_path):
    path = tmp_path / "data.json"
    path.write_text("{not valid json", encoding="utf-8")

    assert read_json(str(path), {"ok": False}) == {"ok": False}

    backups = corrupt_backups(path)
    assert len(backups) == 1
    assert backups[0].read_text(encoding="utf-8") == "{not valid json"
    assert not path.exists()


def test_read_json_returns_default_and_moves_empty_file(tmp_path):
    path = tmp_path / "empty.json"
    path.write_text("", encoding="utf-8")

    assert read_json(str(path), []) == []

    backups = corrupt_backups(path)
    assert len(backups) == 1
    assert backups[0].read_text(encoding="utf-8") == ""
    assert not path.exists()


def test_read_json_returns_normal_json(tmp_path):
    path = tmp_path / "data.json"
    path.write_text(json.dumps({"ok": True}), encoding="utf-8")

    assert read_json(str(path), {"ok": False}) == {"ok": True}
    assert corrupt_backups(path) == []


def test_write_json_writes_path_without_directory(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)

    write_json("data.json", {"ok": True})

    assert json.loads((tmp_path / "data.json").read_text(encoding="utf-8")) == {"ok": True}
    assert not os.path.exists("data.json.tmp")


def test_write_json_writes_path_with_directory(tmp_path):
    path = tmp_path / "nested" / "data.json"

    write_json(str(path), {"ok": True})

    assert json.loads(path.read_text(encoding="utf-8")) == {"ok": True}
    assert not path.with_name("data.json.tmp").exists()
