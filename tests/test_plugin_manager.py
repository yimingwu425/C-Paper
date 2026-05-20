import json
import time

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
        try:
            pm.dispatch("on_download_complete", {"filename": "test.pdf"})
        finally:
            pm.close()

    def test_dispatch_python_does_not_wait_for_slow_plugin(self, tmp_path):
        plugin_dir = tmp_path / "slow_py"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.slow",
            "name": "Slow",
            "type": "python",
            "entry": "main.py",
            "hooks": ["on_download_complete"],
            "enabled": True,
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        (plugin_dir / "main.py").write_text('''
import time

class Plugin:
    def __init__(self, config): pass
    def on_download_complete(self, data):
        time.sleep(0.3)
        return {"ok": True}
''', encoding="utf-8")

        pm = PluginManager(str(tmp_path))
        try:
            start = time.perf_counter()
            pm.dispatch("on_download_complete", {"filename": "test.pdf"})
            elapsed = time.perf_counter() - start
            assert elapsed < 0.2
        finally:
            pm.close()

    def test_dispatch_python_exception_does_not_raise(self, tmp_path):
        plugin_dir = tmp_path / "raising_py"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.raising",
            "name": "Raising",
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
        raise RuntimeError("boom")
''', encoding="utf-8")

        pm = PluginManager(str(tmp_path))
        try:
            pm.dispatch("on_download_complete", {"filename": "test.pdf"})
        finally:
            pm.close()

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

    def test_skip_unsupported_plugin_type(self, tmp_path):
        plugin_dir = tmp_path / "bad_type"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.badtype",
            "name": "Bad Type",
            "type": "shellish",
            "entry": "run.sh",
            "hooks": ["on_download_complete"],
            "enabled": True,
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        pm = PluginManager(str(tmp_path))
        assert pm.list_plugins() == []

    def test_skip_non_python_plugin_type(self, tmp_path):
        plugin_dir = tmp_path / "bad_type"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.badtype",
            "name": "Bad Type",
            "type": "command",
            "entry": "run.sh",
            "hooks": ["on_download_complete"],
            "enabled": True,
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        (plugin_dir / "run.sh").write_text("#!/bin/sh\necho '{}'\n", encoding="utf-8")
        pm = PluginManager(str(tmp_path))
        assert pm.list_plugins() == []

    def test_lazy_dispatch_waits_for_initial_load(self, tmp_path):
        marker = tmp_path / "called.txt"
        plugin_dir = tmp_path / "lazy_py"
        plugin_dir.mkdir()
        manifest = {
            "id": "com.test.lazy",
            "name": "Lazy",
            "type": "python",
            "entry": "main.py",
            "hooks": ["on_download_complete"],
            "enabled": True,
            "config": {"marker": str(marker)},
        }
        (plugin_dir / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        (plugin_dir / "main.py").write_text('''
class Plugin:
    def __init__(self, config):
        self.marker = config["marker"]
    def on_download_complete(self, data):
        with open(self.marker, "w", encoding="utf-8") as f:
            f.write(data.get("filename", ""))
        return {"ok": True}
''', encoding="utf-8")

        pm = PluginManager(str(tmp_path), lazy=True)
        try:
            pm.dispatch("on_download_complete", {"filename": "first.pdf"})
            deadline = time.time() + 1
            while time.time() < deadline and not marker.exists():
                time.sleep(0.01)
            assert marker.read_text(encoding="utf-8") == "first.pdf"
        finally:
            pm.close()
