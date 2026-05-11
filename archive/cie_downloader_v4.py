#!/usr/bin/env python3
"""CIE 试卷下载器 v4 — Liquid Glass UI (pywebview + requests)"""

import webview
import json, os, re, time, threading, shutil, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE_URL  = "https://cie.fraft.cn"
SEASONS   = [("Mar","春季"),("Jun","夏季"),("Nov","冬季")]
CACHE_DIR = os.path.expanduser("~/.cie_cache")
CACHE_TTL = 86400          # 24 hours
CACHE_MAX = 200            # max cache files
USER_AGENT = "CIE-Downloader/4.0 (Desktop)"


# ═══════════════════════════════════════════════════════
#  Cache
# ═══════════════════════════════════════════════════════

def load_cache(key):
    p = os.path.join(CACHE_DIR, f"{key}.json")
    if not os.path.exists(p):
        return None
    try:
        if time.time() - os.path.getmtime(p) > CACHE_TTL:
            os.remove(p)
            return None
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def save_cache(key, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        # LRU: remove oldest if over limit
        files = sorted(
            [os.path.join(CACHE_DIR, f) for f in os.listdir(CACHE_DIR) if f.endswith(".json")],
            key=os.path.getmtime,
        )
        while len(files) >= CACHE_MAX:
            oldest = files.pop(0)
            try:
                os.remove(oldest)
            except OSError:
                pass
        with open(os.path.join(CACHE_DIR, f"{key}.json"), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass


# ═══════════════════════════════════════════════════════
#  TokenBucket — thread-safe rate limiter
# ═══════════════════════════════════════════════════════

class TokenBucket:
    def __init__(self, rate: float, capacity: int):
        self._rate = rate
        self._capacity = float(capacity)
        self._tokens = float(capacity)
        self._last_refill = time.monotonic()
        self._lock = threading.Lock()

    def acquire(self, tokens: float = 1.0) -> float:
        """Block until tokens available. Returns seconds waited."""
        waited = 0.0
        while True:
            with self._lock:
                now = time.monotonic()
                elapsed = now - self._last_refill
                self._tokens = min(self._capacity, self._tokens + elapsed * self._rate)
                self._last_refill = now
                if self._tokens >= tokens:
                    self._tokens -= tokens
                    return waited
                wait = (tokens - self._tokens) / self._rate
            time.sleep(wait)
            waited += wait

    def drain(self):
        with self._lock:
            self._tokens = 0.0
            self._last_refill = time.monotonic()


# ═══════════════════════════════════════════════════════
#  CircuitBreaker — fault isolation
# ═══════════════════════════════════════════════════════

class CircuitBreaker:
    CLOSED, OPEN, HALF_OPEN = "CLOSED", "OPEN", "HALF_OPEN"

    def __init__(self, failure_threshold: int = 5, recovery_timeout: float = 30.0):
        self._threshold = failure_threshold
        self._recovery = recovery_timeout
        self._failures = 0
        self._state = self.CLOSED
        self._last_failure = 0.0
        self._lock = threading.Lock()

    @property
    def state(self):
        with self._lock:
            if self._state == self.OPEN:
                if time.monotonic() - self._last_failure >= self._recovery:
                    self._state = self.HALF_OPEN
            return self._state

    def record_success(self):
        with self._lock:
            self._state = self.CLOSED
            self._failures = 0

    def record_failure(self):
        with self._lock:
            self._failures += 1
            self._last_failure = time.monotonic()
            if self._failures >= self._threshold:
                self._state = self.OPEN


# ═══════════════════════════════════════════════════════
#  DownloadEngine
# ═══════════════════════════════════════════════════════

def create_session(max_retries: int = 5) -> requests.Session:
    retry = Retry(
        total=max_retries,
        backoff_factor=1.0,
        backoff_jitter=0.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"],
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(
        max_retries=retry,
        pool_connections=10,
        pool_maxsize=10,
    )
    s = requests.Session()
    s.headers["User-Agent"] = USER_AGENT
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    return s

class DownloadEngine:
    def __init__(self, rate: float = 5.0, capacity: int = 15, max_concurrent: int = 4):
        self.bucket = TokenBucket(rate, capacity)
        self._max_concurrent = max_concurrent
        self.semaphore = threading.BoundedSemaphore(max_concurrent)
        self.breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=30.0)
        self.session = create_session()
        self._lock = threading.Lock()
        self._stats = {"done": 0, "success": 0, "failed": 0}

    def update_rate(self, rate: float):
        self.bucket._rate = rate

    def update_concurrency(self, n: int):
        # Only call between download batches — not thread-safe during active downloads
        self._max_concurrent = n
        self.semaphore = threading.BoundedSemaphore(n)

    def download_one(self, filename: str, save_path: str) -> None:
        # Circuit breaker check
        st = self.breaker.state
        if st == CircuitBreaker.OPEN:
            raise RuntimeError("断路器开启：服务器过载，请等待冷却 (30s)")

        # Rate limit
        self.bucket.acquire()

        # Concurrency limit
        with self.semaphore:
            url = f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"
            try:
                resp = self.session.get(url, timeout=(10, 60), stream=True)
                resp.raise_for_status()
                os.makedirs(os.path.dirname(save_path) or ".", exist_ok=True)
                with open(save_path, "wb") as f:
                    shutil.copyfileobj(resp.raw, f)
                self.breaker.record_success()
            except requests.exceptions.HTTPError as e:
                code = e.response.status_code if e.response is not None else 0
                if code == 429:
                    self.bucket.drain()   # force cooldown
                if code == 429 or code >= 500:
                    self.breaker.record_failure()
                raise
            except requests.exceptions.RequestException:
                self.breaker.record_failure()
                raise

    def reset_stats(self, total: int):
        with self._lock:
            self._stats = {"done": 0, "success": 0, "failed": 0, "total": total}

    def record_result(self, success: bool):
        with self._lock:
            self._stats["done"] += 1
            if success:
                self._stats["success"] += 1
            else:
                self._stats["failed"] += 1

    def get_stats(self):
        with self._lock:
            return dict(self._stats)


# ═══════════════════════════════════════════════════════
#  Network helpers (reuse engine's session)
# ═══════════════════════════════════════════════════════

def fetch_subjects(session: requests.Session):
    resp = session.post(
        f"{BASE_URL}/obj/Common/Subject/combo",
        timeout=(5, 15),
    )
    resp.raise_for_status()
    return resp.json()

def search_papers(session: requests.Session, subject, year, season):
    key = f"{subject}_{year}_{season}"
    cached = load_cache(key)
    if cached:
        return cached
    resp = session.post(
        f"{BASE_URL}/obj/Common/Fetch/renum",
        data={"subject": str(subject), "year": str(year), "season": season},
        timeout=(5, 20),
    )
    resp.raise_for_status()
    result = resp.json()
    save_cache(key, result)
    return result


# ═══════════════════════════════════════════════════════
#  File parsing & grouping
# ═══════════════════════════════════════════════════════

def parse_filename(fname):
    m = re.match(r"(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf", fname)
    if not m:
        return None
    return dict(subject=m.group(1), sy=m.group(2), type=m.group(3),
                number=m.group(4) or "", filename=fname)

def get_year(sy):
    y = sy[1:] if len(sy) > 1 and sy[0] in "msw" else "unknown"
    return "20" + y if y.isdigit() and len(y) == 2 else y

def paper_group_of(number):
    if not number:
        return 0
    n = int(number)
    return n // 10 if n >= 10 else n

def group_papers(rows):
    """Group into pairs (qp+ms) or standalone files. Returns flat file-level list per group."""
    pairs, standalone_files = {}, []
    for row in rows:
        fname = row["file"]
        p = parse_filename(fname)
        if not p or p["type"] not in ("qp", "ms"):
            standalone_files.append(dict(
                filename=fname, ftype=p["type"] if p else "other",
                label=fname.replace(".pdf", ""), paper_group=0,
                sy="", number="",
            ))
            continue
        key = (p["subject"], p["sy"], p["number"])
        if key not in pairs:
            pairs[key] = dict(
                subject=p["subject"], sy=p["sy"], number=p["number"],
                paper_group=paper_group_of(p["number"]),
                qp=None, ms=None,  # individual filenames
            )
        pairs[key][p["type"]] = fname

    results = []
    for v in pairs.values():
        results.append(dict(
            subject=v["subject"], sy=v["sy"], number=v["number"],
            paper_group=v["paper_group"],
            qp=v.get("qp"), ms=v.get("ms"),
        ))
    results.sort(key=lambda g: (g["paper_group"],
                                 int(g["number"]) if g["number"].isdigit() else 999))
    # standalone at end
    results.extend(standalone_files)
    return results

def build_folders(groups, save_dir, merge):
    os.makedirs(save_dir, exist_ok=True)
    if merge:
        return {"root": save_dir}
    folders = {}
    for g in groups:
        year = get_year(g.get("sy", ""))
        if year not in folders:
            folders[year] = {
                "qp": os.path.join(save_dir, year, "QP"),
                "ms": os.path.join(save_dir, year, "MS"),
            }
            os.makedirs(folders[year]["qp"], exist_ok=True)
            os.makedirs(folders[year]["ms"], exist_ok=True)
    return folders


# ═══════════════════════════════════════════════════════
#  Python ↔ JS bridge API
# ═══════════════════════════════════════════════════════

class API:
    def __init__(self):
        self.window = None
        self._dl_items: list = []
        self._dl_lock = threading.Lock()
        self._status_lock = threading.Lock()
        self._status = {"phase": "idle", "done": 0, "total": 0, "success": 0, "message": "就绪"}
        self.engine = DownloadEngine(rate=5.0, capacity=15, max_concurrent=4)
        self.session = create_session()

    # ── Init ─────────────────────────────────────────

    def get_default_dir(self):
        return os.path.expanduser("~/Downloads/CIE_Papers")

    def get_subjects(self):
        try:
            data = fetch_subjects(self.session)
            return json.dumps({"ok": True, "data": data}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    # ── Search ───────────────────────────────────────

    def search(self, subject, year, season):
        try:
            result = search_papers(self.session, subject, year, season)
            groups = group_papers(result.get("rows", []))
            return json.dumps({"ok": True, "groups": groups,
                               "count": len(result.get("rows", []))}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    # ── Batch Preview ────────────────────────────────

    def batch_preview(self, params_json):
        p = json.loads(params_json)
        queries = [(y, s)
                   for y in range(int(p["year_from"]), int(p["year_to"]) + 1)
                   for s in p["seasons"]]
        all_groups = []
        errors = []
        with ThreadPoolExecutor(max_workers=3) as ex:
            futs = {ex.submit(search_papers, self.session, p["code"], y, s): (y, s)
                    for y, s in queries}
            for fut in as_completed(futs):
                try:
                    res = fut.result(timeout=30)
                    gs = group_papers(res.get("rows", []))
                    all_groups.extend(
                        g for g in gs
                        if g.get("paper_group", -1) in p["pgs"]
                    )
                except Exception as e:
                    y, s = futs[fut]
                    errors.append(f"{y}/{s}: {e}")
        result = {"ok": True, "groups": all_groups}
        if errors:
            result["warnings"] = errors
        return json.dumps(result, ensure_ascii=False)

    # ── Download ─────────────────────────────────────

    def start_download(self, groups_json, save_dir, options_json):
        groups = json.loads(groups_json)
        options = json.loads(options_json)
        merge = bool(options.get("merge", False))
        include_ms = bool(options.get("include_ms", True))
        rate = float(options.get("rate", 5.0))
        threads = int(options.get("threads", 4))

        self.engine.update_rate(rate)
        self.engine.update_concurrency(threads)

        folders = build_folders(groups, save_dir, merge)

        # Build flat download item list
        items = []
        for g in groups:
            year = get_year(g.get("sy", ""))
            label = f"Paper {g['number']}" if g.get("number") else g.get("label", "")
            for ftype_key, ftype_label in [("qp", "QP"), ("ms", "MS")]:
                if ftype_key == "ms" and not include_ms:
                    continue
                fname = g.get(ftype_key)
                if not fname:
                    continue
                if merge:
                    fdir = folders["root"]
                else:
                    fdir = folders.get(year, {}).get(ftype_key, save_dir)
                items.append({
                    "id": len(items),
                    "filename": fname,
                    "ftype": ftype_label,
                    "label": label,
                    "year": year,
                    "save_path": os.path.join(fdir, fname),
                    "status": "pending",
                    "error": "",
                })

        with self._dl_lock:
            self._dl_items = items
        with self._status_lock:
            self._status = {"phase": "running", "done": 0, "total": len(items),
                            "success": 0, "message": "准备下载..."}

        threading.Thread(target=self._run_downloads, args=(items,), daemon=True).start()
        return json.dumps({"ok": True, "total": len(items)})

    def _run_downloads(self, items, retry_round: int = 0):
        """Run downloads with auto-retry for failed items."""
        MAX_AUTO_RETRIES = 10

        def worker(item):
            with self._dl_lock:
                item["status"] = "downloading"
            try:
                self.engine.download_one(item["filename"], item["save_path"])
                with self._dl_lock:
                    item["status"] = "done"
                    item["error"] = ""
                return True
            except Exception as e:
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = str(e)
                return False

        self.engine.reset_stats(len(items))
        max_w = getattr(self.engine, '_max_concurrent', 4)
        with ThreadPoolExecutor(max_workers=max_w) as ex:
            futures = []
            for item in items:
                futures.append(ex.submit(worker, item))

            for fut in as_completed(futures):
                ok = fut.result()
                self.engine.record_result(ok)
                st = self.engine.get_stats()
                with self._status_lock:
                    self._status["done"] = st["done"]
                    self._status["success"] = st["success"]
                    self._status["message"] = f"下载中... ({st['done']}/{st['total']})"

        # Check for failures & auto-retry
        with self._dl_lock:
            failed = [i for i in self._dl_items if i["status"] == "failed"]

        if failed and retry_round < MAX_AUTO_RETRIES:
            # Exponential backoff between retry rounds
            delay = min(5 * (2 ** retry_round), 60)
            with self._status_lock:
                self._status["message"] = f"{len(failed)} 失败, {delay}s 后自动重试 (第{retry_round+1}轮)..."
            time.sleep(delay)

            # Reset failed items to pending
            with self._dl_lock:
                for item in failed:
                    item["status"] = "pending"
                    item["error"] = ""
            self._run_downloads(failed, retry_round + 1)
        else:
            # Done
            st = self.engine.get_stats()
            with self._status_lock:
                self._status["phase"] = "done"
                if retry_round > 0:
                    self._status["message"] = f"完成 ({st['success']}/{st['total']} 成功, 经过{retry_round}轮重试)"
                else:
                    self._status["message"] = f"完成 ({st['success']}/{st['total']} 成功)"

    # ── Status / List ────────────────────────────────

    def get_status(self):
        with self._status_lock:
            return json.dumps(dict(self._status), ensure_ascii=False)

    def get_download_list(self):
        with self._dl_lock:
            return json.dumps(list(self._dl_items), ensure_ascii=False)

    # ── Retry ────────────────────────────────────────

    def retry_failed(self):
        with self._status_lock:
            if self._status["phase"] == "running":
                return json.dumps({"ok": False, "error": "下载进行中"})
        with self._dl_lock:
            failed = [i for i in self._dl_items if i["status"] == "failed"]
            for i in failed:
                i["status"] = "pending"
                i["error"] = ""
        if not failed:
            return json.dumps({"ok": True, "count": 0})
        with self._status_lock:
            self._status = {"phase": "running", "done": 0, "total": len(failed),
                            "success": 0, "message": "手动重试中..."}
        threading.Thread(target=self._run_downloads, args=(failed, 0), daemon=True).start()
        return json.dumps({"ok": True, "count": len(failed)})

    def retry_item(self, item_id):
        with self._status_lock:
            if self._status["phase"] == "running":
                return json.dumps({"ok": False, "error": "下载进行中"})
        with self._dl_lock:
            item = next((i for i in self._dl_items if i["id"] == item_id), None)
            if not item:
                return json.dumps({"ok": False, "error": "找不到该项"})
            item["status"] = "pending"
            item["error"] = ""
        with self._status_lock:
            self._status = {"phase": "running", "done": 0, "total": 1,
                            "success": 0, "message": "单文件重试中..."}
        threading.Thread(target=self._run_downloads, args=([item], 0), daemon=True).start()
        return json.dumps({"ok": True})

    def clear_download_list(self):
        with self._status_lock:
            if self._status["phase"] == "running":
                return json.dumps({"ok": False, "error": "下载进行中"})
        with self._dl_lock:
            self._dl_items = []
        with self._status_lock:
            self._status = {"phase": "idle", "done": 0, "total": 0, "success": 0, "message": "就绪"}
        return json.dumps({"ok": True})

    # ── File system ──────────────────────────────────

    def choose_directory(self):
        try:
            import sys
            if sys.platform == "darwin":
                r = subprocess.run(
                    ["osascript", "-e", "POSIX path of (choose folder)"],
                    capture_output=True, text=True, timeout=60,
                )
                return r.stdout.strip().rstrip("/") if r.returncode == 0 else ""
            elif sys.platform == "win32":
                ps = (
                    "Add-Type -AssemblyName System.Windows.Forms;"
                    "$f=New-Object System.Windows.Forms.FolderBrowserDialog;"
                    "$f.ShowDialog()|Out-Null;$f.SelectedPath"
                )
                r = subprocess.run(
                    ["powershell", "-NoProfile", "-Command", ps],
                    capture_output=True, text=True, timeout=60,
                )
                return r.stdout.strip() if r.returncode == 0 else ""
            else:
                r = subprocess.run(
                    ["zenity", "--file-selection", "--directory"],
                    capture_output=True, text=True, timeout=60,
                )
                return r.stdout.strip() if r.returncode == 0 else ""
        except Exception:
            return ""

    def open_folder(self, path):
        try:
            import sys
            if not os.path.exists(path):
                return
            if sys.platform == "darwin":
                subprocess.run(["open", path])
            elif sys.platform == "win32":
                subprocess.run(["explorer", path])
            else:
                subprocess.run(["xdg-open", path])
        except Exception:
            pass


# ═══════════════════════════════════════════════════════
#  HTML / CSS / JS — Liquid Glass Design
# ═══════════════════════════════════════════════════════

HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>CIE 试卷下载器</title>
<style>
/* ── Reset & Tokens ── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg-deep:#020203;--bg-surface:#0a0a0c;
  --glass:rgba(255,255,255,0.05);--glass-hover:rgba(255,255,255,0.08);
  --glass-b:rgba(255,255,255,0.08);--glass-border:rgba(255,255,255,0.07);
  --glass-border-s:rgba(255,255,255,0.12);
  --text:#EDEDEF;--muted:#8A8F98;--faint:rgba(255,255,255,0.3);
  --accent:#5E6AD2;--accent2:#4F46E5;
  --accent-glow:rgba(94,106,210,0.25);--accent-glass:rgba(94,106,210,0.12);
  --ok:#10B981;--err:#EF4444;--warn:#F59E0B;
  --r:14px;--rs:10px;--blur:saturate(180%) blur(24px);
  --ease:cubic-bezier(0.16,1,0.3,1);
  font-family:'Inter',-apple-system,'SF Pro Text','Helvetica Neue',sans-serif;
}
@font-face{font-family:'Inter';font-style:normal;font-weight:300 700;
  src:url(https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap);}
html,body{height:100%;overflow:hidden;background:var(--bg-deep);
  color:var(--text);-webkit-font-smoothing:antialiased;}

/* ── Background ── */
.bg{position:fixed;inset:0;z-index:0;
  background:radial-gradient(ellipse 80% 50% at 5% 5%,rgba(94,106,210,0.12),transparent 60%),
             radial-gradient(ellipse 60% 50% at 95% 95%,rgba(79,70,229,0.08),transparent 60%),
             radial-gradient(ellipse 50% 40% at 50% 50%,rgba(14,165,233,0.04),transparent 60%),
             var(--bg-deep);}
.orb{position:fixed;border-radius:50%;pointer-events:none;}
.o1{width:600px;height:600px;top:-120px;left:-100px;
    background:radial-gradient(circle,rgba(94,106,210,0.15),transparent 70%);filter:blur(80px);}
.o2{width:450px;height:450px;bottom:-100px;right:-80px;
    background:radial-gradient(circle,rgba(124,58,237,0.1),transparent 70%);filter:blur(80px);}
.o3{width:350px;height:350px;top:45%;left:48%;
    background:radial-gradient(circle,rgba(14,165,233,0.06),transparent 70%);filter:blur(60px);}

/* ── Glass base ── */
.g{background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
   border:1px solid var(--glass-border);border-radius:var(--r);}
.gs{background:var(--glass-b);backdrop-filter:saturate(200%) blur(30px);
    -webkit-backdrop-filter:saturate(200%) blur(30px);
    border:1px solid var(--glass-border-s);border-radius:var(--r);}

/* ── Layout ── */
.app{position:relative;z-index:1;display:flex;flex-direction:column;
     height:100vh;padding:12px;gap:8px;}

/* ── Header ── */
.hdr{display:flex;align-items:center;gap:10px;padding:10px 20px;flex-shrink:0;}
.hdr-icon svg{width:20px;height:20px;stroke:var(--accent);}
.hdr-title{font-size:16px;font-weight:700;letter-spacing:-0.3px;}
.badge{background:var(--accent-glass);color:var(--accent);font-size:10px;font-weight:600;
       padding:2px 10px;border-radius:20px;border:1px solid rgba(94,106,210,0.2);}
.hdr-status{margin-left:auto;font-size:11px;color:var(--muted);display:flex;align-items:center;gap:6px;}
.hdr-dot{width:6px;height:6px;border-radius:50%;}
.hdr-dot.ok{background:var(--ok);box-shadow:0 0 6px var(--ok);}
.hdr-dot.err{background:var(--err);box-shadow:0 0 6px var(--err);}
.hdr-dot.idle{background:var(--muted);}

/* ── Mode pills ── */
.modes{display:flex;gap:4px;flex-shrink:0;padding:4px;justify-content:center;}
.mode{flex:0 1 200px;padding:7px 16px;border:none;border-radius:var(--rs);background:transparent;
      color:var(--muted);font-size:12px;font-weight:500;cursor:pointer;transition:all .2s var(--ease);}
.mode:hover{color:var(--text);background:var(--glass-hover);}
.mode.on{background:var(--accent-glass);color:var(--accent);font-weight:600;}

/* ── Panels ── */
.panel{display:none;flex-direction:column;gap:8px;flex:1;min-height:0;overflow:hidden;}
.panel.on{display:flex;}

/* ── Controls ── */
.ctrl{padding:14px 16px;flex-shrink:0;}
.row{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap;}
.fld{display:flex;flex-direction:column;gap:5px;}
.fld.grow{flex:1;min-width:160px;}
.lbl{font-size:9px;color:var(--muted);font-weight:600;
     text-transform:uppercase;letter-spacing:.6px;}

/* ── Inputs ── */
select,input[type=text]{background:rgba(255,255,255,0.05);border:1px solid var(--glass-border);
  border-radius:var(--rs);color:var(--text);font-size:12px;padding:7px 10px;outline:none;
  width:100%;transition:border-color .2s var(--ease),box-shadow .2s var(--ease);}
select{appearance:none;-webkit-appearance:none;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%238A8F98' stroke-width='2'%3E%3Cpolyline points='6 9 12 15 18 9'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:right 9px center;padding-right:28px;}
select option{background:#14141a;color:var(--text);}
select:focus,input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-glow);}

/* ── Buttons ── */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:8px 16px;
     border-radius:var(--rs);font-size:12px;font-weight:600;cursor:pointer;border:none;
     transition:all .2s var(--ease);white-space:nowrap;font-family:inherit;}
.btn:active{transform:scale(0.97);}
.btn-pri{background:var(--accent);color:#fff;box-shadow:0 2px 10px var(--accent-glow);}
.btn-pri:hover{background:#6D7AEB;box-shadow:0 4px 16px var(--accent-glow);}
.btn-sec{background:rgba(255,255,255,0.06);border:1px solid var(--glass-border);color:var(--text);}
.btn-sec:hover{background:var(--glass-hover);border-color:var(--glass-border-s);}
.btn-ok{background:linear-gradient(135deg,#059669,#10b981);color:#fff;box-shadow:0 2px 10px rgba(16,185,129,0.25);}
.btn-ok:hover{box-shadow:0 4px 18px rgba(16,185,129,0.4);}
.btn-err{background:linear-gradient(135deg,#dc2626,#ef4444);color:#fff;box-shadow:0 2px 10px rgba(239,68,68,0.2);}
.btn-err:hover{box-shadow:0 4px 18px rgba(239,68,68,0.35);}
.btn-sm{padding:5px 11px;font-size:11px;}
.btn:disabled{opacity:.35;cursor:not-allowed;transform:none!important;box-shadow:none!important;}

/* ── Toolbar ── */
.tbar{display:flex;align-items:center;gap:6px;margin-bottom:8px;flex-shrink:0;}
.tbar-r{margin-left:auto;font-size:11px;color:var(--muted);}

/* ── Result list ── */
.rlist-wrap{flex:1;overflow-y:auto;min-height:0;
            border:1px solid var(--glass-border);border-radius:var(--rs);}
.rlist-wrap::-webkit-scrollbar,.dlwrap::-webkit-scrollbar,.prev::-webkit-scrollbar{width:4px;}
.rlist-wrap::-webkit-scrollbar-thumb,.dlwrap::-webkit-scrollbar-thumb,.prev::-webkit-scrollbar-thumb{
  background:rgba(255,255,255,0.08);border-radius:2px;}
.rhead{display:grid;grid-template-columns:36px 1fr 1fr 32px;gap:8px;padding:7px 12px;
  background:rgba(255,255,255,0.02);border-bottom:1px solid var(--glass-border);
  font-size:9px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;
  position:sticky;top:0;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);}
.rgrp-hdr{padding:6px 12px;font-size:11px;font-weight:600;color:var(--accent);
  background:var(--accent-glass);border-bottom:1px solid var(--glass-border);
  cursor:pointer;display:flex;align-items:center;gap:6px;transition:background .15s;}
.rgrp-hdr:hover{background:rgba(94,106,210,0.18);}
.rrow{display:grid;grid-template-columns:36px 1fr 1fr 32px;gap:8px;padding:7px 12px;
  border-bottom:1px solid var(--glass-border);font-size:12px;align-items:center;
  transition:background .12s;}
.rrow:hover{background:var(--glass-hover);}
.rrow .chk-col{display:flex;align-items:center;gap:2px;}
.cb{display:flex;align-items:center;justify-content:center;width:20px;height:20px;
    border-radius:5px;border:1.5px solid var(--glass-border);cursor:pointer;
    transition:all .15s var(--ease);font-size:11px;color:transparent;flex-shrink:0;}
.cb.on{background:var(--accent);border-color:var(--accent);color:#fff;}
.cb.dim{opacity:.25;cursor:not-allowed;}
.fname{font-family:'JetBrains Mono','SF Mono','Menlo',monospace;font-size:11px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.fname.exist{color:var(--text);}
.fname.miss{color:var(--muted);opacity:.35;}
.fok{color:var(--ok);font-size:13px;}.fno{color:var(--muted);font-size:13px;opacity:.3;}

/* ── Batch ── */
.bgrid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:10px;}
.bsec-t{font-size:9px;color:var(--muted);font-weight:600;
  text-transform:uppercase;letter-spacing:.6px;margin-bottom:7px;}
.cbgrp{display:flex;gap:7px;flex-wrap:wrap;}
.cbitem{display:flex;align-items:center;gap:5px;cursor:pointer;font-size:11px;
  padding:5px 10px;border-radius:6px;border:1px solid var(--glass-border);
  transition:all .15s var(--ease);user-select:none;}
.cbitem:hover{background:var(--glass-hover);}
.cbitem.on{background:var(--accent-glass);border-color:rgba(94,106,210,0.25);}
input[type=checkbox]{accent-color:var(--accent);width:13px;height:13px;cursor:pointer;}
.srow{display:flex;align-items:center;gap:8px;}
input[type=range]{flex:1;height:4px;border-radius:2px;
  background:rgba(255,255,255,0.12);accent-color:var(--accent);cursor:pointer;}
.sval{font-size:11px;color:var(--muted);width:36px;text-align:right;font-variant-numeric:tabular-nums;}

/* ── Preview ── */
.prev{flex:1;overflow-y:auto;min-height:0;background:rgba(0,0,0,0.2);
  border:1px solid var(--glass-border);border-radius:var(--rs);padding:12px;
  font-family:'JetBrains Mono','SF Mono','Menlo',monospace;font-size:11px;line-height:1.8;
  color:var(--muted);white-space:pre-wrap;}
.py{color:var(--accent);font-weight:600;}.pf{color:rgba(255,255,255,0.6);}

/* ── Download bar (global bottom) ── */
.dlbar{padding:11px 18px;display:flex;align-items:center;gap:14px;flex-shrink:0;}
.dir-row{display:flex;align-items:center;gap:8px;flex:1;min-width:0;}
.dir-disp{flex:1;min-width:0;background:rgba(255,255,255,0.04);
  border:1px solid var(--glass-border);border-radius:6px;color:var(--muted);
  font-size:11px;font-family:'JetBrains Mono','SF Mono','Menlo',monospace;
  padding:6px 10px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.chk-row{display:flex;align-items:center;gap:6px;font-size:11px;color:var(--muted);
         cursor:pointer;user-select:none;}
.chk-row input{cursor:pointer;}
.prog-sec{display:flex;align-items:center;gap:10px;flex-shrink:0;}
.prog-wrap{width:130px;height:4px;background:rgba(255,255,255,0.08);
  border-radius:2px;overflow:hidden;}
.prog-fill{height:100%;width:0%;border-radius:2px;
  background:linear-gradient(90deg,var(--accent2),var(--accent));
  transition:width .35s var(--ease);}
.stat{font-size:11px;color:var(--muted);white-space:nowrap;min-width:90px;}

/* ── Download overlay panel ── */
.dl-overlay{display:none;flex-direction:column;height:180px;background:var(--glass);
  backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border-top:1px solid var(--glass-border);border-radius:var(--r) var(--r) 0 0;
  flex-shrink:0;overflow:hidden;transition:height .3s var(--ease);}
.dl-overlay.on{display:flex;}
.dl-overlay.expanded{height:340px;}
.dlsummary{display:flex;align-items:center;gap:12px;padding:8px 18px;
  border-bottom:1px solid var(--glass-border);flex-shrink:0;font-size:11px;}
.cnt-ok{color:var(--ok);font-weight:600;}
.cnt-err{color:var(--err);font-weight:600;}
.cnt-pnd{color:var(--muted);}
.cnt-dl{color:var(--accent);font-weight:600;}
.dlwrap{flex:1;overflow-y:auto;min-height:0;}
.dlrow{display:grid;
  grid-template-columns:24px 1fr 42px 70px 48px minmax(60px,1fr) 54px;
  gap:6px;padding:6px 18px;border-bottom:1px solid var(--glass-border);
  font-size:11px;align-items:center;transition:background .12s;}
.dlrow:hover{background:var(--glass-hover);}
.dlrow.downloading{background:rgba(94,106,210,0.06);}
.dlrow.failed{background:rgba(239,68,68,0.05);}
.dlrow .ico{font-size:12px;text-align:center;}
.dlrow .dl-fname{font-family:'JetBrains Mono','SF Mono','Menlo',monospace;font-size:10px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text);}
.dl-fname.dim{color:var(--muted);}
.type-QP{background:rgba(94,106,210,0.18);color:#a5b4fc;
  padding:2px 6px;border-radius:4px;font-size:9px;font-weight:700;text-align:center;}
.type-MS{background:rgba(16,185,129,0.18);color:#6ee7b7;
  padding:2px 6px;border-radius:4px;font-size:9px;font-weight:700;text-align:center;}
.dl-stat{font-size:10px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.dl-stat.s-pnd{color:var(--muted);}.dl-stat.s-dl{color:var(--accent);}
.dl-stat.s-ok{color:var(--ok);}.dl-stat.s-err{color:var(--err);}

/* ── Spinner ── */
.spin{display:inline-block;width:12px;height:12px;
  border:2px solid rgba(255,255,255,0.15);border-top-color:var(--accent);
  border-radius:50%;animation:sp .6s linear infinite;vertical-align:middle;}
@keyframes sp{to{transform:rotate(360deg)}}

/* ── Empty state ── */
.empty{display:flex;flex-direction:column;align-items:center;
  justify-content:center;height:100%;gap:8px;color:var(--muted);}
.empty svg{width:32px;height:32px;stroke:var(--muted);opacity:.3;}

/* ── Toast ── */
#toasts{position:fixed;top:14px;right:14px;z-index:999;
  display:flex;flex-direction:column;gap:6px;pointer-events:none;}
.toast{background:rgba(10,10,14,0.97);
  backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);
  border:1px solid var(--glass-border);border-radius:10px;
  padding:10px 14px;font-size:12px;min-width:200px;
  display:flex;gap:8px;align-items:flex-start;
  animation:tin .25s var(--ease);pointer-events:auto;}
.toast.ok{border-left:3px solid var(--ok);}
.toast.err{border-left:3px solid var(--err);}
.toast.warn{border-left:3px solid var(--warn);}
@keyframes tin{from{transform:translateX(110%);opacity:0}}

/* ── Reduced motion ── */
@media(prefers-reduced-motion:reduce){
  *,*::before,*::after{animation-duration:0.01ms!important;transition-duration:0.01ms!important;}
}
</style>
</head>
<body>

<div class="bg"></div>
<div class="orb o1"></div><div class="orb o2"></div><div class="orb o3"></div>
<div id="toasts"></div>

<div class="app">

  <!-- Header -->
  <header class="hdr g">
    <span class="hdr-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/><line x1="8" y1="7" x2="16" y2="7"/><line x1="8" y1="11" x2="14" y2="11"/></svg></span>
    <span class="hdr-title">CIE 试卷下载器</span>
    <span class="badge">v4.0</span>
    <span class="hdr-status">
      <span class="hdr-dot idle" id="hdr-dot"></span>
      <span id="hdr-st">加载中...</span>
    </span>
  </header>

  <!-- Mode pills -->
  <div class="modes">
    <button class="mode on" id="mode-search" onclick="switchMode('search')">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
      按次搜索
    </button>
    <button class="mode" id="mode-batch" onclick="switchMode('batch')">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
      批量下载
    </button>
  </div>

  <!-- ══ Search Panel ══ -->
  <div class="panel on" id="pnl-search">
    <div class="ctrl g">
      <div class="row">
        <div class="fld grow">
          <label class="lbl">科目</label>
          <select id="s-subj"><option>加载中...</option></select>
        </div>
        <div class="fld">
          <label class="lbl">年份</label>
          <select id="s-year" style="width:85px"></select>
        </div>
        <div class="fld">
          <label class="lbl">季度</label>
          <select id="s-seas" style="width:115px">
            <option value="Mar">Mar 春季</option>
            <option value="Jun">Jun 夏季</option>
            <option value="Nov" selected>Nov 冬季</option>
          </select>
        </div>
        <div class="fld">
          <label class="lbl">&nbsp;</label>
          <button class="btn btn-pri" id="sbtn" onclick="doSearch()">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
            搜索
          </button>
        </div>
      </div>
    </div>

    <div class="gs" style="flex:1;min-height:0;padding:12px 16px;display:flex;flex-direction:column;overflow:hidden;">
      <div class="tbar">
        <button class="btn btn-sec btn-sm" onclick="selAll()">全选</button>
        <button class="btn btn-sec btn-sm" onclick="deselAll()">全不选</button>
        <button class="btn btn-sec btn-sm" onclick="selQP()">仅 QP</button>
        <button class="btn btn-sec btn-sm" onclick="selMS()">仅 MS</button>
        <span class="tbar-r" id="rcnt">共 0 项</span>
      </div>
      <div class="rhead"><div></div><div>题卷 QP</div><div>答案 MS</div><div></div></div>
      <div class="rlist-wrap" id="rlist">
        <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg><div>搜索后显示结果</div></div>
      </div>
    </div>
  </div>

  <!-- ══ Batch Panel ══ -->
  <div class="panel" id="pnl-batch">
    <div class="ctrl g" style="flex-shrink:0">
      <div class="row">
        <div class="fld grow">
          <label class="lbl">科目</label>
          <select id="b-subj"><option>加载中...</option></select>
        </div>
        <div class="fld">
          <label class="lbl">年份从</label>
          <select id="b-yfrom" style="width:85px"></select>
        </div>
        <div class="fld">
          <label class="lbl">到</label>
          <select id="b-yto" style="width:85px"></select>
        </div>
      </div>
      <div class="bgrid">
        <div>
          <div class="bsec-t">季度</div>
          <div class="cbgrp">
            <label class="cbitem on"><input type="checkbox" value="Mar" checked onchange="syncCB(this)"> Mar 春</label>
            <label class="cbitem on"><input type="checkbox" value="Jun" checked onchange="syncCB(this)"> Jun 夏</label>
            <label class="cbitem on"><input type="checkbox" value="Nov" checked onchange="syncCB(this)"> Nov 冬</label>
          </div>
        </div>
        <div>
          <div class="bsec-t">试卷类型</div>
          <div class="cbgrp">
            <label class="cbitem on"><input type="checkbox" value="1" checked onchange="syncCB(this)"> Paper 1</label>
            <label class="cbitem on"><input type="checkbox" value="2" checked onchange="syncCB(this)"> Paper 2</label>
            <label class="cbitem on"><input type="checkbox" value="3" checked onchange="syncCB(this)"> Paper 3</label>
            <label class="cbitem on"><input type="checkbox" value="4" checked onchange="syncCB(this)"> Paper 4</label>
            <label class="cbitem on"><input type="checkbox" value="5" checked onchange="syncCB(this)"> Paper 5</label>
            <label class="cbitem on"><input type="checkbox" value="6" checked onchange="syncCB(this)"> Paper 6</label>
          </div>
        </div>
      </div>
      <div style="display:flex;align-items:center;gap:16px;margin-top:12px;flex-wrap:wrap;">
        <div style="display:flex;align-items:center;gap:8px;">
          <label class="lbl">速度 (req/s)</label>
          <div class="srow" style="width:120px">
            <input type="range" id="b-rate" min="2" max="10" step="1" value="5"
                   oninput="document.getElementById('rv').textContent=this.value+'/s'">
            <span class="sval" id="rv">5/s</span>
          </div>
        </div>
        <div style="display:flex;align-items:center;gap:8px;">
          <label class="lbl">线程</label>
          <select id="b-thr" style="width:65px">
            <option>2</option><option selected>4</option><option>6</option>
          </select>
        </div>
        <label class="cbitem" id="merge-cb">
          <input type="checkbox" id="b-merge" onchange="syncCB(this)"> 同一文件夹
        </label>
        <div style="margin-left:auto;display:flex;gap:8px;">
          <button class="btn btn-sec" id="pvbtn" onclick="doPreview()">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
            预览
          </button>
          <button class="btn btn-pri" id="bdbtn" onclick="doBatchDL()">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            开始下载
          </button>
        </div>
      </div>
    </div>
    <div class="gs" style="flex:1;min-height:0;padding:12px 16px;display:flex;flex-direction:column;overflow:hidden;">
      <div class="bsec-t">预览</div>
      <div class="prev" id="prev">（点击「预览」查看将要下载的文件...）</div>
    </div>
  </div>

  <!-- ══ Download bar (global, always visible) ══ -->
  <div class="dlbar g">
    <div class="dir-row">
      <label class="lbl">保存到</label>
      <div class="dir-disp" id="dir-disp"></div>
      <button class="btn btn-sec btn-sm" onclick="browseDir()">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
      </button>
      <button class="btn btn-sec btn-sm" onclick="openDir()">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
      </button>
    </div>
    <label class="chk-row" id="ms-chk-row" title="下载时是否包含答案 (MS) 文件">
      <input type="checkbox" id="dl-ms" checked onchange="syncMS(this)">
      <span>包含 MS</span>
    </label>
    <div class="prog-sec">
      <div class="prog-wrap"><div class="prog-fill" id="prog"></div></div>
      <span class="stat" id="stat">就绪</span>
    </div>
    <button class="btn btn-ok" id="dlbtn" onclick="doDownloadSel()">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
      下载选中
    </button>
  </div>

  <!-- ══ Download overlay panel (sits between content and download bar) ══ -->
  <div class="dl-overlay" id="dl-overlay">
    <div class="dlsummary">
      <span style="font-weight:600" id="dl-total">共 0 项</span>
      <span class="cnt-dl" id="dl-cnt-dl">⬇ 0</span>
      <span class="cnt-ok" id="dl-cnt-ok">✓ 0</span>
      <span class="cnt-err" id="dl-cnt-err">✗ 0</span>
      <span class="cnt-pnd" id="dl-cnt-pnd">⏳ 0</span>
      <div style="margin-left:auto;display:flex;gap:6px;">
        <button class="btn btn-err btn-sm" id="retry-all-btn" onclick="retryAll()">↺ 重试失败</button>
        <button class="btn btn-sec btn-sm" onclick="clearDLList()">清空</button>
        <button class="btn btn-sec btn-sm" id="expand-btn" onclick="toggleExpand()">
          <svg width="12" height="12" id="expand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
        </button>
      </div>
    </div>
    <div class="dlwrap" id="dllist">
      <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>下载后在此查看进度</div></div>
    </div>
  </div>

</div><!-- .app -->

<script>
// ── Lucide SVG icons ──────────────────────────────────
const ICO={check:'<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'};

// ── State ─────────────────────────────────────────────
const S={
  subjects:[], groups:[], selected:{}, // selected: {groupIndex: {qp:bool, ms:bool}}
  bGroups:[], saveDir:'', poll:null, dlRendered:false, expanded:false,
};

// ── Init ──────────────────────────────────────────────
window.addEventListener('pywebviewready',async()=>{
  const now=new Date().getFullYear();
  const yrs=Array.from({length:now-1999},(_,i)=>now-i);
  ['s-year','b-yfrom','b-yto'].forEach(id=>{
    const sel=document.getElementById(id);
    yrs.forEach(y=>sel.add(new Option(y,y)));
    sel.value=id==='b-yfrom'?now-2:now;
  });
  S.saveDir=await pywebview.api.get_default_dir();
  document.getElementById('dir-disp').textContent=S.saveDir;
  try{
    const r=JSON.parse(await pywebview.api.get_subjects());
    if(!r.ok)throw new Error(r.error);
    S.subjects=r.data;
    const opts=r.data.map(s=>`<option value="${s.value}">${s.value} — ${s.text}</option>`).join('');
    document.getElementById('s-subj').innerHTML=opts;
    document.getElementById('b-subj').innerHTML=opts;
    document.getElementById('hdr-st').textContent=`${r.data.length} 个科目`;
    setStat('就绪');setDot('idle');
  }catch(e){
    toast('加载科目失败: '+e.message,'err');
    document.getElementById('hdr-st').textContent='加载失败';
    setDot('err');
  }
});

// ── Mode ──────────────────────────────────────────────
function switchMode(name){
  ['search','batch'].forEach(n=>{
    document.getElementById('mode-'+n).classList.toggle('on',n===name);
    document.getElementById('pnl-'+n).classList.toggle('on',n===name);
  });
}

// ── Search ────────────────────────────────────────────
async function doSearch(){
  const subj=document.getElementById('s-subj').value;
  const year=document.getElementById('s-year').value;
  const seas=document.getElementById('s-seas').value;
  if(!subj)return toast('请选择科目','err');
  setBusy('sbtn','<span class="spin"></span> 搜索中…',true);
  setStat('搜索中…');
  try{
    const r=JSON.parse(await pywebview.api.search(subj,year,seas));
    if(!r.ok)throw new Error(r.error);
    S.groups=r.groups;
    // Init selected: true for all files that exist
    S.selected={};
    r.groups.forEach((g,i)=>{
      S.selected[i]={};
      if(g.qp)S.selected[i].qp=true;
      if(g.ms)S.selected[i].ms=true;
    });
    renderResults();
    setStat(`找到 ${r.count} 个文件`);
    document.getElementById('hdr-st').textContent=`${r.groups.length} 组试卷`;
    setDot('idle');
  }catch(e){toast('搜索失败: '+e.message,'err');setStat('失败');setDot('err');}
  finally{setBusy('sbtn','搜索',false,'btn-pri');}
}

function renderResults(){
  const el=document.getElementById('rlist');
  if(!S.groups.length){
    el.innerHTML='<div class="empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="8" rx="2" ry="2"/><rect x="2" y="14" width="20" height="8" rx="2" ry="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg><div>未找到试卷</div></div>';
    document.getElementById('rcnt').textContent='共 0 项';return;
  }
  const byPG={};
  S.groups.forEach((g,i)=>{const pg=g.paper_group||0;(byPG[pg]=byPG[pg]||[]).push([i,g]);});
  let html='';
  Object.keys(byPG).sort((a,b)=>+a-+b).forEach(pg=>{
    const label=+pg>0?`Paper ${pg}`:'其他',items=byPG[pg];
    html+=`<div class="rgrp" data-pg="${pg}">
      <div class="rgrp-hdr" onclick="toggleGrp(${pg})">
        ▾ ${label} <span style="color:var(--muted);font-weight:400">(${items.length} 项)</span>
      </div>`;
    items.forEach(([i,g])=>{
      const sqp=S.selected[i]&&S.selected[i].qp?'on':'';
      const sms=S.selected[i]&&S.selected[i].ms?'on':'';
      const qp=g.qp?g.qp.replace('.pdf',''):null;
      const ms=g.ms?g.ms.replace('.pdf',''):null;
      const ok=(g.qp&&g.ms)?'<span class="fok">✓</span>':'<span class="fno">!</span>';
      html+=`<div class="rrow" data-i="${i}">
        <div class="chk-col">
          <div class="cb ${sqp}" onclick="event.stopPropagation();toggleCB(${i},'qp')" title="QP">${sqp?ICO.check:''}</div>
          <div class="cb ${sms}${!g.ms?' dim':''}" onclick="${g.ms?'event.stopPropagation();toggleCB('+i+',\'ms\')':''}" title="MS">${sms?ICO.check:''}</div>
        </div>
        <span class="fname ${qp?'fname exist':'fname miss'}">${qp||'—'}</span>
        <span class="fname ${ms?'fname exist':'fname miss'}">${ms||'—'}</span>
        ${ok}
      </div>`;
    });
    html+='</div>';
  });
  el.innerHTML=html;updateCount();
}

function toggleCB(i,ftype){
  if(!S.selected[i])S.selected[i]={};
  S.selected[i][ftype]=!(S.selected[i][ftype]);
  // Update the checkbox visually
  const row=document.querySelector(`.rrow[data-i="${i}"]`);
  if(!row)return;
  const cb=row.querySelectorAll('.cb')[ftype==='qp'?0:1];
  const on=S.selected[i][ftype];
  cb.classList.toggle('on',on);
  cb.innerHTML=on?ICO.check:'';
  updateCount();
}

function toggleGrp(pg){
  const rows=[...document.querySelectorAll(`.rgrp[data-pg="${pg}"] .rrow`)];
  const anyOff=rows.some(r=>{
    const i=+r.dataset.i;
    const g=S.groups[i];if(!g)return false;
    const qpOn=S.selected[i]&&S.selected[i].qp;
    const msOn=S.selected[i]&&S.selected[i].ms;
    return (g.qp&&!qpOn)||(g.ms&&!msOn);
  });
  rows.forEach(r=>{
    const i=+r.dataset.i;if(!S.selected[i])S.selected[i]={};
    const g=S.groups[i];if(!g)return;
    if(g.qp)S.selected[i].qp=anyOff;
    if(g.ms)S.selected[i].ms=anyOff;
    const cbs=r.querySelectorAll('.cb');
    ['qp','ms'].forEach((ft,idx)=>{
      const on=S.selected[i][ft];
      cbs[idx].classList.toggle('on',!!on);
      cbs[idx].innerHTML=on?ICO.check:'';
    });
  });updateCount();
}

function selAll(){
  S.groups.forEach((g,i)=>{S.selected[i]={};if(g.qp)S.selected[i].qp=true;if(g.ms)S.selected[i].ms=true;});
  document.querySelectorAll('.cb').forEach(cb=>{cb.classList.add('on');cb.innerHTML=ICO.check;});
  updateCount();
}
function deselAll(){
  S.groups.forEach((_,i)=>{S.selected[i]={qp:false,ms:false};});
  document.querySelectorAll('.cb').forEach(cb=>{cb.classList.remove('on');cb.innerHTML='';});
  updateCount();
}
function selQP(){
  S.groups.forEach((g,i)=>{S.selected[i]={qp:!!g.qp,ms:false};});
  document.querySelectorAll('.rrow').forEach(r=>{
    const i=+r.dataset.i;const g=S.groups[i];if(!g)return;
    const cbs=r.querySelectorAll('.cb');
    cbs[0].classList.toggle('on',!!g.qp);cbs[0].innerHTML=g.qp?ICO.check:'';
    cbs[1].classList.remove('on');cbs[1].innerHTML='';
  });updateCount();
}
function selMS(){
  S.groups.forEach((g,i)=>{S.selected[i]={qp:false,ms:!!g.ms};});
  document.querySelectorAll('.rrow').forEach(r=>{
    const i=+r.dataset.i;const g=S.groups[i];if(!g)return;
    const cbs=r.querySelectorAll('.cb');
    cbs[0].classList.remove('on');cbs[0].innerHTML='';
    cbs[1].classList.toggle('on',!!g.ms);cbs[1].innerHTML=g.ms?ICO.check:'';
  });updateCount();
}

function countSelected(){
  let n=0;
  S.groups.forEach((g,i)=>{
    if(S.selected[i]&&S.selected[i].qp&&g.qp)n++;
    if(S.selected[i]&&S.selected[i].ms&&g.ms)n++;
  });
  return n;
}
function updateCount(){
  const tot=S.groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0);
  document.getElementById('rcnt').textContent=`共 ${tot} 文件，已选 ${countSelected()} 个`;
}

// ── Batch Preview ────────────────────────────────────
async function doPreview(){
  const code=document.getElementById('b-subj').value;
  const yFrom=+document.getElementById('b-yfrom').value;
  const yTo=+document.getElementById('b-yto').value;
  if(!code)return toast('请选择科目','err');
  if(yFrom>yTo)return toast('年份范围有误','err');
  const seasons=[...document.querySelectorAll('#pnl-batch .cbgrp input:checked')]
    .filter(el=>'Mar Jun Nov'.includes(el.value)).map(el=>el.value);
  const pgs=[...document.querySelectorAll('#pnl-batch .cbgrp input:checked')]
    .map(el=>+el.value).filter(v=>v>=1&&v<=6);
  if(!seasons.length)return toast('请至少选一个季度','err');
  ['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=true;});
  document.getElementById('pvbtn').innerHTML='<span class="spin"></span> 搜索中…';
  setStat('预览中…');
  try{
    const r=JSON.parse(await pywebview.api.batch_preview(
      JSON.stringify({code,year_from:yFrom,year_to:yTo,seasons,pgs})
    ));
    if(!r.ok)throw new Error(r.error);
    S.bGroups=r.groups;
    if(r.warnings&&r.warnings.length){
      toast(`预览完成，${r.warnings.length} 个查询失败`,'warn');
    }
    renderPreview(r.groups);
    setStat(`预览: ${r.groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0)} 个文件`);
  }catch(e){toast('预览失败: '+e.message,'err');setStat('失败');}
  finally{
    ['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=false;});
    document.getElementById('pvbtn').innerHTML='预览';
  }
}

function renderPreview(groups){
  if(!groups.length){document.getElementById('prev').innerHTML='<span style="color:var(--muted)">(无结果）</span>';return;}
  const byY={};
  groups.forEach(g=>{
    const sy=g.sy||'';let y=sy.length>1?sy.slice(1):'?';
    if(/^\d{2}$/.test(y))y='20'+y;(byY[y]=byY[y]||[]).push(g);
  });
  const el=document.getElementById('prev');el.innerHTML='';
  Object.keys(byY).sort((a,b)=>+a-+b).forEach(y=>{
    const d=document.createElement('div');
    d.innerHTML=`<span class="py">── ${y} 年 (${byY[y].length} 组) ──</span>\n`;
    byY[y].forEach(g=>{
      const ln=document.createElement('div');ln.className='pf';
      ln.textContent=g.number?`  P${g.number}  ${(g.qp||'-').replace('.pdf','')}  +  ${(g.ms||'-').replace('.pdf','')}`
        :`  ${Object.values(g.files||{}).join(' ')}`;
      d.appendChild(ln);
    });
    d.appendChild(document.createTextNode('\n'));el.appendChild(d);
  });
}

// ── Downloads ─────────────────────────────────────────
async function doBatchDL(){
  if(!S.bGroups.length)return toast('请先点击预览','err');
  if(!S.saveDir)return toast('请选择保存目录','err');
  startDL(S.bGroups,{
    merge:document.getElementById('b-merge').checked,
    include_ms:document.getElementById('dl-ms').checked,
    rate:+document.getElementById('b-rate').value,
    threads:+document.getElementById('b-thr').value,
  });
}
async function doDownloadSel(){
  const sel=[];let any=false;
  S.groups.forEach((g,i)=>{
    const qpOn=S.selected[i]&&S.selected[i].qp&&g.qp;
    const msOn=S.selected[i]&&S.selected[i].ms&&g.ms;
    if(qpOn||msOn){
      any=true;
      sel.push(Object.assign({},g,
        qpOn?{qp:g.qp}:{qp:null},
        msOn?{ms:g.ms}:{ms:null}
      ));
    }
  });
  if(!any)return toast('请先选择文件','err');
  if(!S.saveDir)return toast('请选择保存目录','err');
  startDL(sel,{
    merge:false,
    include_ms:document.getElementById('dl-ms').checked,
    rate:5.0,
    threads:4,
  });
}
async function startDL(groups,options){
  S.dlRendered=false;
  setAllDis(true);setProgress(0);setStat('准备下载…');
  document.getElementById('dl-overlay').classList.add('on');
  document.getElementById('expand-btn').style.display='';
  try{
    const r=JSON.parse(await pywebview.api.start_download(
      JSON.stringify(groups),S.saveDir,JSON.stringify(options)
    ));
    if(!r.ok)throw new Error(r.error);
    startPoll();
  }catch(e){toast('启动失败: '+e.message,'err');setAllDis(false);}
}

// ── Poll ──────────────────────────────────────────────
function startPoll(){
  if(S.poll)clearInterval(S.poll);
  S.poll=setInterval(doPoll,700);
}
async function doPoll(){
  try{
    const [stJson,listJson]=await Promise.all([
      pywebview.api.get_status(),pywebview.api.get_download_list(),
    ]);
    const st=JSON.parse(stJson);
    const items=JSON.parse(listJson);
    setStat(st.message);
    if(st.total>0)setProgress(st.done/st.total*100);
    updateDLList(items);
    if(st.phase==='done'){
      clearInterval(S.poll);setProgress(100);setAllDis(false);
      setDot('idle');
      const fail=items.filter(i=>i.status==='failed').length;
      if(!fail)toast(`下载完成! 共 ${st.success} 个文件`,'ok');
      else toast(`完成 ${st.success} 个, 失败 ${fail} 个`,'warn');
    }else{setDot('running');}
  }catch(e){clearInterval(S.poll);setAllDis(false);setDot('idle');}
}

// ── DL list rendering ─────────────────────────────────
const DL_ICON={pending:'⏳',downloading:'⬇',done:'✓',failed:'✗'};
const DL_STAT_TXT={pending:'等待',downloading:'下载中',done:'完成',};
function dlStatClass(s){return{pending:'s-pnd',downloading:'s-dl',done:'s-ok',failed:'s-err'}[s]||'s-pnd';}

function renderDLListFull(items){
  const el=document.getElementById('dllist');
  if(!items.length){
    el.innerHTML='<div class="empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>下载后在此查看进度</div></div>';
    return;
  }
  el.innerHTML=items.map(it=>`
    <div class="dlrow ${it.status}" data-id="${it.id}" data-status="${it.status}" data-err="${it.error||''}">
      <span class="ico">${DL_ICON[it.status]||'⏳'}</span>
      <span class="dl-fname${it.status==='done'?' dim':''}" title="${it.filename}">${it.filename}</span>
      <span class="type-${it.ftype}">${it.ftype}</span>
      <span class="dl-label" title="${it.label}">${it.label}</span>
      <span class="dl-year">${it.year}</span>
      <span class="dl-stat ${dlStatClass(it.status)}">${it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'')}</span>
      <span>${it.status==='failed'?`<button class="btn btn-err btn-sm" onclick="retryItem(${it.id})">重试</button>`:''}</span>
    </div>`).join('');
  S.dlRendered=true;
}

function updateDLList(items){
  if(!S.dlRendered||!document.querySelector('.dlrow')){S.dlRendered=false;renderDLListFull(items);return;}
  items.forEach(it=>{
    const row=document.querySelector(`.dlrow[data-id="${it.id}"]`);
    if(!row)return;
    if(row.dataset.status===it.status&&row.dataset.err===it.error)return;
    row.dataset.status=it.status;row.dataset.err=it.error||'';
    row.className=`dlrow ${it.status}`;
    row.querySelector('.ico').textContent=DL_ICON[it.status]||'⏳';
    row.querySelector('.dl-fname').className=`dl-fname${it.status==='done'?' dim':''}`;
    const statEl=row.querySelector('.dl-stat');
    statEl.className=`dl-stat ${dlStatClass(it.status)}`;
    statEl.textContent=it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'');
    row.querySelector('span:last-child').innerHTML=it.status==='failed'
      ?`<button class="btn btn-err btn-sm" onclick="retryItem(${it.id})">重试</button>`:'';
    if(it.status==='downloading')row.scrollIntoView({block:'nearest',behavior:'smooth'});
  });
  updateDLSummary(items);
}

function updateDLSummary(items){
  const dl=items.filter(i=>i.status==='downloading').length;
  const ok=items.filter(i=>i.status==='done').length;
  const fail=items.filter(i=>i.status==='failed').length;
  const pend=items.filter(i=>i.status==='pending').length;
  document.getElementById('dl-total').textContent=`共 ${items.length} 项`;
  document.getElementById('dl-cnt-dl').textContent=`⬇ ${dl}`;
  document.getElementById('dl-cnt-ok').textContent=`✓ ${ok}`;
  document.getElementById('dl-cnt-err').textContent=`✗ ${fail}`;
  document.getElementById('dl-cnt-pnd').textContent=`⏳ ${pend}`;
  document.getElementById('dl-cnt-err').style.opacity=fail>0?'1':'0.4';
}

// ── Retry ─────────────────────────────────────────────
async function retryAll(){
  document.getElementById('retry-all-btn').disabled=true;
  const r=JSON.parse(await pywebview.api.retry_failed());
  if(!r.ok){toast(r.error,'err');document.getElementById('retry-all-btn').disabled=false;return;}
  if(r.count===0){toast('没有失败的项目','info');document.getElementById('retry-all-btn').disabled=false;return;}
  S.dlRendered=false;
  toast(`重试 ${r.count} 个失败项`,'info');
  startPoll();
}
async function retryItem(id){
  // Disable the clicked button to prevent double-click
  const btn=document.querySelector(`.dlrow[data-id="${id}"] .btn-err`);
  if(btn)btn.disabled=true;
  const r=JSON.parse(await pywebview.api.retry_item(id));
  if(!r.ok){toast(r.error,'err');if(btn)btn.disabled=false;return;}
  startPoll();
}
async function clearDLList(){
  const r=JSON.parse(await pywebview.api.clear_download_list());
  if(!r.ok){toast(r.error,'err');return;}
  S.dlRendered=false;
  document.getElementById('dllist').innerHTML='<div class="empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>下载后在此查看进度</div></div>';
  document.getElementById('dl-overlay').classList.remove('on');
  updateDLSummary([]);
  setProgress(0);setStat('就绪');setDot('idle');
}

function toggleExpand(){
  S.expanded=!S.expanded;
  document.getElementById('dl-overlay').classList.toggle('expanded',S.expanded);
  const icon=document.getElementById('expand-icon');
  icon.innerHTML=S.expanded
    ?'<polyline points="18 15 12 9 6 15"/>'
    :'<polyline points="6 9 12 15 18 9"/>';
}

// ── Dir ───────────────────────────────────────────────
async function browseDir(){
  const d=await pywebview.api.choose_directory();
  if(d){S.saveDir=d;document.getElementById('dir-disp').textContent=d;}
}
function openDir(){if(S.saveDir)pywebview.api.open_folder(S.saveDir);}

// ── Helpers ───────────────────────────────────────────
function setStat(msg){document.getElementById('stat').textContent=msg;}
function setProgress(p){document.getElementById('prog').style.width=p+'%';}
function setDot(s){
  const d=document.getElementById('hdr-dot');
  d.className='hdr-dot '+s;
  if(s==='running')d.classList.add('ok');
}
function setAllDis(dis){
  ['sbtn','pvbtn','bdbtn','dlbtn'].forEach(id=>{
    const b=document.getElementById(id);if(b)b.disabled=dis;
  });
}
function setBusy(id,html,dis,cls){
  const b=document.getElementById(id);if(!b)return;
  b.innerHTML=html;b.disabled=dis;
  if(cls)b.className='btn '+cls;
}
function syncCB(el){el.closest('.cbitem').classList.toggle('on',el.checked);}
function syncMS(el){el.closest('.chk-row').style.color=el.checked?'var(--muted)':'var(--err)';}
function toast(msg,type){
  const el=document.createElement('div');el.className=`toast ${type||'info'}`;
  const ico={ok:'✓',err:'✗',warn:'!',info:'i'}[type]||'';
  el.innerHTML=`<span style="font-weight:700">${ico}</span><span>${msg}</span>`;
  document.getElementById('toasts').appendChild(el);
  setTimeout(()=>el.style.opacity='0',3500);
  setTimeout(()=>el.remove(),3800);
}
</script>
</body>
</html>
"""


# ═══════════════════════════════════════════════════════
#  Entry
# ═══════════════════════════════════════════════════════

if __name__ == "__main__":
    api = API()
    window = webview.create_window(
        "CIE 试卷下载器 v4",
        html=HTML,
        js_api=api,
        width=1120, height=900,
        min_size=(900, 700),
        background_color="#020203",
    )
    api.window = window
    webview.start(debug=False)
