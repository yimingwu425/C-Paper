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
