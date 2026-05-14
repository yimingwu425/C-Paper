# C-Paper v5.2 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 C-Paper 添加自动更新检查与插件扩展系统

**Architecture:** 后端新增 `updater.py`（GitHub API + version.json fallback）和 `plugin_manager.py`（Python Hook + 外部命令双模式），通过 `api.py` 暴露给前端；前端在设置面板新增插件管理区域和更新提示 Toast。

**Tech Stack:** Python 3.11, pywebview, Vanilla JS, CSS3, requests, concurrent.futures, subprocess, webbrowser

---

## 关键设计决策（审查后修订）

1. **Hook 分发不侵入 except 块**：`on_download_failed` 在 worker 的 `finally` 块中根据 return 值统一分发，避免 4 个 except 块重复。
2. **`on_batch_complete` 在 `_run_downloads` 末尾分发**：所有重试轮次结束后、设置 `phase="done"` 之前。
3. **打开 URL 走 Python 端**：pywebview 中 `window.open()` 不可靠，用 `webbrowser.open()` 替代，新增 `open_url()` API 方法。
4. **`engine.py` 不单独修改**：hook 分发在 `api.py` 的 worker 层面完成，底层引擎保持纯净。

---

## 文件结构

| 文件 | 职责 | 操作 |
|---|---|---|
| `src/backend/const.py` | 新增 `PLUGINS_DIR`、`UPDATE_STATE_PATH` 常量；更新 `VERSION` | 修改 |
| `src/backend/updater.py` | 自动更新检查：GitHub API 请求、版本比对、状态持久化 | **新增** |
| `src/backend/plugin_manager.py` | 插件扫描、加载、事件分发、启用/禁用管理 | **新增** |
| `src/backend/api.py` | 暴露 `check_update`、`open_url`、`get_plugins`、`toggle_plugin` 等接口；初始化 PluginManager；在 worker 和 `_run_downloads` 中集成 hook | 修改 |
| `src/ui_v2.html` | 新增更新提示 Toast、插件设置区域 | 修改 |
| `src/ui_v2.js` | 新增更新检查、插件管理相关逻辑；`doInit()` 中调用更新检查和插件加载 | 修改 |
| `src/ui_v2.css` | 新增插件卡片、更新提示样式 | 修改 |
| `version.json` | 仓库根目录版本信息（fallback） | **新增** |
| `tests/test_updater.py` | updater 单元测试 | **新增** |
| `tests/test_plugin_manager.py` | plugin_manager 单元测试 | **新增** |

---

## Task 1: 基础常量与版本文件

**Files:**
- Modify: `src/backend/const.py`
- Create: `version.json`

- [ ] **Step 1: 修改 `const.py` 新增常量**

在 `const.py` 中，将 `VERSION = "5.1"` 改为 `VERSION = "5.2.0"`，并在末尾添加：

```python
PLUGINS_DIR = os.path.join(CACHE_DIR, "plugins")
UPDATE_STATE_PATH = os.path.join(CACHE_DIR, "update_state.json")
```

- [ ] **Step 2: 创建 `version.json`**

```json
{
  "version": "5.2.0",
  "min_version": "5.0.0",
  "download_url": "https://github.com/Ja-son-WU/CIE-Downloader/releases/tag/v5.2.0",
  "release_notes": "- 新增插件系统\n- 新增自动更新检查",
  "force_update": false,
  "published_at": "2026-05-13T00:00:00Z"
}
```

- [ ] **Step 3: Commit**

```bash
git add src/backend/const.py version.json
git commit -m "chore: add version constants, update_state path, and version.json"
```

---

## Task 2: 自动更新模块 (updater.py)

**Files:**
- Create: `src/backend/updater.py`
- Create: `tests/test_updater.py`

- [ ] **Step 1: 编写 `updater.py`**

```python
"""Auto-update checker — GitHub Releases API with version.json fallback"""
import json
import logging
from datetime import datetime, timezone

import requests

from .cache import read_json, write_json
from .const import UPDATE_STATE_PATH, VERSION

logger = logging.getLogger(__name__)

GITHUB_API_URL = "https://api.github.com/repos/Ja-son-WU/CIE-Downloader/releases/latest"
VERSION_JSON_URL = "https://raw.githubusercontent.com/Ja-son-WU/CIE-Downloader/main/version.json"


def _parse_version(v: str):
    """Parse '5.2.0' or 'v5.2.0' into (5, 2, 0) tuple."""
    return tuple(int(x) for x in v.lstrip("v").split(".")[:3])


def _version_gte(v1: str, v2: str) -> bool:
    return _parse_version(v1) >= _parse_version(v2)


def _should_check() -> bool:
    state = read_json(UPDATE_STATE_PATH, {})
    if not state.get("check_enabled", True):
        return False
    last = state.get("last_check", "")
    if not last:
        return True
    try:
        last_dt = datetime.fromisoformat(last)
        return (datetime.now(timezone.utc) - last_dt).total_seconds() > 86400
    except ValueError:
        return True


def _fetch_github() -> dict | None:
    try:
        resp = requests.get(GITHUB_API_URL, timeout=(5, 10), headers={"Accept": "application/vnd.github+json"})
        if resp.status_code == 200:
            data = resp.json()
            return {
                "version": data.get("tag_name", "").lstrip("v"),
                "download_url": data.get("html_url", ""),
                "release_notes": data.get("body", ""),
                "force_update": False,
                "published_at": data.get("published_at", ""),
            }
        logger.warning("GitHub API returned %s", resp.status_code)
    except Exception as e:
        logger.warning("GitHub API request failed: %s", e)
    return None


def _fetch_version_json() -> dict | None:
    try:
        resp = requests.get(VERSION_JSON_URL, timeout=(5, 10))
        if resp.status_code == 200:
            return resp.json()
    except Exception as e:
        logger.warning("version.json request failed: %s", e)
    return None


def check_update(force: bool = False) -> dict:
    """Check for updates. Returns dict with ok/has_update/etc."""
    if not force and not _should_check():
        return {"ok": True, "has_update": False, "message": "已是最新版或今日已检查"}

    state = read_json(UPDATE_STATE_PATH, {})
    skipped = state.get("skipped_version", "")

    info = _fetch_github()
    if info is None:
        info = _fetch_version_json()

    state["last_check"] = datetime.now(timezone.utc).isoformat()
    write_json(UPDATE_STATE_PATH, state)

    if info is None:
        return {"ok": False, "error": "无法获取版本信息", "has_update": False}

    latest = info.get("version", "")
    if not latest or _version_gte(VERSION, latest):
        return {"ok": True, "has_update": False, "latest_version": latest}

    if skipped and _version_gte(skipped, latest):
        return {"ok": True, "has_update": False, "message": "已跳过此版本"}

    return {
        "ok": True,
        "has_update": True,
        "current_version": VERSION,
        "latest_version": latest,
        "download_url": info.get("download_url", ""),
        "release_notes": info.get("release_notes", ""),
        "force_update": info.get("force_update", False),
    }


def skip_version(version: str):
    state = read_json(UPDATE_STATE_PATH, {})
    state["skipped_version"] = version
    write_json(UPDATE_STATE_PATH, state)


def set_update_check(enabled: bool):
    state = read_json(UPDATE_STATE_PATH, {})
    state["check_enabled"] = enabled
    write_json(UPDATE_STATE_PATH, state)
```

- [ ] **Step 2: 编写测试 `tests/test_updater.py`**

```python
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
```

- [ ] **Step 3: 运行测试**

```bash
cd /Users/yimingwu/Documents/C-Paper
python -m pytest tests/test_updater.py -v
```

Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add src/backend/updater.py tests/test_updater.py
git commit -m "feat: add auto-update checker with GitHub API + version.json fallback"
```

---

## Task 3: 插件管理器 (plugin_manager.py)

**Files:**
- Create: `src/backend/plugin_manager.py`
- Create: `tests/test_plugin_manager.py`

- [ ] **Step 1: 编写 `plugin_manager.py`**

```python
"""Plugin Manager — supports Python hooks and external command plugins"""
import importlib.util
import json
import logging
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor

from .cache import read_json, write_json

logger = logging.getLogger(__name__)
PLUGIN_TIMEOUT = 10.0


class Plugin:
    """Represents a loaded plugin."""

    def __init__(self, manifest: dict, plugin_dir: str):
        self.manifest = manifest
        self.plugin_dir = plugin_dir
        self.id = manifest["id"]
        self.name = manifest.get("name", self.id)
        self.version = manifest.get("version", "0.0.0")
        self.author = manifest.get("author", "")
        self.description = manifest.get("description", "")
        self.type = manifest["type"]  # "python" or "command"
        self.entry = manifest["entry"]
        self.hooks = set(manifest.get("hooks", []))
        self.enabled = manifest.get("enabled", True)
        self.config = manifest.get("config", {})
        self._instance = None  # For python plugins

    def _load_python(self):
        entry_path = os.path.join(self.plugin_dir, self.entry)
        if not os.path.exists(entry_path):
            raise FileNotFoundError(f"Plugin entry not found: {entry_path}")
        spec = importlib.util.spec_from_file_location(f"plugin_{self.id}", entry_path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        if not hasattr(mod, "Plugin"):
            raise AttributeError("Python plugin must define a 'Plugin' class")
        self._instance = mod.Plugin(self.config)

    def initialize(self):
        if self.type == "python":
            self._load_python()

    def execute(self, hook_name: str, data: dict) -> dict:
        if hook_name not in self.hooks:
            return {"ok": True, "skipped": True}
        try:
            if self.type == "python":
                if self._instance is None:
                    self.initialize()
                handler = getattr(self._instance, hook_name, None)
                if handler is None:
                    return {"ok": False, "error": f"Handler {hook_name} not found"}
                return handler(data) or {"ok": True}
            else:
                # Command plugin
                entry_path = os.path.join(self.plugin_dir, self.entry)
                if not os.path.exists(entry_path):
                    return {"ok": False, "error": f"Entry not found: {entry_path}"}
                payload = json.dumps({"event": hook_name, "data": data}, ensure_ascii=False)
                result = subprocess.run(
                    [entry_path],
                    input=payload.encode("utf-8"),
                    capture_output=True,
                    timeout=PLUGIN_TIMEOUT,
                )
                if result.returncode != 0:
                    return {"ok": False, "error": result.stderr.decode("utf-8", errors="replace")[:200]}
                return json.loads(result.stdout.decode("utf-8"))
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "Plugin execution timed out"}
        except Exception as e:
            logger.exception("Plugin %s failed on %s", self.id, hook_name)
            return {"ok": False, "error": str(e)}

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "version": self.version,
            "author": self.author,
            "description": self.description,
            "type": self.type,
            "hooks": list(self.hooks),
            "enabled": self.enabled,
            "config": self.config,
        }


class PluginManager:
    def __init__(self, plugins_dir: str):
        self._plugins_dir = plugins_dir
        self._plugins: dict[str, Plugin] = {}
        os.makedirs(plugins_dir, exist_ok=True)
        self._load_all()

    def _load_all(self):
        if not os.path.isdir(self._plugins_dir):
            return
        for name in os.listdir(self._plugins_dir):
            plugin_dir = os.path.join(self._plugins_dir, name)
            manifest_path = os.path.join(plugin_dir, "plugin.json")
            if not os.path.isfile(manifest_path):
                continue
            try:
                manifest = read_json(manifest_path)
                if not manifest or not manifest.get("id") or not manifest.get("type"):
                    logger.warning("Invalid plugin.json in %s (missing id or type)", name)
                    continue
                plugin = Plugin(manifest, plugin_dir)
                plugin.initialize()
                self._plugins[plugin.id] = plugin
                logger.info("Loaded plugin: %s v%s", plugin.id, plugin.version)
            except Exception:
                logger.exception("Failed to load plugin %s", name)

    def dispatch(self, hook_name: str, data: dict):
        """Dispatch event to all subscribed plugins in parallel."""
        targets = [p for p in self._plugins.values() if p.enabled and hook_name in p.hooks]
        if not targets:
            return

        def _run(plugin: Plugin):
            try:
                result = plugin.execute(hook_name, data)
                if not result.get("ok"):
                    logger.warning("Plugin %s error on %s: %s", plugin.id, hook_name, result.get("error"))
            except Exception:
                logger.exception("Plugin %s crashed on %s", plugin.id, hook_name)

        with ThreadPoolExecutor(max_workers=min(len(targets), 4)) as ex:
            for plugin in targets:
                ex.submit(_run, plugin)

    def list_plugins(self) -> list[dict]:
        return [p.to_dict() for p in self._plugins.values()]

    def enable_plugin(self, plugin_id: str, enabled: bool):
        plugin = self._plugins.get(plugin_id)
        if not plugin:
            return False
        plugin.enabled = enabled
        # Persist to plugin.json
        manifest_path = os.path.join(plugin.plugin_dir, "plugin.json")
        try:
            manifest = read_json(manifest_path, {})
            manifest["enabled"] = enabled
            write_json(manifest_path, manifest)
        except Exception:
            logger.exception("Failed to persist plugin state")
        return True

    def get_plugin_config(self, plugin_id: str) -> dict:
        plugin = self._plugins.get(plugin_id)
        return plugin.config if plugin else {}

    def set_plugin_config(self, plugin_id: str, config: dict):
        plugin = self._plugins.get(plugin_id)
        if not plugin:
            return False
        plugin.config = config
        manifest_path = os.path.join(plugin.plugin_dir, "plugin.json")
        try:
            manifest = read_json(manifest_path, {})
            manifest["config"] = config
            write_json(manifest_path, manifest)
        except Exception:
            logger.exception("Failed to persist plugin config")
        # Re-initialize python plugins with new config
        if plugin.type == "python":
            try:
                plugin._instance = None
                plugin.initialize()
            except Exception:
                logger.exception("Failed to re-initialize plugin %s", plugin_id)
        return True
```

- [ ] **Step 2: 编写测试 `tests/test_plugin_manager.py`**

```python
import json

from backend.plugin_manager import PluginManager


class TestPluginManager:
    def test_empty_dir(self, tmp_path):
        pm = PluginManager(str(tmp_path))
        assert pm.list_plugins() == []

    def test_load_python_plugin(self, tmp_path):
        plugin_dir = tmp_path / "test_py"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.py",
            "name": "Test Python",
            "version": "1.0.0",
            "type": "python",
            "entry": "main.py",
            "hooks": ["on_download_complete"],
            "enabled": True,
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        (plugin_dir / "main.py").write_text('''
class Plugin:
    def __init__(self, config):
        self.config = config
    def on_download_complete(self, data):
        return {"ok": True, "received": data.get("filename")}
''', encoding="utf-8")

        pm = PluginManager(str(tmp_path))
        plugins = pm.list_plugins()
        assert len(plugins) == 1
        assert plugins[0]["id"] == "com.test.py"

    def test_dispatch_python(self, tmp_path):
        plugin_dir = tmp_path / "test_py"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.py",
            "name": "Test",
            "type": "python",
            "entry": "main.py",
            "hooks": ["on_download_complete"],
            "enabled": True,
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        (plugin_dir / "main.py").write_text('''
class Plugin:
    def __init__(self, config): pass
    def on_download_complete(self, data):
        return {"ok": True}
''', encoding="utf-8")

        pm = PluginManager(str(tmp_path))
        # Should not raise
        pm.dispatch("on_download_complete", {"filename": "test.pdf"})

    def test_enable_disable(self, tmp_path):
        plugin_dir = tmp_path / "test_py"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.py",
            "name": "Test",
            "type": "python",
            "entry": "main.py",
            "hooks": ["on_download_complete"],
            "enabled": True,
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        (plugin_dir / "main.py").write_text('class Plugin:\n    def __init__(self, c): pass\n', encoding="utf-8")

        pm = PluginManager(str(tmp_path))
        assert pm.list_plugins()[0]["enabled"] is True
        pm.enable_plugin("com.test.py", False)
        assert pm.list_plugins()[0]["enabled"] is False

    def test_skip_invalid_manifest(self, tmp_path):
        plugin_dir = tmp_path / "bad"
        plugin_dir.mkdir()
        (plugin_dir / "plugin.json").write_text('{"name": "no id or type"}', encoding="utf-8")
        pm = PluginManager(str(tmp_path))
        assert pm.list_plugins() == []
```

- [ ] **Step 3: 运行测试**

```bash
cd /Users/yimingwu/Documents/C-Paper
python -m pytest tests/test_plugin_manager.py -v
```

Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add src/backend/plugin_manager.py tests/test_plugin_manager.py
git commit -m "feat: add plugin manager with Python hook and command support"
```

---

## Task 4: API 层集成

**Files:**
- Modify: `src/backend/api.py`

- [ ] **Step 1: 导入新模块并初始化 PluginManager**

在 `api.py` 顶部添加：

```python
import webbrowser
from .updater import check_update, skip_version, set_update_check
from .plugin_manager import PluginManager
from .const import PLUGINS_DIR, VERSION
```

在 `API.__init__` 中添加（在 `self._hist_set = set()` 之后）：

```python
        self.plugin_manager = PluginManager(PLUGINS_DIR)
```

注意：`VERSION` 已经在 `const.py` 中定义完成导入，不再需要重复定义。

- [ ] **Step 2: 添加更新相关 API 方法**

在 `API` 类末尾添加：

```python
    # ── Auto Update ──

    def check_update(self, force="false"):
        try:
            result = check_update(force=(force.lower() == "true"))
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e), "has_update": False})

    def skip_version(self, version):
        try:
            skip_version(version)
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def set_update_check(self, enabled_json):
        try:
            enabled = json.loads(enabled_json)
            set_update_check(bool(enabled))
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def open_url(self, url):
        """Open URL in system default browser."""
        try:
            webbrowser.open(url)
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})
```

- [ ] **Step 3: 添加插件相关 API 方法**

在 `API` 类末尾添加：

```python
    # ── Plugins ──

    def get_plugins(self):
        try:
            return json.dumps({"ok": True, "plugins": self.plugin_manager.list_plugins()}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def toggle_plugin(self, plugin_id, enabled_json):
        try:
            enabled = json.loads(enabled_json)
            ok = self.plugin_manager.enable_plugin(plugin_id, bool(enabled))
            return json.dumps({"ok": ok})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def get_plugin_config(self, plugin_id):
        try:
            config = self.plugin_manager.get_plugin_config(plugin_id)
            return json.dumps({"ok": True, "config": config}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def set_plugin_config(self, plugin_id, config_json):
        try:
            config = json.loads(config_json)
            ok = self.plugin_manager.set_plugin_config(plugin_id, config)
            return json.dumps({"ok": ok})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def open_plugins_dir(self):
        try:
            import sys
            if sys.platform == "darwin":
                subprocess.run(["open", PLUGINS_DIR])
            elif sys.platform == "win32":
                subprocess.run(["explorer", PLUGINS_DIR])
            else:
                subprocess.run(["xdg-open", PLUGINS_DIR])
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})
```

- [ ] **Step 4: 在下载流程中插入 Hook（关键修改）**

修改 `start_download` 方法，在 `self.engine.reset_stats(len(items))` 之前添加：

```python
        # Dispatch batch start hook
        self.plugin_manager.dispatch("on_batch_start", {
            "total": len(items),
            "groups": groups,
        })
```

修改 `_create_download_worker` 中的 worker 函数，重写为统一的 hook 分发模式。原有代码在每个 except 块中设置 error/error_type，新代码改为在 finally 中统一分发：

```python
    def _create_download_worker(self):
        def worker(item):
            if self._cancel.is_set():
                return None
            with self._dl_lock:
                item["status"] = "downloading"
            # Dispatch on_download_start before download
            self.plugin_manager.dispatch("on_download_start", {
                "filename": item["filename"],
                "save_path": item["save_path"],
                "ftype": item["ftype"],
                "label": item["label"],
                "year": item["year"],
            })
            success = None
            try:
                self.engine.download_one(item["filename"], item["save_path"])
                with self._dl_lock:
                    item["status"] = "done"
                    item["error"] = ""
                self._record_one_history(item["filename"], item["label"], item["year"], item["save_path"])
                success = True
                return True
            except requests.exceptions.Timeout:
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = "网络超时"
                    item["error_type"] = "network"
                success = False
                return False
            except requests.exceptions.ConnectionError:
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = "连接失败"
                    item["error_type"] = "network"
                success = False
                return False
            except requests.exceptions.HTTPError as e:
                code = e.response.status_code if e.response is not None else 0
                with self._dl_lock:
                    item["status"] = "failed"
                    if code == 404:
                        item["error"] = "文件不存在 (404)"
                        item["error_type"] = "not_found"
                    elif code == 429:
                        item["error"] = "请求过频 (429)"
                        item["error_type"] = "rate_limit"
                    elif code >= 500:
                        item["error"] = f"服务器错误 ({code})"
                        item["error_type"] = "server"
                    else:
                        item["error"] = f"HTTP {code}"
                        item["error_type"] = "unknown"
                success = False
                return False
            except Exception as e:
                msg = str(e)
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = msg
                    if "proxy" in msg.lower() or "代理" in msg:
                        item["error_type"] = "proxy"
                    elif "断路器" in msg:
                        item["error_type"] = "rate_limit"
                    else:
                        item["error_type"] = "unknown"
                success = False
                return False
            finally:
                # Unified hook dispatch — only once, not in each except block
                try:
                    if success:
                        self.plugin_manager.dispatch("on_download_complete", {
                            "filename": item["filename"],
                            "save_path": item["save_path"],
                            "ftype": item["ftype"],
                            "label": item["label"],
                            "year": item["year"],
                        })
                    elif success is False:
                        self.plugin_manager.dispatch("on_download_failed", {
                            "filename": item["filename"],
                            "ftype": item["ftype"],
                            "label": item["label"],
                            "year": item["year"],
                            "error": item.get("error", ""),
                            "error_type": item.get("error_type", "unknown"),
                        })
                except Exception:
                    logger.exception("Plugin dispatch failed in download worker")
        return worker
```

修改 `_run_downloads` 方法，在所有重试完成后、设置 `phase="done"` 之前，分发 `on_batch_complete`。找到设置 `phase="done"` 的代码块（现有代码 line 222-232），在 `self._status["phase"] = "done"` 之前插入：

```python
                # Dispatch batch_complete hook before marking phase done
                with self._dl_lock:
                    failed_count = sum(1 for i in self._dl_items if i["status"] == "failed")
                    skipped_count = sum(1 for i in self._dl_items if i["status"] == "skipped")
                self.plugin_manager.dispatch("on_batch_complete", {
                    "total": batch_total,
                    "success": total_done,
                    "failed": failed_count,
                    "skipped": skipped_count,
                    "retry_rounds": current_round,
                })
```

- [ ] **Step 5: 在搜索流程中插入 Hook**

修改 `search` 方法，在返回 `json.dumps(...)` 之前添加：

```python
        try:
            self.plugin_manager.dispatch("on_search_result", {
                "subject": subject,
                "year": year,
                "season": season,
                "groups": groups,
            })
        except Exception:
            logger.exception("Plugin dispatch failed for on_search_result")
```

把 groups 变量提前到 dispatch 之前可用。具体做法：将 `groups = group_papers(...)` 的结果保存，dispatch 中引用它。

- [ ] **Step 6: Commit**

```bash
git add src/backend/api.py
git commit -m "feat: integrate updater and plugin manager into API layer"
```

---

## Task 5: 前端 UI — 更新提示

**Files:**
- Modify: `src/ui_v2.html`
- Modify: `src/ui_v2.js`
- Modify: `src/ui_v2.css`

- [ ] **Step 1: 在 `ui_v2.html` 中添加更新提示 Toast 容器**

在 `<div id="toasts"></div>` 下方添加：

```html
<div class="update-toast" id="update-toast" style="display:none">
  <div class="update-toast-content">
    <div class="update-toast-title">C-Paper <span id="update-ver"></span> 已发布</div>
    <div class="update-toast-notes" id="update-notes"></div>
    <div class="update-toast-actions">
      <button class="btn btn-pri btn-sm" onclick="openUpdateUrl()">查看详情</button>
      <button class="btn btn-sec btn-sm" onclick="skipThisVersion()">跳过此版本</button>
      <button class="btn btn-sec btn-sm" onclick="dismissUpdate()">×</button>
    </div>
  </div>
</div>
```

- [ ] **Step 2: 在 `ui_v2.css` 中添加更新提示样式**

```css
.update-toast{position:fixed;top:16px;right:16px;z-index:1001;
  background:var(--surface);border:1px solid var(--border2);border-radius:12px;
  box-shadow:0 8px 32px rgba(0,0,0,0.12);padding:16px;min-width:280px;
  animation:toastIn .3s ease;}
.update-toast-title{font-size:13px;font-weight:700;color:var(--text);margin-bottom:6px;}
.update-toast-notes{font-size:11px;color:var(--text2);line-height:1.6;max-height:120px;
  overflow-y:auto;margin-bottom:10px;white-space:pre-wrap;}
.update-toast-actions{display:flex;gap:6px;justify-content:flex-end;}
@keyframes toastIn{from{opacity:0;transform:translateY(-8px);}to{opacity:1;transform:translateY(0);}}
```

- [ ] **Step 3: 在 `ui_v2.js` 中添加更新检查逻辑**

在 `doInit()` 函数中，`window.focus()` 之前添加：

```javascript
  // Check for updates (async, non-blocking)
  setTimeout(()=>checkUpdate(), 2000);
```

在文件末尾添加：

```javascript
let _updateUrl = '';
let _updateVersion = '';

async function checkUpdate(force=false){
  try{
    const r = JSON.parse(await pywebview.api.check_update(force ? 'true' : 'false'));
    if(!r.ok || !r.has_update) return;
    _updateUrl = r.download_url || '';
    _updateVersion = r.latest_version || '';
    document.getElementById('update-ver').textContent = 'v' + _updateVersion;
    document.getElementById('update-notes').textContent = r.release_notes || '';
    document.getElementById('update-toast').style.display = '';
  }catch(e){}
}

async function openUpdateUrl(){
  if(_updateUrl){
    // Use Python-side webbrowser.open() — window.open is unreliable in pywebview
    await pywebview.api.open_url(_updateUrl);
  }
  dismissUpdate();
}

async function skipThisVersion(){
  if(_updateVersion){
    await pywebview.api.skip_version(_updateVersion);
  }
  dismissUpdate();
}

function dismissUpdate(){
  document.getElementById('update-toast').style.display = 'none';
}
```

- [ ] **Step 4: Commit**

```bash
git add src/ui_v2.html src/ui_v2.js src/ui_v2.css
git commit -m "feat: add auto-update toast notification UI"
```

---

## Task 6: 前端 UI — 插件设置面板

**Files:**
- Modify: `src/ui_v2.html`
- Modify: `src/ui_v2.js`
- Modify: `src/ui_v2.css`

- [ ] **Step 1: 在设置弹窗中添加插件区域**

在 `ui_v2.html` 的 `set-dialog` 中，在代理设置下方、版本信息上方添加：

```html
    <div style="border-top:1px solid var(--border);padding-top:14px">
      <div style="font-weight:700;font-size:14px;color:var(--text);margin-bottom:10px;display:flex;align-items:center;gap:8px">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18"/><path d="M9 21V9"/></svg>
        插件
      </div>
      <div id="plugin-list" style="display:flex;flex-direction:column;gap:8px">
        <div style="font-size:11px;color:var(--text3)">加载中...</div>
      </div>
      <div style="margin-top:10px;display:flex;gap:8px;align-items:center">
        <span style="font-size:10px;color:var(--text3)">插件目录: ~/.cie_cache/plugins/</span>
        <button class="btn btn-sec btn-sm" onclick="openPluginsDir()">打开目录</button>
      </div>
    </div>
```

- [ ] **Step 2: 在 `ui_v2.js` 中添加插件管理逻辑**

在 `doInit()` 中，`loadPlugins()` 需要在首次打开设置面板或 init 时调用。由于设置面板可能不在 init 时立即打开，在 `openSettings()` 相关函数中调用 `loadPlugins()`。

添加以下函数：

```javascript
async function loadPlugins(){
  try{
    const r = JSON.parse(await pywebview.api.get_plugins());
    if(!r.ok) return;
    renderPlugins(r.plugins);
  }catch(e){}
}

function renderPlugins(plugins){
  const el = document.getElementById('plugin-list');
  if(!el) return;
  if(!plugins || !plugins.length){
    el.innerHTML = '<div style="font-size:11px;color:var(--text3)">暂无已安装插件</div>';
    return;
  }
  el.innerHTML = '';
  plugins.forEach(p=>{
    const card = document.createElement('div');
    card.style.cssText = 'border:1px solid var(--border);border-radius:8px;padding:10px;display:flex;flex-direction:column;gap:4px';
    card.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px">
        <input type="checkbox" ${p.enabled?'checked':''} onchange="togglePlugin('${p.id}',this.checked)" style="width:14px;height:14px">
        <span style="font-size:12px;font-weight:600;color:var(--text)">${esc(p.name)}</span>
        <span style="font-size:9px;color:var(--text3);margin-left:auto">v${esc(p.version)}</span>
      </div>
      <div style="font-size:10px;color:var(--text2);padding-left:22px">${esc(p.description||'')}</div>
      <div style="font-size:9px;color:var(--text3);padding-left:22px">Hooks: ${p.hooks.join(', ')}</div>
    `;
    el.appendChild(card);
  });
}

async function togglePlugin(pluginId, enabled){
  try{
    const r = JSON.parse(await pywebview.api.toggle_plugin(pluginId, JSON.stringify(enabled)));
    if(!r.ok) toast('插件状态切换失败','err');
  }catch(e){ toast('插件状态切换失败: '+e.message,'err'); }
}

async function openPluginsDir(){
  await pywebview.api.open_plugins_dir();
}
```

- [ ] **Step 3: 在 `ui_v2.css` 中添加插件卡片样式**

```css
#plugin-list .plugin-card{border:1px solid var(--border);border-radius:8px;padding:10px;
  display:flex;flex-direction:column;gap:4px;transition:border-color .2s;}
#plugin-list .plugin-card:hover{border-color:var(--border2);}
```

- [ ] **Step 4: Commit**

```bash
git add src/ui_v2.html src/ui_v2.js src/ui_v2.css
git commit -m "feat: add plugin management UI in settings panel"
```

---

## Task 7: 示例插件

**Files:**
- Create: `examples/plugins/notify/plugin.json`
- Create: `examples/plugins/notify/main.py`

- [ ] **Step 1: 创建 Python 示例插件**

`examples/plugins/notify/plugin.json`:

```json
{
  "name": "下载完成系统通知",
  "id": "com.cpaper.examples.notify",
  "version": "1.0.0",
  "author": "C-Paper",
  "description": "下载完成后发送系统通知（macOS/Linux）",
  "type": "python",
  "entry": "main.py",
  "hooks": ["on_download_complete"],
  "enabled": true,
  "config": {}
}
```

`examples/plugins/notify/main.py`:

```python
import platform
import subprocess

class Plugin:
    def __init__(self, config):
        self.config = config

    def on_download_complete(self, data):
        filename = data.get("filename", "")
        system = platform.system()
        try:
            if system == "Darwin":
                subprocess.run([
                    "osascript", "-e",
                    f'display notification "{filename}" with title "C-Paper 下载完成"'
                ], check=True, capture_output=True)
            elif system == "Linux":
                subprocess.run([
                    "notify-send", "C-Paper 下载完成", filename
                ], check=True, capture_output=True)
        except Exception:
            pass
        return {"ok": True}
```

- [ ] **Step 2: Commit**

```bash
git add examples/
git commit -m "feat: add example download-complete notification plugin"
```

---

## Task 8: 构建配置更新

**Files:**
- Modify: `.github/workflows/build.yml`

- [ ] **Step 1: 确保 `version.json` 被打包**

检查 `build.yml` 的 Windows build 步骤，确保 `version.json` 被复制到输出目录。在 `Copy-Item` 步骤后添加：

```powershell
          Copy-Item -Path "version.json" -Destination "." -Force
```

macOS 的 `build_mac.sh` 也需要确保 `version.json` 被打包进 DMG。检查 `build_mac.sh` 内容，如果它复制 `src/` 目录，则 `version.json` 需要在 DMG 构建脚本中被额外复制。

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: ensure version.json is bundled in release artifacts"
```

---

## Task 9: 集成测试与验证

**Files:**
- Run: 测试命令

- [ ] **Step 1: 运行全部测试**

```bash
cd /Users/yimingwu/Documents/C-Paper
python -m pytest tests/ -v
```

Expected: 全部 PASS（包括新加的 `test_updater.py` 和 `test_plugin_manager.py`）

- [ ] **Step 2: 手动验证更新检查**

临时修改 `const.py` 中的 `VERSION = "5.0.0"`，运行应用，观察是否弹出更新提示。

```bash
cd /Users/yimingwu/Documents/C-Paper/src
python main.py
```

验证点：
- 启动 2 秒后右上角出现更新提示 Toast
- 点击"查看详情"能打开浏览器（通过 Python webbrowser.open）
- 点击"跳过此版本"后关闭提示，再次启动不再显示

验证完成后恢复 `VERSION = "5.2.0"`。

- [ ] **Step 3: 手动验证插件系统**

将 `examples/plugins/notify` 复制到 `~/.cie_cache/plugins/`，运行应用，执行一次下载，观察是否收到系统通知。

```bash
mkdir -p ~/.cie_cache/plugins
cp -r examples/plugins/notify ~/.cie_cache/plugins/
cd /Users/yimingwu/Documents/C-Paper/src
python main.py
```

验证点：
- 设置面板中看到插件列表
- 可以启用/禁用插件
- 下载完成后收到系统通知

- [ ] **Step 4: 验证 on_batch_complete hook**

创建一个临时 Python 插件，在 `on_batch_complete` 中打印 batch 统计信息，验证下载完成后的 hook 数据正确。

---

## Task 10: 文档更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 在 README 功能列表中添加新功能**

在"主要功能"列表中添加：

```markdown
- 🔄 **自动更新** —— 启动时自动检查 GitHub 最新版本，一键前往下载
- 🔌 **插件扩展** —— 支持 Python 脚本和外部命令插件，自定义下载后行为
```

- [ ] **Step 2: 添加插件开发说明**

在 README 末尾添加"插件开发"章节：

```markdown
## 插件开发

C-Paper 支持两种插件类型：

### Python 插件

在 `~/.cie_cache/plugins/{plugin_name}/` 目录下创建 `plugin.json` 和 `main.py`：

```json
{
  "name": "我的插件",
  "id": "com.example.myplugin",
  "version": "1.0.0",
  "type": "python",
  "entry": "main.py",
  "hooks": ["on_download_complete"],
  "enabled": true
}
```

`main.py` 中定义 `Plugin` 类：

```python
class Plugin:
    def __init__(self, config):
        self.config = config

    def on_download_complete(self, data):
        print(f"下载完成: {data['filename']}")
        return {"ok": True}
```

### 外部命令插件

将 `type` 设为 `"command"`，`entry` 指向可执行文件。C-Paper 会通过 stdin 传入 JSON 数据，从 stdout 读取返回结果。

### 支持的事件

- `on_search_result` — 搜索完成后
- `on_download_start` — 单个文件开始下载
- `on_download_complete` — 单个文件下载成功
- `on_download_failed` — 单个文件下载失败
- `on_batch_start` — 批量下载开始
- `on_batch_complete` — 批量下载结束（含统计：total/success/failed/skipped/retry_rounds）
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with auto-update and plugin features"
```

---

## 发布 Checklist

- [ ] 所有测试通过
- [ ] 手动验证更新提示和插件功能
- [ ] README 已更新
- [ ] `version.json` 中的版本号正确
- [ ] `const.py` 中的 `VERSION` 正确
- [ ] 打 tag 并推送：

```bash
git tag v5.2.0
git push origin v5.2.0
```

---

## 计划自审

### Spec 覆盖检查

| Spec 需求 | 对应 Task |
|---|---|
| AU-01 启动时检查 GitHub | Task 2 + Task 5 |
| AU-02 每天最多一次 | Task 2 (`_should_check`) |
| AU-03 非侵入式 Toast | Task 5 |
| AU-04 前往下载按钮（webbrowser.open） | Task 4 (`open_url`) + Task 5 |
| AU-05 跳过此版本 | Task 2 (`skip_version`) + Task 5 |
| AU-06 version.json fallback | Task 2 (`_fetch_version_json`) |
| AU-07 关闭自动检查 | Task 2 (`set_update_check`) |
| PL-01 Python 钩子 | Task 3 |
| PL-02 外部命令 | Task 3 |
| PL-03 生命周期事件 | Task 3 + Task 4 |
| PL-04 JSON 配置 | Task 3 (`plugin.json`) |
| PL-05 启用/禁用 | Task 3 + Task 6 |
| PL-06 错误隔离 | Task 3 (`try/except` + timeout) |
| PL-07 开发文档 | Task 10 |
| PL-08 统一 hook 分发（避免 except 块重复） | Task 4 Step 4 |
| on_batch_complete | Task 4 Step 4 (`_run_downloads` 末尾) |

### 审查修订记录

| 问题 | 修订 |
|---|---|
| 原始设计中 `on_batch_complete` 缺失分发放置 | 在 `_run_downloads` 末尾、`phase="done"` 之前添加分发 |
| 原始计划在 4 个 except 块中重复 hook 分发 | 改为在 finally 块中根据 success 标志统一分发 |
| 原始计划用 `window.open()` 打开 URL | 改为 `pywebview.api.open_url()` → Python `webbrowser.open()` |
| 原始计划提到修改 `engine.py` | 确认不需要修改 engine.py，hook 在 api.py worker 层面完成 |

### Placeholder 扫描

- [x] 无 TBD/TODO
- [x] 所有步骤包含具体代码
- [x] 所有测试包含具体断言
- [x] 所有命令包含预期输出

### 类型一致性

- [x] `check_update` 返回 `dict`，前后一致
- [x] `PluginManager` 方法签名前后一致
- [x] API 方法参数类型前后一致
