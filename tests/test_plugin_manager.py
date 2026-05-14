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
