import io

import pytest

from backend.engine import DownloadEngine


class FakeResponse:
    def __init__(self, raw):
        self.raw = raw

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def raise_for_status(self):
        return None


class FakeSession:
    def __init__(self, response):
        self.response = response

    def get(self, url, timeout, stream):
        return self.response


class FailingRaw:
    def __init__(self, first_chunk=b"%PDF-partial"):
        self._first_chunk = first_chunk
        self._reads = 0

    def read(self, size=-1):
        self._reads += 1
        if self._reads == 1:
            return self._first_chunk
        raise OSError("simulated streaming failure")


def _patch_response(monkeypatch, engine, raw):
    session = FakeSession(FakeResponse(raw))
    monkeypatch.setattr(engine, "_get_worker_session", lambda: session)


def _part_files(path):
    return list(path.parent.glob(f"{path.name}.part*"))


def test_successful_download_writes_target_without_temp_leftover(tmp_path, monkeypatch):
    engine = DownloadEngine()
    save_path = tmp_path / "paper.pdf"
    _patch_response(monkeypatch, engine, io.BytesIO(b"%PDF-1.7\ncontent"))

    engine.download_one("paper.pdf", str(save_path))

    assert save_path.read_bytes() == b"%PDF-1.7\ncontent"
    assert _part_files(save_path) == []


def test_midstream_failure_removes_temp_file(tmp_path, monkeypatch):
    engine = DownloadEngine()
    save_path = tmp_path / "paper.pdf"
    _patch_response(monkeypatch, engine, FailingRaw())

    with pytest.raises(OSError, match="simulated streaming failure"):
        engine.download_one("paper.pdf", str(save_path))

    assert not save_path.exists()
    assert _part_files(save_path) == []


def test_midstream_failure_preserves_existing_target(tmp_path, monkeypatch):
    engine = DownloadEngine()
    save_path = tmp_path / "paper.pdf"
    save_path.write_bytes(b"old pdf")
    _patch_response(monkeypatch, engine, FailingRaw())

    with pytest.raises(OSError, match="simulated streaming failure"):
        engine.download_one("paper.pdf", str(save_path))

    assert save_path.read_bytes() == b"old pdf"
    assert _part_files(save_path) == []
