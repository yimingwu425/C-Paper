#!/usr/bin/env python3
"""C-Paper v5.2.1 — three-column desktop app (pywebview + requests)"""
import os
import sys
import webview
from backend.api import API

_UI_DIR = os.path.dirname(os.path.abspath(__file__))
_UI_PATH = os.path.join(_UI_DIR, "ui_v2.html")

if __name__ == "__main__":
    api = API()
    is_mac = (sys.platform == "darwin")
    window = webview.create_window(
        "C-Paper",
        url=f"file://{_UI_PATH}",
        js_api=api,
        width=1280, height=900,
        min_size=(1024, 700),
        hidden=True,
        transparent=is_mac,
        vibrancy=is_mac,
        frameless=is_mac,
    )
    api.window = window

    def _on_loaded():
        if is_mac:
            # 1. Add class namespace to HTML body
            window.evaluate_js("document.body.classList.add('mac-os');")
            
            # 2. Advanced Cocoa / PyObjC Vibrancy & Shadow Injector
            try:
                import AppKit
                native_window = window.native
                if native_window:
                    # Restore premium macOS native drop shadow (frameless windows lose shadow by default in pywebview)
                    native_window.setHasShadow_(True)
                    native_window.invalidateShadow()
                    
                    wk_webview = native_window.contentView()
                    if wk_webview:
                        # Clear default pywebview vibrancy views if present
                        for subview in list(wk_webview.subviews()):
                            if isinstance(subview, AppKit.NSVisualEffectView):
                                subview.removeFromSuperview()
                        
                        # Apply modern transparent WebView settings to let vibrancy pass through flawlessly
                        try:
                            wk_webview.setValue_forKey_(False, 'drawsBackground')
                        except Exception:
                            pass
                        try:
                            wk_webview.setUnderPageBackgroundColor_(AppKit.NSColor.clearColor())
                        except Exception:
                            pass
                        
                        # Create custom high-fidelity NSVisualEffectView
                        frame = wk_webview.bounds()
                        vfx = AppKit.NSVisualEffectView.alloc().initWithFrame_(frame)
                        vfx.setAutoresizingMask_(AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable)
                        vfx.setWantsLayer_(True)
                        
                        # State: 1 = NSVisualEffectStateActive (always vibrant, even in background)
                        vfx.setState_(1)
                        # Blending Mode: 0 = NSVisualEffectBlendingModeBehindWindow
                        vfx.setBlendingMode_(0)
                        # Material: 7 = NSVisualEffectMaterialSidebar (ultra-clear, premium glass blur)
                        vfx.setMaterial_(7)
                        
                        # Insert under the WebView
                        wk_webview.addSubview_positioned_relativeTo_(vfx, AppKit.NSWindowBelow, wk_webview)
                        
                        print("[Cocoa] High-fidelity macOS native vibrancy and drop shadow successfully injected!")
            except Exception as e:
                print(f"[Cocoa] Failed to inject custom vibrancy: {e}")

        window.show()
        window.evaluate_js("window.focus();")

    def _on_maximized():
        api.sync_maximize_state(True)

    def _on_restored():
        api.sync_maximize_state(False)

    window.events.loaded += _on_loaded
    if is_mac:
        window.events.maximized += _on_maximized
        window.events.restored += _on_restored
    webview.start(debug=False)

