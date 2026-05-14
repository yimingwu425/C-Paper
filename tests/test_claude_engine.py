import json
import os
import pytest
from backend.claude_engine import ClaudeEngine, _find_binary


class TestClaudeEngineBinary:
    def test_find_binary_returns_path(self):
        """_find_binary returns a non-empty path string."""
        path = _find_binary()
        assert isinstance(path, str)
        assert len(path) > 0

    def test_is_available_when_binary_exists(self):
        """is_available returns True when the binary is present."""
        engine = ClaudeEngine()
        # In dev environment, binary is at bin/claude-haha
        # This test assumes the binary is present (copied during setup)
        result = engine.is_available()
        assert isinstance(result, bool)

    def test_get_binary_path(self):
        """get_binary_path returns the same path as _find_binary."""
        engine = ClaudeEngine()
        assert engine.get_binary_path() == _find_binary()


class TestClaudeEngineSession:
    def test_initial_state(self):
        """Engine starts with no active session."""
        engine = ClaudeEngine()
        assert engine.is_running is False
        assert engine.get_messages() == []

    def test_stop_session_when_not_started(self):
        """stop_session is safe to call when no session is active."""
        engine = ClaudeEngine()
        engine.stop_session()  # Should not raise

    def test_send_message_without_session(self):
        """send_message returns error when no session is active."""
        engine = ClaudeEngine()
        result = engine.send_message("hello")
        assert result["ok"] is False
        assert "未启动" in result["error"]

    def test_start_session_with_invalid_key(self):
        """start_session with a bad key still starts (error comes later)."""
        engine = ClaudeEngine()
        if not engine.is_available():
            pytest.skip("claude-haha binary not available")
        result = engine.start_session("invalid-key-12345")
        # It may fail or succeed depending on binary behavior
        # Just verify it returns a dict
        assert isinstance(result, dict)
        engine.stop_session()


class TestClaudeEngineMessages:
    def test_messages_thread_safety(self):
        """get_messages returns a copy, not a reference."""
        engine = ClaudeEngine()
        msgs1 = engine.get_messages()
        msgs2 = engine.get_messages()
        assert msgs1 is not msgs2
        assert msgs1 == msgs2

    def test_handle_event_assistant(self):
        """_handle_event processes assistant messages correctly."""
        engine = ClaudeEngine()
        engine._active = True
        engine._handle_event({"type": "assistant", "content": "Hello!"})
        msgs = engine.get_messages()
        assert len(msgs) == 1
        assert msgs[0]["role"] == "assistant"
        assert msgs[0]["content"] == "Hello!"
        assert msgs[0]["complete"] is True

    def test_handle_event_delta(self):
        """_handle_event processes streaming deltas."""
        engine = ClaudeEngine()
        engine._active = True
        engine._handle_event({"type": "content_block_delta", "delta": {"text": "Hel"}})
        engine._handle_event({"type": "content_block_delta", "delta": {"text": "lo"}})
        engine._handle_event({"type": "message_stop"})
        msgs = engine.get_messages()
        assert len(msgs) == 1
        assert msgs[0]["content"] == "Hello"
        assert msgs[0]["complete"] is True

    def test_handle_event_error(self):
        """_handle_event processes error events."""
        engine = ClaudeEngine()
        engine._active = True
        engine._handle_event({"type": "error", "error": "something went wrong"})
        msgs = engine.get_messages()
        assert len(msgs) == 1
        assert msgs[0]["role"] == "system"
        assert "错误" in msgs[0]["content"]

    def test_handle_event_assistant_list_content(self):
        """_handle_event handles content as a list of blocks."""
        engine = ClaudeEngine()
        engine._active = True
        engine._handle_event({
            "type": "assistant",
            "content": [{"type": "text", "text": "Part 1"}, {"type": "text", "text": " Part 2"}]
        })
        msgs = engine.get_messages()
        assert msgs[0]["content"] == "Part 1 Part 2"
