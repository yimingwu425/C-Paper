import json, tempfile, os, shutil
import pytest
from backend import API


class TestFavorites:
    def test_add_and_get(self):
        api = API()
        # Clean start
        open(api._fav_path, 'w').close()
        r = json.loads(api.add_favorite("9709", "Mathematics"))
        assert r["ok"]
        favs = json.loads(api.get_favorites())
        assert len(favs) == 1
        assert favs[0]["code"] == "9709"

    def test_remove(self):
        api = API()
        api.add_favorite("9701", "Chemistry")
        api.remove_favorite("9701")
        favs = json.loads(api.get_favorites())
        assert all(f["code"] != "9701" for f in favs)

    def test_no_duplicate(self):
        api = API()
        open(api._fav_path, 'w').close()
        api.add_favorite("9709", "Math")
        api.add_favorite("9709", "Math")
        favs = json.loads(api.get_favorites())
        assert len(favs) == 1


class TestSettings:
    def test_load_defaults(self):
        api = API()
        # Remove any stale settings file from prior test runs
        if os.path.exists(api._settings_path):
            os.remove(api._settings_path)
        s = json.loads(api.load_settings())
        assert s["theme"] == "light"
        assert s["include_ms"] is True
        assert s["rate"] == 5
        assert s["threads"] == 4

    def test_save_and_load(self):
        api = API()
        saved = {"theme": "light", "rate": 8, "include_ms": False,
                 "save_dir": "/test", "threads": 6, "merge": True,
                 "proxy_url": "", "last_subject": "", "last_mode": "batch"}
        r = json.loads(api.save_settings(json.dumps(saved)))
        assert r["ok"]
        loaded = json.loads(api.load_settings())
        assert loaded["theme"] == "light"
        assert loaded["rate"] == 8
        assert loaded["threads"] == 6
        assert loaded["include_ms"] is False


class TestDownloadHistory:
    def test_record_and_check(self):
        api = API()
        open(api._hist_path, 'w').close()
        api._record_one_history("9709_s24_qp_11.pdf", "Paper 1", "2024")
        r = json.loads(api.check_downloaded("9709_s24_qp_11.pdf"))
        assert r["downloaded"] is True
        r2 = json.loads(api.check_downloaded("nonexistent.pdf"))
        assert r2["downloaded"] is False

    def test_clear(self):
        api = API()
        api._record_one_history("test.pdf", "P1", "2024")
        api.clear_history()
        hist = json.loads(api.get_download_history())
        assert len(hist) == 0


class TestProxy:
    def test_set_and_get(self):
        api = API()
        r = json.loads(api.set_proxy("http://localhost:8080"))
        assert r["ok"]
        p = json.loads(api.get_proxy())
        assert "localhost:8080" in p["proxy"]

    def test_clear_proxy(self):
        api = API()
        api.set_proxy("")
        p = json.loads(api.get_proxy())
        assert p["proxy"] == ""

    def test_test_proxy_fails_gracefully(self):
        api = API()
        r = json.loads(api.test_proxy("http://nonexistent.local:1"))
        assert not r["ok"]  # should fail gracefully
