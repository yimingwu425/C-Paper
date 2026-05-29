#!/usr/bin/env python3
"""C-Paper v5.2.1 — three-column desktop app (pywebview + requests)"""
import os
import sys
import webview

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

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
            # 1. Add class namespace to HTML documentElement and body
            window.evaluate_js("document.documentElement.classList.add('mac-os'); document.body.classList.add('mac-os');")
            
            # 2. Thread-safe Cocoa / PyObjC Vibrancy & Shadow Injector
            try:
                import AppKit
                from PyObjCTools import AppHelper
                
                def _inject_cocoa_vibrancy():
                    try:
                        native_window = window.native
                        if not native_window:
                            print("[Cocoa] Native window is None")
                            return
                            
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
                            except Exception as e:
                                print(f"[Cocoa] WebView drawsBackground failed: {e}")
                            try:
                                wk_webview.setUnderPageBackgroundColor_(AppKit.NSColor.clearColor())
                            except Exception as e:
                                print(f"[Cocoa] WebView setUnderPageBackgroundColor failed: {e}")
                            
                            # Create one native vibrancy layer and keep WebKit pixels clear.
                            frame = wk_webview.bounds()
                            vfx = AppKit.NSVisualEffectView.alloc().initWithFrame_(frame)
                            vfx.setAutoresizingMask_(AppKit.NSViewWidthSizable | AppKit.NSViewHeightSizable)
                            vfx.setWantsLayer_(True)
                            
                            # Let macOS adapt vibrancy when the window becomes inactive.
                            vfx.setState_(0)
                            # Blending Mode: 0 = NSVisualEffectBlendingModeBehindWindow
                            vfx.setBlendingMode_(0)
                            # Material: 7 = NSVisualEffectMaterialSidebar, a stable native macOS surface.
                            vfx.setMaterial_(7)
                            
                            # Insert under all other views (relativeTo: None)
                            wk_webview.addSubview_positioned_relativeTo_(vfx, AppKit.NSWindowBelow, None)
                            
                            print("[Cocoa] Successfully injected native vibrancy and drop shadow on main thread!")
                    except Exception as inner_e:
                        print(f"[Cocoa] Error inside main thread injector: {inner_e}")
                
                # Dispatch the injection block to the macOS main UI thread
                AppHelper.callAfter(_inject_cocoa_vibrancy)
            except Exception as e:
                print(f"[Cocoa] Failed to dispatch vibrancy inject: {e}")

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
