#!/usr/bin/env python3
"""C-Paper v5.2.1 — three-column desktop app (pywebview + requests)"""
import os
import webview
from backend.api import API

_UI_DIR = os.path.dirname(os.path.abspath(__file__))
_UI_PATH = os.path.join(_UI_DIR, "ui_v2.html")

if __name__ == "__main__":
    api = API()
    window = webview.create_window(
        "C-Paper",
        url=f"file://{_UI_PATH}",
        js_api=api,
        width=1280, height=900,
        min_size=(1024, 700),
        hidden=True,
        background_color="#faf9f5",
    )
    api.window = window

    def _on_loaded():
        window.show()
        window.evaluate_js("window.focus();")

    window.events.loaded += _on_loaded
    webview.start(debug=False)
