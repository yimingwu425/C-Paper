"""C-Paper constants"""
import os

BASE_URL  = "https://cie.fraft.cn"
SEASONS   = [("Mar", "春季"), ("Jun", "夏季"), ("Nov", "冬季")]
CACHE_DIR = os.path.expanduser("~/.cie_cache")
CACHE_TTL = 86400          # 24 hours
CACHE_MAX = 200            # max cache files
USER_AGENT = "C-Paper/5.2.3 (Desktop)"
HISTORY_MAX = 2000         # max download history entries
VERSION = "5.2.3"

PLUGINS_DIR = os.path.join(CACHE_DIR, "plugins")
UPDATE_STATE_PATH = os.path.join(CACHE_DIR, "update_state.json")
