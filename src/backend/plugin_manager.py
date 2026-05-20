"""Plugin Manager — supports Python hooks"""
import importlib.util
import json
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from .cache import read_json, write_json

logger = logging.getLogger(__name__)
SUPPORTED_PLUGIN_TYPES = {"python"}


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
        self.type = manifest["type"]
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
        if self.type != "python":
            raise ValueError(f"Unsupported plugin type: {self.type}")
        self._load_python()

    def execute(self, hook_name: str, data: dict) -> dict:
        if hook_name not in self.hooks:
            return {"ok": True, "skipped": True}
        try:
            if self.type != "python":
                return {"ok": False, "error": f"Unsupported plugin type: {self.type}"}
            if self._instance is None:
                self.initialize()
            handler = getattr(self._instance, hook_name, None)
            if handler is None:
                return {"ok": False, "error": f"Handler {hook_name} not found"}
            return handler(data) or {"ok": True}
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
    def __init__(self, plugins_dir: str, lazy: bool = False):
        self._plugins_dir = plugins_dir
        self._plugins: dict[str, Plugin] = {}
        self._lock = threading.Lock()
        self._executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="plugin-manager")
        self._closed = False
        self._loaded = False
        os.makedirs(plugins_dir, exist_ok=True)
        if not lazy:
            self._load_all()
        else:
            threading.Thread(target=self._load_all, daemon=True).start()

    def _load_all(self):
        if not os.path.isdir(self._plugins_dir):
            return
        loaded = {}
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
                if manifest.get("type") not in SUPPORTED_PLUGIN_TYPES:
                    logger.warning("Invalid plugin.json in %s (unsupported type: %s)", name, manifest.get("type"))
                    continue
                plugin = Plugin(manifest, plugin_dir)
                plugin.initialize()
                loaded[plugin.id] = plugin
                logger.info("Loaded plugin: %s v%s", plugin.id, plugin.version)
            except Exception:
                logger.exception("Failed to load plugin %s", name)
        with self._lock:
            self._plugins = loaded
            self._loaded = True
        logger.info("PluginManager lazy load complete: %d plugins loaded", len(loaded))

    def dispatch(self, hook_name: str, data: dict):
        """Dispatch event to all subscribed plugins in the background."""
        self.ensure_loaded()
        with self._lock:
            targets = [p for p in self._plugins.values() if p.enabled and hook_name in p.hooks]
            if self._closed or not targets:
                return

            def _run(plugin: Plugin):
                try:
                    result = plugin.execute(hook_name, data)
                    if not result.get("ok"):
                        logger.warning("Plugin %s error on %s: %s", plugin.id, hook_name, result.get("error"))
                except Exception:
                    logger.exception("Plugin %s crashed on %s", plugin.id, hook_name)

            for plugin in targets:
                self._executor.submit(_run, plugin)

    def ensure_loaded(self):
        """Block until initial plugin discovery has completed."""
        while True:
            with self._lock:
                if self._loaded:
                    return
            time.sleep(0.01)

    def close(self, wait: bool = True):
        """Shut down background plugin workers."""
        with self._lock:
            if self._closed:
                return
            self._closed = True
            executor = self._executor
        executor.shutdown(wait=wait)

    def list_plugins(self) -> list[dict]:
        with self._lock:
            return [p.to_dict() for p in self._plugins.values()]

    def enable_plugin(self, plugin_id: str, enabled: bool):
        """Enable/disable a plugin. Persists to plugin.json, preserving all existing fields."""
        with self._lock:
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
