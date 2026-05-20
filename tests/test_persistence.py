import json
import os
import requests
from backend import API


def make_api(tmp_path):
    api = API()
    api._fav_path = os.path.join(tmp_path, "favorites.json")
    api._hist_path = os.path.join(tmp_path, "download_history.json")
    api._settings_path = os.path.join(tmp_path, "settings.json")
    return api


class TestFavorites:
    def test_add_and_get(self, tmp_path):
        api = make_api(tmp_path)
        r = json.loads(api.add_favorite("9709", "Mathematics"))
        assert r["ok"]
        favs = json.loads(api.get_favorites())
        assert len(favs) == 1
        assert favs[0]["code"] == "9709"

    def test_remove(self, tmp_path):
        api = make_api(tmp_path)
        api.add_favorite("9701", "Chemistry")
        api.remove_favorite("9701")
        favs = json.loads(api.get_favorites())
        assert all(f["code"] != "9701" for f in favs)

    def test_no_duplicate(self, tmp_path):
        api = make_api(tmp_path)
        api.add_favorite("9709", "Math")
        api.add_favorite("9709", "Math")
        favs = json.loads(api.get_favorites())
        assert len(favs) == 1


class TestSettings:
    def test_load_defaults(self, tmp_path):
        api = make_api(tmp_path)
        s = json.loads(api.load_settings())
        assert s["theme"] == "light"
        assert s["include_ms"] is True
        assert s["rate"] == 5
        assert s["threads"] == 4
        assert s["dup_mode"] == "overwrite"

    def test_save_and_load(self, tmp_path):
        api = make_api(tmp_path)
        saved = {"theme": "light", "rate": 8, "include_ms": False,
                 "save_dir": "/test", "threads": 6, "merge": True,
                 "proxy_url": "", "last_subject": "", "last_mode": "batch",
                 "dup_mode": "missing"}
        r = json.loads(api.save_settings(json.dumps(saved)))
        assert r["ok"]
        loaded = json.loads(api.load_settings())
        assert loaded["theme"] == "light"
        assert loaded["rate"] == 8
        assert loaded["threads"] == 6
        assert loaded["include_ms"] is False
        assert loaded["dup_mode"] == "missing"


class TestDownloadHistory:
    def test_record_and_check(self, tmp_path):
        api = make_api(tmp_path)
        api._record_one_history("9709_s24_qp_11.pdf", "Paper 1", "2024")
        r = json.loads(api.check_downloaded("9709_s24_qp_11.pdf"))
        assert r["downloaded"] is True
        r2 = json.loads(api.check_downloaded("nonexistent.pdf"))
        assert r2["downloaded"] is False

    def test_clear(self, tmp_path):
        api = make_api(tmp_path)
        api._record_one_history("test.pdf", "P1", "2024")
        api.clear_history()
        hist = json.loads(api.get_download_history())
        assert len(hist) == 0


class TestProxy:
    def test_set_and_get(self, tmp_path):
        api = make_api(tmp_path)
        r = json.loads(api.set_proxy("http://localhost:8080"))
        assert r["ok"]
        p = json.loads(api.get_proxy())
        assert "localhost:8080" in p["proxy"]

    def test_clear_proxy(self, tmp_path):
        api = make_api(tmp_path)
        api.set_proxy("")
        p = json.loads(api.get_proxy())
        assert p["proxy"] == ""

    def test_test_proxy_fails_gracefully(self, tmp_path, monkeypatch):
        api = make_api(tmp_path)

        def fail_post(*args, **kwargs):
            raise requests.exceptions.ProxyError("proxy unavailable")

        monkeypatch.setattr(api, "test_proxy", API.test_proxy.__get__(api, API))
        monkeypatch.setattr("backend.api.create_session", lambda proxy_url, max_retries=0: type("S", (), {"post": fail_post})())
        r = json.loads(api.test_proxy("http://nonexistent.local:1"))
        assert not r["ok"]  # should fail gracefully
