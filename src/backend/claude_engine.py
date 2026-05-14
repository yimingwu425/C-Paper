"""Claude Code Haha engine — spawns cc-haha as a subprocess for AI conversations."""

import json
import os
import subprocess
import sys
import threading
import time
import uuid


def _find_binary():
    """Locate the claude-haha binary."""
    if getattr(sys, '_MEIPASS', None):
        path = os.path.join(sys._MEIPASS, 'bin', 'claude-haha')
    else:
        base = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        path = os.path.join(base, 'bin', 'claude-haha')
    if sys.platform == 'win32':
        path += '.exe'
    return path


class ClaudeEngine:
    """Manages a Claude Code Haha subprocess for AI conversations."""

    def __init__(self):
        self._binary = _find_binary()
        self._process = None
        self._session_id = None
        self._messages = []
        self._lock = threading.Lock()
        self._reader_thread = None
        self._active = False

    def is_available(self):
        """Check if the binary exists and is executable."""
        return os.path.isfile(self._binary) and os.access(self._binary, os.X_OK)

    def get_binary_path(self):
        return self._binary

    def start_session(self, api_key):
        """Start a cc-haha subprocess with the given DeepSeek API key."""
        if self._process:
            self.stop_session()

        self._session_id = str(uuid.uuid4())
        self._messages = []
        self._active = True

        env = os.environ.copy()
        env["ANTHROPIC_AUTH_TOKEN"] = api_key
        env["ANTHROPIC_BASE_URL"] = "https://api.deepseek.com/anthropic"

        cmd = [
            self._binary, "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-mode", "bypassPermissions",
            "--session-id", self._session_id,
            "--model", "deepseek-v4-pro",
        ]

        try:
            self._process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
        except FileNotFoundError:
            return {"ok": False, "error": f"找不到 Claude Code 引擎: {self._binary}"}
        except Exception as e:
            return {"ok": False, "error": str(e)}

        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()
        return {"ok": True, "session_id": self._session_id}

    def send_message(self, message):
        """Send a user message to the subprocess stdin."""
        if not self._process or not self._active:
            return {"ok": False, "error": "会话未启动"}

        with self._lock:
            self._messages.append({
                "role": "user",
                "content": message,
                "complete": True,
                "timestamp": time.time(),
            })

        try:
            payload = json.dumps({"type": "user_message", "content": message}) + "\n"
            self._process.stdin.write(payload.encode())
            self._process.stdin.flush()
        except (BrokenPipeError, OSError) as e:
            self._active = False
            return {"ok": False, "error": f"发送失败: {e}"}

        return {"ok": True}

    def get_messages(self):
        """Return all messages in the current session."""
        with self._lock:
            return list(self._messages)

    def stop_session(self):
        """Terminate the subprocess."""
        self._active = False
        if self._process:
            try:
                self._process.stdin.close()
            except Exception:
                pass
            try:
                self._process.terminate()
                self._process.wait(timeout=5)
            except Exception:
                try:
                    self._process.kill()
                except Exception:
                    pass
            self._process = None

    @property
    def is_running(self):
        return self._process is not None and self._process.poll() is None and self._active

    def _read_loop(self):
        """Background thread: read NDJSON from stdout line by line."""
        try:
            for line in self._process.stdout:
                if not self._active:
                    break
                line = line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    self._handle_event(data)
                except json.JSONDecodeError:
                    continue
        except Exception:
            pass
        finally:
            self._active = False

    def _handle_event(self, data):
        """Process a cc-haha stream event."""
        event_type = data.get("type", "")

        with self._lock:
            if event_type in ("assistant", "assistant_message"):
                content = data.get("content", "") or data.get("message", "")
                if isinstance(content, list):
                    # content might be a list of content blocks
                    content = "".join(
                        b.get("text", "") for b in content if isinstance(b, dict)
                    )
                self._messages.append({
                    "role": "assistant",
                    "content": content,
                    "complete": True,
                    "timestamp": time.time(),
                })

            elif event_type in ("content_block_delta", "assistant_message_delta"):
                delta = data.get("delta", {})
                text = delta.get("text", "") if isinstance(delta, dict) else str(delta)
                if not text:
                    text = data.get("content", "")

                if self._messages and self._messages[-1].get("streaming"):
                    self._messages[-1]["content"] += text
                else:
                    self._messages.append({
                        "role": "assistant",
                        "content": text,
                        "streaming": True,
                        "complete": False,
                        "timestamp": time.time(),
                    })

            elif event_type in ("message_stop", "assistant_message_complete"):
                if self._messages and self._messages[-1].get("streaming"):
                    self._messages[-1]["streaming"] = False
                    self._messages[-1]["complete"] = True

            elif event_type == "error":
                error_msg = data.get("error", data.get("message", "未知错误"))
                self._messages.append({
                    "role": "system",
                    "content": f"错误: {error_msg}",
                    "complete": True,
                    "timestamp": time.time(),
                })
