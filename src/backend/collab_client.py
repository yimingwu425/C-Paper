import json
import os
import threading
import time
import requests
from .const import COLLAB_SERVER_URL, CACHE_DIR

class CollabClient:
    def __init__(self, base_url=None):
        self._base_url = base_url or COLLAB_SERVER_URL
        self._token = ""
        self._refresh_token = ""
        self._token_path = os.path.join(CACHE_DIR, "collab_token.json")
        self._session = requests.Session()
        self._session.headers.update({"Content-Type": "application/json"})
        self._load_tokens()

    def _load_tokens(self):
        """Load saved tokens from disk"""
        try:
            if os.path.exists(self._token_path):
                with open(self._token_path, 'r') as f:
                    data = json.load(f)
                    self._token = data.get("access_token", "")
                    self._refresh_token = data.get("refresh_token", "")
        except Exception:
            pass

    def _save_tokens(self):
        """Save tokens to disk"""
        try:
            os.makedirs(os.path.dirname(self._token_path), exist_ok=True)
            with open(self._token_path, 'w') as f:
                json.dump({"access_token": self._token, "refresh_token": self._refresh_token}, f)
        except Exception:
            pass

    def _request(self, method, path, **kwargs):
        """Central HTTP request with auto token refresh"""
        url = self._base_url.rstrip('/') + path
        headers = kwargs.pop("headers", {})
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"

        for attempt in range(2):
            try:
                resp = self._session.request(method, url, headers=headers, timeout=15, **kwargs)
                if resp.status_code == 401 and attempt == 0 and self._refresh_token:
                    if self._refresh():
                        headers["Authorization"] = f"Bearer {self._token}"
                        continue
                if resp.status_code >= 500:
                    return {"ok": False, "error": f"server error ({resp.status_code})"}
                return resp.json()
            except requests.exceptions.ConnectionError:
                return {"ok": False, "error": "无法连接到协作服务器"}
            except requests.exceptions.Timeout:
                return {"ok": False, "error": "请求超时"}
            except Exception as e:
                return {"ok": False, "error": str(e)}
        return {"ok": False, "error": "请求失败"}

    def _refresh(self):
        """Refresh the access token"""
        try:
            resp = self._session.post(
                self._base_url + "/api/auth/refresh",
                json={"refresh_token": self._refresh_token},
                timeout=10
            )
            if resp.status_code == 200:
                data = resp.json()
                self._token = data.get("access_token", "")
                self._refresh_token = data.get("refresh_token", "")
                self._save_tokens()
                return True
        except Exception:
            pass
        return False

    def is_logged_in(self):
        return bool(self._token)

    def register(self, email, password, nickname):
        data = self._request("POST", "/api/auth/register", json={"email": email, "password": password, "nickname": nickname})
        if data.get("access_token"):
            self._token = data["access_token"]
            self._refresh_token = data.get("refresh_token", "")
            self._save_tokens()
        return data

    def login(self, email, password):
        data = self._request("POST", "/api/auth/login", json={"email": email, "password": password})
        if data.get("access_token"):
            self._token = data["access_token"]
            self._refresh_token = data.get("refresh_token", "")
            self._save_tokens()
        return data

    def logout(self):
        self._token = ""
        self._refresh_token = ""
        self._save_tokens()
        return {"ok": True}

    def get_me(self):
        return self._request("GET", "/api/me")

    def update_me(self, nickname=None, avatar_url=None):
        body = {}
        if nickname is not None: body["nickname"] = nickname
        if avatar_url is not None: body["avatar_url"] = avatar_url
        return self._request("PUT", "/api/me", json=body)

    def create_share(self, subject, year, season, paper_type, expiry):
        return self._request("POST", "/api/share", json={
            "subject": subject, "year": int(year), "season": season,
            "paper_type": paper_type, "expiry": expiry
        })

    def get_share(self, code):
        return self._request("GET", f"/api/share/{code}")

    def delete_share(self, code):
        return self._request("DELETE", f"/api/share/{code}")

    def list_my_shares(self):
        return self._request("GET", "/api/share/list")

    def create_group(self, name, description):
        return self._request("POST", "/api/groups", json={"name": name, "description": description})

    def join_group(self, invite_code):
        return self._request("POST", "/api/groups/0/join", json={"invite_code": invite_code})

    def leave_group(self, group_id):
        return self._request("POST", f"/api/groups/{group_id}/leave")

    def list_groups(self):
        return self._request("GET", "/api/groups")

    def get_group(self, group_id):
        return self._request("GET", f"/api/groups/{group_id}")

    def add_group_paper(self, group_id, subject, year, season, paper_type, filename, download_url):
        return self._request("POST", f"/api/groups/{group_id}/papers", json={
            "subject": subject, "year": int(year), "season": season,
            "paper_type": paper_type, "filename": filename, "download_url": download_url
        })

    def remove_group_paper(self, group_id, paper_id):
        return self._request("DELETE", f"/api/groups/{group_id}/papers/{paper_id}")

    def get_progress(self, group_id):
        return self._request("GET", f"/api/groups/{group_id}/progress")

    def update_progress(self, group_id, group_paper_id, status):
        return self._request("POST", f"/api/groups/{group_id}/progress", json={
            "group_paper_id": int(group_paper_id), "status": status
        })

    def create_review(self, subject, year, season, paper_type, filename, rating, difficulty, tags, comment):
        return self._request("POST", "/api/reviews", json={
            "subject": subject, "year": int(year), "season": season,
            "paper_type": paper_type, "filename": filename,
            "rating": int(rating), "difficulty": int(difficulty),
            "tags": tags if isinstance(tags, list) else [], "comment": comment
        })

    def list_reviews(self, subject="", year=0, season=""):
        params = {}
        if subject: params["subject"] = subject
        if year: params["year"] = str(year)
        if season: params["season"] = season
        return self._request("GET", "/api/reviews", params=params)

    def get_review_stats(self, subject):
        return self._request("GET", "/api/reviews/stats", params={"subject": subject})

    def delete_review(self, review_id):
        return self._request("DELETE", f"/api/reviews/{review_id}")

    def subscribe_group_events(self, group_id, callback):
        """Subscribe to SSE events for a group. Returns a daemon thread."""
        def _listen():
            url = f"{self._base_url}/api/groups/{group_id}/events"
            headers = {"Accept": "text/event-stream", "Authorization": f"Bearer {self._token}"}
            try:
                resp = self._session.get(url, headers=headers, stream=True, timeout=None)
                for line in resp.iter_lines(decode_unicode=True):
                    if line and line.startswith("data: "):
                        try:
                            data = json.loads(line[6:])
                            callback(data)
                        except Exception:
                            pass
            except Exception:
                pass

        t = threading.Thread(target=_listen, daemon=True)
        t.start()
        return t
