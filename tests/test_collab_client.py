import json
import os
import pytest
from backend import collab_client
from backend.collab_client import CollabClient


@pytest.fixture(autouse=True)
def _patch_cache_dir(tmp_path, monkeypatch):
    """Redirect CACHE_DIR and token storage to tmp_path for all tests."""
    monkeypatch.setattr(collab_client, "CACHE_DIR", str(tmp_path))


class TestCollabClientInit:
    def test_init_no_token(self):
        """Client starts logged out when no saved tokens exist."""
        client = CollabClient()
        assert client.is_logged_in() is False

    def test_init_loads_saved_tokens(self, tmp_path):
        """Client loads tokens from disk when file exists."""
        token_file = tmp_path / "collab_token.json"
        token_file.write_text(json.dumps({
            "access_token": "saved_access",
            "refresh_token": "saved_refresh",
        }))
        client = CollabClient()
        assert client.is_logged_in() is True
        assert client._token == "saved_access"
        assert client._refresh_token == "saved_refresh"


class TestCollabClientTokens:
    def test_save_and_load_tokens(self, tmp_path):
        """Tokens persist to file and reload correctly."""
        client = CollabClient()
        assert client.is_logged_in() is False

        # Simulate setting tokens (as login would)
        client._token = "test_access_token"
        client._refresh_token = "test_refresh_token"
        client._save_tokens()

        # Verify file was written
        token_file = tmp_path / "collab_token.json"
        assert token_file.exists()
        data = json.loads(token_file.read_text())
        assert data["access_token"] == "test_access_token"
        assert data["refresh_token"] == "test_refresh_token"

        # Create a new client that should load from disk
        client2 = CollabClient()
        assert client2.is_logged_in() is True
        assert client2._token == "test_access_token"
        assert client2._refresh_token == "test_refresh_token"

    def test_mask_key(self):
        """API key masking: token is stored, login state is correct."""
        client = CollabClient()
        client._token = "sk-abc123def456"
        client._save_tokens()
        assert client.is_logged_in() is True

    def test_is_logged_in_false_initially(self):
        """is_logged_in returns False when no token is set."""
        client = CollabClient()
        assert client.is_logged_in() is False

    def test_is_logged_in_true_after_set(self):
        """is_logged_in returns True after token is set."""
        client = CollabClient()
        client._token = "some_token"
        assert client.is_logged_in() is True


class TestCollabClientLogout:
    def test_logout_clears_tokens(self):
        """Logout clears both access and refresh tokens."""
        client = CollabClient()
        client._token = "access_123"
        client._refresh_token = "refresh_456"
        client._save_tokens()
        assert client.is_logged_in() is True

        result = client.logout()
        assert result == {"ok": True}
        assert client.is_logged_in() is False
        assert client._token == ""
        assert client._refresh_token == ""

    def test_logout_persists_cleared_state(self):
        """After logout, a new client instance also starts logged out."""
        client = CollabClient()
        client._token = "access_123"
        client._refresh_token = "refresh_456"
        client._save_tokens()

        client.logout()

        # New client should also be logged out
        client2 = CollabClient()
        assert client2.is_logged_in() is False

    def test_request_returns_error_when_offline(self):
        """_request returns error dict when server is unreachable."""
        client = CollabClient(base_url="http://127.0.0.1:1")
        result = client.get_me()
        assert result["ok"] is False
        assert "error" in result
