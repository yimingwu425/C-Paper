#!/usr/bin/env python3
"""C-Paper v5.1 — three-column desktop app (pywebview + requests)"""

import webview
import json, os, re, time, threading, shutil, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE_URL  = "https://cie.fraft.cn"
SEASONS   = [("Mar","春季"),("Jun","夏季"),("Nov","冬季")]
CACHE_DIR = os.path.expanduser("~/.cie_cache")
CACHE_TTL = 86400
CACHE_MAX = 200
USER_AGENT = "C-Paper/5.0 (Desktop)"
HISTORY_MAX = 2000


# ═══════════════════════════════════════════════════════
#  Persistence helpers
# ═══════════════════════════════════════════════════════

def _read_json(path, default=None):
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return default

def _write_json(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        pass


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
        files = sorted(
            [os.path.join(CACHE_DIR, f) for f in os.listdir(CACHE_DIR) if f.endswith(".json")],
            key=os.path.getmtime,
        )
        while len(files) >= CACHE_MAX:
            try: os.remove(files.pop(0))
            except OSError: pass
        path = os.path.join(CACHE_DIR, f"{key}.json")
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        pass


# ═══════════════════════════════════════════════════════
#  TokenBucket
# ═══════════════════════════════════════════════════════

class TokenBucket:
    def __init__(self, rate: float, capacity: int):
        self._rate = rate
        self._capacity = float(capacity)
        self._tokens = float(capacity)
        self._last_refill = time.monotonic()
        self._lock = threading.Lock()

    def acquire(self, tokens: float = 1.0) -> float:
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
#  CircuitBreaker
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
            if self._state == self.HALF_OPEN or self._failures >= self._threshold:
                self._state = self.OPEN


# ═══════════════════════════════════════════════════════
#  DownloadEngine
# ═══════════════════════════════════════════════════════

def create_session(proxy_url: str = "", max_retries: int = 5) -> requests.Session:
    retry = Retry(
        total=max_retries,
        backoff_factor=1.0,
        backoff_jitter=0.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"],
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_connections=10, pool_maxsize=10)
    s = requests.Session()
    s.headers["User-Agent"] = USER_AGENT
    if proxy_url:
        s.proxies = {"http": proxy_url, "https": proxy_url}
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    return s

class DownloadEngine:
    def __init__(self, rate: float = 5.0, capacity: int = 15, max_concurrent: int = 4):
        self.bucket = TokenBucket(rate, capacity)
        self._max_concurrent = max_concurrent
        self.semaphore = threading.BoundedSemaphore(max_concurrent)
        self.breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=30.0)
        self._lock = threading.Lock()
        self._stats = {"done": 0, "success": 0, "failed": 0}
        self._proxy_url = ""
        self._session_lock = threading.Lock()
        # Thread-local sessions for concurrent downloads
        self._tlocal = threading.local()

    def _get_worker_session(self) -> requests.Session:
        if not hasattr(self._tlocal, 'session') or self._tlocal.session is None:
            self._tlocal.session = create_session(self._proxy_url)
        return self._tlocal.session

    def update_rate(self, rate: float):
        self.bucket._rate = rate

    def update_concurrency(self, n: int):
        # Must only be called between download batches — NOT thread-safe if workers
        # are currently holding the old semaphore. Call from start_download() before
        # spawning worker threads is the safe call site.
        self._max_concurrent = n
        self.semaphore = threading.BoundedSemaphore(n)

    def download_one(self, filename: str, save_path: str) -> None:
        st = self.breaker.state
        if st == CircuitBreaker.OPEN:
            raise RuntimeError("断路器开启：服务器过载，请等待冷却 (30s)")
        self.bucket.acquire()
        with self.semaphore:
            url = f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"
            try:
                resp = self._get_worker_session().get(url, timeout=(10, 60), stream=True)
                resp.raise_for_status()
                os.makedirs(os.path.dirname(save_path) or ".", exist_ok=True)
                with open(save_path, "wb") as f:
                    shutil.copyfileobj(resp.raw, f)
                self.breaker.record_success()
            except requests.exceptions.HTTPError as e:
                code = e.response.status_code if e.response is not None else 0
                if code == 429:
                    self.bucket.drain()
                if code == 429 or code >= 500:
                    self.breaker.record_failure()
                raise
            except requests.exceptions.RequestException:
                self.breaker.record_failure()
                raise

    def rebuild_session(self, proxy_url: str = ""):
        self._proxy_url = proxy_url
        # Invalidate all thread-local sessions so they get recreated with new proxy
        if hasattr(self._tlocal, 'session'):
            try:
                self._tlocal.session.close()
            except Exception:
                pass
            self._tlocal.session = None

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
#  Network helpers
# ═══════════════════════════════════════════════════════

def fetch_subjects(session: requests.Session):
    resp = session.post(f"{BASE_URL}/obj/Common/Subject/combo", timeout=(5, 15))
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
    # Reject anything with path separators or non-matching pattern
    if os.path.sep in fname or '/' in fname or '\\' in fname:
        return None
    if not fname.lower().endswith(".pdf"):
        return None
    m = re.fullmatch(r"(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf", fname)
    if not m:
        return None
    return dict(subject=m.group(1), sy=m.group(2), type=m.group(3),
                number=m.group(4) or "", filename=fname)

def get_year(sy):
    y = sy[1:] if len(sy) > 1 and sy[0] in "msw" else "unknown"
    return "20" + y if y.isdigit() and len(y) == 2 else y

def paper_group_of(number):
    if not number: return 0
    return int(number) // 10 if int(number) >= 10 else int(number)

def group_papers(rows):
    pairs, standalone_files = {}, []
    for row in rows:
        fname = row["file"]
        p = parse_filename(fname)
        if not p or p["type"] not in ("qp", "ms"):
            standalone_files.append(dict(
                filename=fname, ftype=p["type"] if p else "other",
                label=fname.replace(".pdf", ""), paper_group=0, sy="", number="",
            ))
            continue
        key = (p["subject"], p["sy"], p["number"])
        if key not in pairs:
            pairs[key] = dict(
                subject=p["subject"], sy=p["sy"], number=p["number"],
                paper_group=paper_group_of(p["number"]), qp=None, ms=None,
            )
        pairs[key][p["type"]] = fname
    results = []
    for v in pairs.values():
        results.append(dict(
            subject=v["subject"], sy=v["sy"], number=v["number"],
            paper_group=v["paper_group"], qp=v.get("qp"), ms=v.get("ms"),
        ))
    results.sort(key=lambda g: (g["paper_group"],
                                 int(g["number"]) if g["number"].isdigit() else 999))
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
#  API — Python ↔ JS bridge
# ═══════════════════════════════════════════════════════

class API:
    def __init__(self):
        self.window = None
        self._dl_items: list = []
        self._dl_lock = threading.Lock()
        self._status_lock = threading.Lock()
        self._status = {"phase": "idle", "done": 0, "total": 0, "success": 0, "message": "就绪"}
        self.engine = DownloadEngine(rate=5.0, capacity=15, max_concurrent=4)
        self._cancel_flag = False
        self.session = create_session()

        self._fav_path = os.path.join(CACHE_DIR, "favorites.json")
        self._hist_path = os.path.join(CACHE_DIR, "download_history.json")
        self._settings_path = os.path.join(CACHE_DIR, "settings.json")
        self._persist_lock = threading.Lock()  # protects all persistence read-modify-write
        # In-memory history index to avoid disk I/O per check_downloaded call
        self._hist_set: set = set()
        self._hist_loaded = False

    def _ensure_hist_loaded(self):
        if self._hist_loaded:
            return
        with self._persist_lock:
            if self._hist_loaded:
                return
            hist = _read_json(self._hist_path, {"items": []})
            self._hist_set = {e["filename"] for e in hist.get("items", [])}
            self._hist_loaded = True

    # ── Init ─────────────────────────────────────────

    def get_default_dir(self):
        return os.path.expanduser("~/Downloads/C-Paper")

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
        queries = [(y, s) for y in range(int(p["year_from"]), int(p["year_to"]) + 1) for s in p["seasons"]]
        all_groups = []; errors = []
        with ThreadPoolExecutor(max_workers=3) as ex:
            futs = {ex.submit(search_papers, self.session, p["code"], y, s): (y, s) for y, s in queries}
            for fut in as_completed(futs):
                try:
                    res = fut.result(timeout=30)
                    gs = group_papers(res.get("rows", []))
                    all_groups.extend(g for g in gs if g.get("paper_group", -1) in p["pgs"])
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
        dup_mode = str(options.get("dup_mode", "overwrite"))
        # Clamp to safe ranges
        rate = max(1.0, min(20.0, rate))
        threads = max(1, min(16, threads))

        self._cancel_flag = False
        self._ensure_hist_loaded()
        self.engine.update_rate(rate)
        self.engine.update_concurrency(threads)
        folders = build_folders(groups, save_dir, merge)

        skipped_count = 0
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
                # Safety: reject path traversal
                if os.path.sep in fname or '/' in fname or '\\' in fname or '..' in fname:
                    continue
                fname = os.path.basename(fname)
                if not fname or not fname.lower().endswith(".pdf"):
                    continue
                fdir = folders["root"] if merge else folders.get(year, {}).get(ftype_key, save_dir)
                save_path = os.path.realpath(os.path.join(fdir, fname))
                base = os.path.realpath(save_dir)
                if os.path.commonpath([base, save_path]) != base:
                    continue
                # Dup mode check
                is_dup = fname in self._hist_set
                if dup_mode == "skip" and is_dup:
                    skipped_count += 1; continue
                if dup_mode == "missing" and is_dup and os.path.exists(save_path):
                    skipped_count += 1; continue
                items.append({
                    "id": len(items), "filename": fname, "ftype": ftype_label,
                    "label": label, "year": year,
                    "save_path": save_path,
                    "status": "pending", "error": "", "error_type": "",
                })

        with self._dl_lock:
            self._dl_items = items
        with self._status_lock:
            self._status = {"phase": "running", "done": 0, "total": len(items),
                            "success": 0, "message": "准备下载...",
                            "skipped": skipped_count}
        threading.Thread(target=self._run_downloads, args=(items,), daemon=True).start()
        return json.dumps({"ok": True, "total": len(items), "skipped": skipped_count})

    def _run_downloads(self, items, retry_round: int = 0, batch_total: int = None):
        MAX_AUTO = 3
        if batch_total is None:
            batch_total = len(items)

        def worker(item):
            if self._cancel_flag:
                return None
            with self._dl_lock:
                item["status"] = "downloading"
            try:
                self.engine.download_one(item["filename"], item["save_path"])
                with self._dl_lock:
                    item["status"] = "done"; item["error"] = ""
                self._record_one_history(item["filename"], item["label"], item["year"], item["save_path"])
                return True
            except requests.exceptions.Timeout:
                with self._dl_lock:
                    item["status"] = "failed"; item["error"] = "网络超时"; item["error_type"] = "network"
                return False
            except requests.exceptions.ConnectionError:
                with self._dl_lock:
                    item["status"] = "failed"; item["error"] = "连接失败"; item["error_type"] = "network"
                return False
            except requests.exceptions.HTTPError as e:
                code = e.response.status_code if e.response is not None else 0
                with self._dl_lock:
                    item["status"] = "failed"
                    if code == 404:
                        item["error"] = "文件不存在 (404)"; item["error_type"] = "not_found"
                    elif code == 429:
                        item["error"] = "请求过频 (429)"; item["error_type"] = "rate_limit"
                    elif code >= 500:
                        item["error"] = f"服务器错误 ({code})"; item["error_type"] = "server"
                    else:
                        item["error"] = f"HTTP {code}"; item["error_type"] = "unknown"
                return False
            except Exception as e:
                msg = str(e)
                with self._dl_lock:
                    item["status"] = "failed"; item["error"] = msg
                    if "proxy" in msg.lower() or "代理" in msg:
                        item["error_type"] = "proxy"
                    elif "断路器" in msg:
                        item["error_type"] = "rate_limit"
                    else:
                        item["error_type"] = "unknown"
                return False

        if self._cancel_flag:
            return

        self.engine.reset_stats(len(items))
        max_w = getattr(self.engine, '_max_concurrent', 4)
        with ThreadPoolExecutor(max_workers=max_w) as ex:
            futures = [ex.submit(worker, item) for item in items]
            for fut in as_completed(futures):
                if self._cancel_flag:
                    break
                result = fut.result()
                if result is not None:
                    self.engine.record_result(result)
                st = self.engine.get_stats()
                # Count successful items across ALL _dl_items (not just this round)
                with self._dl_lock:
                    total_done = sum(1 for i in self._dl_items if i["status"] == "done")
                    total_failed = sum(1 for i in self._dl_items if i["status"] == "failed")
                with self._status_lock:
                    self._status["done"] = total_done + total_failed
                    self._status["total"] = batch_total
                    self._status["success"] = total_done
                    self._status["message"] = f"下载中... ({total_done+total_failed}/{batch_total})"

        if self._cancel_flag:
            with self._dl_lock:
                for item in self._dl_items:
                    if item["status"] in ("pending", "downloading"):
                        item["status"] = "cancelled"; item["error"] = "用户取消"
            with self._status_lock:
                self._status["phase"] = "done"
                self._status["message"] = "已取消"
            return

        with self._dl_lock:
            failed = [i for i in self._dl_items if i["status"] == "failed"]

        if failed and retry_round < MAX_AUTO:
            delay = min(5 * (2 ** retry_round), 30)
            with self._status_lock:
                self._status["message"] = f"{len(failed)} 失败, {delay}s 后自动重试 (第{retry_round+1}轮)..."
            time.sleep(delay)
            if self._cancel_flag:
                return
            with self._dl_lock:
                for item in failed:
                    item["status"] = "pending"; item["error"] = ""
            self._run_downloads(failed, retry_round + 1, batch_total)
        else:
            with self._dl_lock:
                total_done = sum(1 for i in self._dl_items if i["status"] == "done")
            with self._status_lock:
                self._status["phase"] = "done"
                self._status["total"] = batch_total
                self._status["success"] = total_done
                msg = f"完成 ({total_done}/{batch_total} 成功)"
                if retry_round > 0:
                    msg += f" (经过{retry_round}轮重试)"
                self._status["message"] = msg

    # ── Download history ─────────────────────────────

    def _record_one_history(self, filename, label, year, save_path=""):
        self._ensure_hist_loaded()
        if filename in self._hist_set:
            return  # already recorded
        with self._persist_lock:
            hist = _read_json(self._hist_path, {"items": []})
            hist["items"].append({
                "filename": filename, "label": label, "year": year,
                "save_path": save_path,
                "downloaded_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            })
            # LRU
            if len(hist["items"]) > HISTORY_MAX:
                evicted = hist["items"][:-HISTORY_MAX]
                hist["items"] = hist["items"][-HISTORY_MAX:]
                for e in evicted:
                    self._hist_set.discard(e["filename"])
            _write_json(self._hist_path, hist)
        self._hist_set.add(filename)

    def get_download_history(self):
        hist = _read_json(self._hist_path, {"items": []})
        return json.dumps(hist.get("items", []))

    def check_downloaded(self, filename):
        self._ensure_hist_loaded()
        downloaded = filename in self._hist_set
        return json.dumps({"downloaded": downloaded, "date": ""})

    def clear_history(self):
        with self._persist_lock:
            _write_json(self._hist_path, {"items": []})
            self._hist_set.clear()
        return json.dumps({"ok": True})

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
                i["status"] = "pending"; i["error"] = ""
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
            item["status"] = "pending"; item["error"] = ""
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

    # ── Favorites ────────────────────────────────────

    def get_favorites(self):
        data = _read_json(self._fav_path, [])
        return json.dumps(data)

    def add_favorite(self, code, name):
        with self._persist_lock:
            data = _read_json(self._fav_path, [])
            if not any(f.get("code") == code for f in data):
                data.append({"code": code, "name": name})
                _write_json(self._fav_path, data)
        return json.dumps({"ok": True})

    def remove_favorite(self, code):
        with self._persist_lock:
            data = _read_json(self._fav_path, [])
            data = [f for f in data if f.get("code") != code]
            _write_json(self._fav_path, data)
        return json.dumps({"ok": True})

    # ── Settings ─────────────────────────────────────

    def load_settings(self):
        defaults = {
            "theme": "light", "save_dir": self.get_default_dir(),
            "include_ms": True, "rate": 5, "threads": 4,
            "merge": False, "proxy_url": "", "last_subject": "",
            "last_mode": "search",
        }
        saved = _read_json(self._settings_path, {})
        defaults.update(saved)
        return json.dumps(defaults)

    def save_settings(self, settings_json):
        with self._persist_lock:
            _write_json(self._settings_path, json.loads(settings_json))
        return json.dumps({"ok": True})

    # ── Proxy ────────────────────────────────────────

    def set_proxy(self, proxy_url):
        if self._status["phase"] == "running":
            return json.dumps({"ok": False, "error": "下载进行中，无法修改代理"})
        try:
            old = self.session
            self.session = create_session(proxy_url)
            try: old.close()
            except Exception: pass
            self.engine.rebuild_session(proxy_url)
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def get_proxy(self):
        p = self.session.proxies.get("https", "") if self.session.proxies else ""
        return json.dumps({"proxy": p})

    def test_proxy(self, proxy_url):
        try:
            s = create_session(proxy_url)
            t0 = time.time()
            resp = s.post(f"{BASE_URL}/obj/Common/Subject/combo", timeout=(5, 10))
            resp.raise_for_status()
            elapsed = int((time.time() - t0) * 1000)
            return json.dumps({"ok": True, "latency_ms": elapsed})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    # ── File system ──────────────────────────────────

    def choose_directory(self):
        try:
            import sys
            if sys.platform == "darwin":
                r = subprocess.run(["osascript", "-e", "POSIX path of (choose folder)"],
                                   capture_output=True, text=True, timeout=60)
                return r.stdout.strip().rstrip("/") if r.returncode == 0 else ""
            elif sys.platform == "win32":
                ps = ("Add-Type -AssemblyName System.Windows.Forms;"
                      "$f=New-Object System.Windows.Forms.FolderBrowserDialog;"
                      "$f.ShowDialog()|Out-Null;$f.SelectedPath")
                r = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                                   capture_output=True, text=True, timeout=60)
                return r.stdout.strip() if r.returncode == 0 else ""
            else:
                r = subprocess.run(["zenity", "--file-selection", "--directory"],
                                   capture_output=True, text=True, timeout=60)
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
#  HTML / CSS / JS — Three-Column Liquid Glass
# ═══════════════════════════════════════════════════════

HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>C-Paper</title>
<style>
/* ── Reset & Tokens ── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg-deep:#faf9f5;--bg-surface:#FFFFFF;
  --glass:rgba(20,20,19,0.03);--glass-hover:rgba(20,20,19,0.05);
  --glass-b:rgba(255,255,255,0.85);--glass-border:rgba(20,20,19,0.08);
  --glass-border-s:rgba(20,20,19,0.14);
  --text:#141413;--muted:#b0aea5;--faint:rgba(20,20,19,0.25);
  --accent:#d97757;--accent2:#6a9bcc;
  --accent-glow:rgba(217,119,87,0.18);--accent-glass:rgba(217,119,87,0.08);
  --ok:#788c5d;--err:#DC2626;--warn:#D97706;
  --r:14px;--rs:10px;--blur:saturate(180%) blur(24px);
  --ease:cubic-bezier(0.16,1,0.3,1);
  font-family:'Poppins',Arial,sans-serif;
}
[data-theme="dark"]{
  --bg-deep:#141413;--bg-surface:#1a1a18;
  --glass:rgba(250,249,245,0.05);--glass-hover:rgba(250,249,245,0.08);
  --glass-b:rgba(250,249,245,0.08);--glass-border:rgba(250,249,245,0.07);
  --glass-border-s:rgba(250,249,245,0.12);
  --text:#faf9f5;--muted:#b0aea5;--faint:rgba(250,249,245,0.3);
  --accent:#d97757;--accent2:#6a9bcc;
  --accent-glow:rgba(217,119,87,0.25);--accent-glass:rgba(217,119,87,0.12);
  --ok:#788c5d;--err:#EF4444;--warn:#F59E0B;
}
html,body{height:100%;overflow:hidden;background:var(--bg-deep);
  color:var(--text);-webkit-font-smoothing:antialiased;}

/* ── Background ── */
.bg{position:fixed;inset:0;z-index:0;pointer-events:none;background:var(--bg-deep);}
[data-theme="dark"] .bg{background:
    radial-gradient(ellipse 80% 50% at 5% 5%,rgba(217,119,87,0.12),transparent 60%),
    radial-gradient(ellipse 60% 50% at 95% 95%,rgba(106,155,204,0.08),transparent 60%),
    radial-gradient(ellipse 50% 40% at 50% 50%,rgba(120,140,93,0.04),transparent 60%),
    var(--bg-deep);}

/* ── Glass ── */
.g{background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
   border:1px solid var(--glass-border);border-radius:var(--r);}
.gs{background:var(--glass-b);backdrop-filter:saturate(200%) blur(30px);
    -webkit-backdrop-filter:saturate(200%) blur(30px);
    border:1px solid var(--glass-border-s);border-radius:var(--r);}

/* ── Layout Grid ── */
.app{position:relative;z-index:1;display:grid;
  grid-template-columns:210px 1fr 290px;
  grid-template-rows:auto 1fr;
  height:100vh;padding:8px;gap:8px;}
.hdr{grid-column:1/-1;grid-row:1;display:flex;align-items:center;
  gap:10px;padding:8px 16px;}
.side-l{grid-column:1;grid-row:2;display:flex;flex-direction:column;gap:8px;overflow:hidden;}
.center{grid-column:2;grid-row:2;display:flex;flex-direction:column;gap:8px;overflow:hidden;}
.side-r{grid-column:3;grid-row:2;display:flex;flex-direction:column;gap:8px;overflow:hidden;}

/* ── Header ── */
.hdr-icon svg{width:18px;height:18px;stroke:var(--accent);}
.hdr-title{font-size:15px;font-weight:700;letter-spacing:-.3px;}
.badge{background:var(--accent-glass);color:var(--accent);font-size:10px;font-weight:600;
       padding:2px 8px;border-radius:20px;border:1px solid rgba(217,119,87,0.2);}
.hdr-status{margin-left:auto;font-size:11px;color:var(--muted);display:flex;align-items:center;gap:6px;}
.hdr-dot{width:6px;height:6px;border-radius:50%;}
.hdr-dot.ok{background:var(--ok);box-shadow:0 0 6px var(--ok);}
.hdr-dot.err{background:var(--err);box-shadow:0 0 6px var(--err);}
.hdr-dot.idle{background:var(--muted);}
.theme-btn{display:flex;align-items:center;justify-content:center;width:28px;height:28px;
  border-radius:50%;border:1px solid var(--glass-border);background:transparent;
  color:var(--text);cursor:pointer;font-size:14px;transition:all .2s var(--ease);margin-left:6px;}
.theme-btn:hover{background:var(--glass-hover);}

/* ── Left sidebar ── */
.mode-btn{display:flex;align-items:center;gap:7px;padding:9px 14px;border-radius:var(--rs);
  border:none;background:transparent;color:var(--muted);font-size:12px;font-weight:500;
  cursor:pointer;transition:all .18s var(--ease);font-family:inherit;width:100%;text-align:left;}
.mode-btn:hover{background:var(--glass-hover);color:var(--text);}
.mode-btn.on{background:var(--accent-glass);color:var(--accent);font-weight:600;}
.mode-btn svg{width:14px;height:14px;stroke:currentColor;}
.mode-next .badge-mini{font-size:9px;color:var(--accent);font-weight:600;margin-left:auto;}

.fav-sec{flex:1;overflow-y:auto;min-height:0;}
.fav-sec::-webkit-scrollbar{width:4px;}
.fav-sec::-webkit-scrollbar-thumb{background:rgba(255,255,255,0.08);border-radius:2px;}
.fav-hdr{display:flex;align-items:center;justify-content:space-between;
  padding:6px 12px;font-size:10px;color:var(--muted);font-weight:600;
  text-transform:uppercase;letter-spacing:.6px;}
.fav-add{display:flex;align-items:center;justify-content:center;width:20px;height:20px;
  border-radius:50%;border:1px solid var(--glass-border);background:transparent;
  color:var(--muted);cursor:pointer;font-size:14px;transition:all .15s var(--ease);}
.fav-add:hover{background:var(--glass-hover);color:var(--text);}
.fav-item{display:flex;align-items:center;gap:6px;padding:7px 12px;cursor:pointer;
  border-radius:6px;font-size:11px;transition:all .12s var(--ease);}
.fav-item:hover{background:var(--glass-hover);}
.fav-item .fav-code{font-weight:600;color:var(--accent);}
.fav-item .fav-name{color:var(--muted);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.fav-item .fav-rm{visibility:hidden;width:16px;height:16px;border-radius:50%;border:none;
  background:transparent;color:var(--err);cursor:pointer;font-size:12px;display:flex;
  align-items:center;justify-content:center;transition:all .12s;}
.fav-item:hover .fav-rm{visibility:visible;}
.fav-rm:hover{background:rgba(224,64,64,0.15);}
.fav-empty{text-align:center;color:var(--faint);font-size:11px;padding:16px;}

.side-footer{flex-shrink:0;padding:4px 0;border-top:1px solid var(--glass-border);}
.set-btn{display:flex;align-items:center;gap:6px;padding:8px 12px;width:100%;border:none;
  border-radius:var(--rs);background:transparent;color:var(--muted);font-size:11px;
  font-family:inherit;cursor:pointer;transition:all .15s var(--ease);}
.set-btn:hover{background:var(--glass-hover);color:var(--text);}
.set-btn svg{width:14px;height:14px;stroke:currentColor;}

/* ── Center area ── */

.ctrl-row{padding:10px 20px;display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap;}
.ctrl-row .fld{display:flex;flex-direction:column;gap:4px;}
.ctrl-row .fld.grow{flex:1;min-width:140px;}
.ctrl-row .lbl{font-size:9px;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.6px;}

.result-panel{flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden;
  padding:12px 20px;}
.result-title{font-size:13px;font-weight:600;color:var(--text);margin-bottom:8px;flex-shrink:0;}
.result-title .rtcnt{color:var(--muted);font-weight:400;font-size:11px;}

/* ── Inputs ── */
select,input[type=text]{background:rgba(20,20,19,0.04);border:1px solid var(--glass-border);
  border-radius:var(--rs);color:var(--text);font-size:12px;padding:7px 10px;outline:none;width:100%;
  transition:border-color .2s var(--ease),box-shadow .2s var(--ease);}
[data-theme="dark"] select,[data-theme="dark"] input[type=text]{background:rgba(255,255,255,0.05);}
select{appearance:none;-webkit-appearance:none;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%238A8F98' stroke-width='2'%3E%3Cpolyline points='6 9 12 15 18 9'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:right 9px center;padding-right:28px;}
select option{background:#1a1a18;color:var(--text);}
[data-theme="dark"] select option{background:#1a1a18;color:var(--text);}
select:focus,input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-glow);}

/* ── Buttons ── */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:8px 16px;
     border-radius:var(--rs);font-size:12px;font-weight:600;cursor:pointer;border:none;
     transition:all .2s var(--ease);white-space:nowrap;font-family:inherit;}
.btn:active{transform:scale(0.97);}
.btn-pri{background:var(--accent);color:#fff;box-shadow:0 2px 10px var(--accent-glow);}
.btn-pri:hover{background:#e08868;box-shadow:0 4px 16px var(--accent-glow);}
.btn-sec{background:rgba(255,255,255,0.06);border:1px solid var(--glass-border);color:var(--text);}
.btn-sec:hover{background:var(--glass-hover);border-color:var(--glass-border-s);}
.btn-ok{background:linear-gradient(135deg,#5a7040,#788c5d);color:#fff;box-shadow:0 2px 10px rgba(120,140,93,0.25);}
.btn-ok:hover{box-shadow:0 4px 18px rgba(120,140,93,0.4);}
.btn-err{background:linear-gradient(135deg,#c03030,#e04040);color:#fff;box-shadow:0 2px 10px rgba(224,64,64,0.2);}
.btn-err:hover{box-shadow:0 4px 18px rgba(224,64,64,0.35);}
.btn-sm{padding:5px 11px;font-size:11px;}
.btn-warn{background:rgba(245,158,11,0.15);color:var(--warn);border:1px solid rgba(245,158,11,0.3);}
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
.rhead{display:grid;grid-template-columns:36px 1fr 1fr 24px;gap:8px;padding:7px 12px;
  background:rgba(255,255,255,0.02);border-bottom:1px solid var(--glass-border);
  font-size:9px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;
  position:sticky;top:0;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);}
.rgrp-hdr{padding:6px 12px;font-size:11px;font-weight:600;color:var(--accent);
  background:var(--accent-glass);border-bottom:1px solid var(--glass-border);
  cursor:pointer;display:flex;align-items:center;gap:6px;transition:background .15s;}
.rgrp-hdr:hover{background:rgba(217,119,87,0.18);}
.rrow{display:grid;grid-template-columns:36px 1fr 1fr 24px;gap:8px;padding:7px 12px;
  border-bottom:1px solid var(--glass-border);font-size:12px;align-items:center;
  transition:background .12s;}
.rrow:hover{background:var(--glass-hover);}
.rrow .chk-col{display:flex;align-items:center;gap:2px;}
.cb{display:flex;align-items:center;justify-content:center;width:20px;height:20px;
    border-radius:5px;border:1.5px solid var(--glass-border);cursor:pointer;
    transition:all .15s var(--ease);font-size:11px;color:transparent;flex-shrink:0;}
.cb.on{background:var(--accent);border-color:var(--accent);color:#fff;}
.cb.dim{opacity:.25;cursor:not-allowed;}
.fname{font-family:'Lora',Georgia,serif;font-size:11px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.fname.exist{color:var(--text);}
.fname.miss{color:var(--muted);opacity:.35;}
.fok{color:var(--ok);font-size:13px;text-align:center;}
.fno{color:var(--muted);font-size:13px;opacity:.3;text-align:center;}
.fname.dled{position:relative;}
.fname.dled::after{content:' ✓';color:var(--ok);font-size:10px;}
.badge-dl{display:inline-flex;align-items:center;gap:2px;padding:1px 5px;border-radius:4px;
  background:rgba(120,140,93,0.12);color:var(--ok);font-size:9px;}

/* ── Right sidebar ── */
.sec-title{font-size:10px;color:var(--muted);font-weight:600;text-transform:uppercase;
  letter-spacing:.6px;padding:4px 14px;flex-shrink:0;}
.side-r .sec{padding:10px 14px;flex-shrink:0;}
.side-r .sec+.sec{border-top:1px solid var(--glass-border);}
.side-r .srow{display:flex;align-items:center;gap:8px;}
.side-r .srow+.srow{margin-top:8px;}
.side-r label{font-size:11px;color:var(--muted);}
.side-r .dir-disp{flex:1;min-width:0;background:rgba(255,255,255,0.04);
  border:1px solid var(--glass-border);border-radius:6px;color:var(--muted);
  font-size:10px;font-family:'Lora',Georgia,serif;
  padding:5px 8px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
[data-theme="dark"] .side-r .dir-disp{background:rgba(255,255,255,0.04);}
input[type=range]{flex:1;height:4px;border-radius:2px;
  background:rgba(255,255,255,0.12);accent-color:var(--accent);cursor:pointer;}
.sval{font-size:11px;color:var(--muted);width:36px;text-align:right;font-variant-numeric:tabular-nums;}

/* Chk row */
.chk-row{display:flex;align-items:center;gap:6px;font-size:11px;color:var(--muted);cursor:pointer;user-select:none;}

/* Proxy section */
.proxy-sec{flex-shrink:0;}
.proxy-status{font-size:10px;margin-top:4px;display:none;}
.proxy-status.ok{color:var(--ok);display:block;}
.proxy-status.err{color:var(--err);display:block;}
.proxy-sec .toggle-row{display:flex;align-items:center;gap:6px;cursor:pointer;user-select:none;}
.proxy-sec .proxy-details{display:none;margin-top:8px;gap:6px;flex-direction:column;}
.proxy-sec .proxy-details.on{display:flex;}

/* ── Download section ── */
.dl-sec{flex:1;min-height:0;display:flex;flex-direction:column;}
.dl-summary-row{display:flex;gap:10px;padding:6px 14px;font-size:10px;flex-shrink:0;
  border-bottom:1px solid var(--glass-border);}
.dl-summary-row span{color:var(--muted);}
.dl-summary-row .cnt-dl{color:var(--accent);font-weight:600;}
.dl-summary-row .cnt-ok{color:var(--ok);font-weight:600;}
.dl-summary-row .cnt-err{color:var(--err);font-weight:600;}
.dl-summary-row .cnt-pnd{color:var(--muted);}
.dlwrap{flex:1;overflow-y:auto;min-height:0;}
.dlrow{display:grid;grid-template-columns:18px 1fr 36px 44px 32px 1fr 44px;
  gap:4px;padding:5px 10px;border-bottom:1px solid var(--glass-border);
  font-size:10px;align-items:center;transition:background .12s;}
.dlrow:hover{background:var(--glass-hover);}
.dlrow.downloading{background:rgba(217,119,87,0.06);}
.dlrow.failed{background:rgba(224,64,64,0.05);}
.dlrow .ico{font-size:11px;text-align:center;}
.dlrow .dl-fname{font-family:'Lora',Georgia,serif;font-size:9px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text);}
.dl-fname.dim{color:var(--muted);}
.type-QP{background:rgba(217,119,87,0.18);color:#e8a888;
  padding:1px 5px;border-radius:3px;font-size:8px;font-weight:700;text-align:center;}
.type-MS{background:rgba(120,140,93,0.18);color:#a0b888;
  padding:1px 5px;border-radius:3px;font-size:8px;font-weight:700;text-align:center;}
.dl-stat{font-size:9px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.dl-stat.s-pnd{color:var(--muted);}.dl-stat.s-dl{color:var(--accent);}
.dl-stat.s-ok{color:var(--ok);}.dl-stat.s-err{color:var(--err);}
.dl-actions{display:flex;gap:6px;padding:8px 14px;flex-shrink:0;}

/* Main download button */
.dl-main-btn{padding:12px 16px;}
.dl-main-btn .btn{width:100%;padding:12px 20px;font-size:14px;}

/* ── Batch panel specific ── */
.bgrid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:8px;}
.bsec-t{font-size:9px;color:var(--muted);font-weight:600;text-transform:uppercase;letter-spacing:.6px;margin-bottom:6px;}
.cbgrp{display:flex;gap:6px;flex-wrap:wrap;}
.cbitem{display:flex;align-items:center;gap:5px;cursor:pointer;font-size:11px;
  padding:5px 9px;border-radius:6px;border:1px solid var(--glass-border);
  transition:all .15s var(--ease);user-select:none;}
.cbitem:hover{background:var(--glass-hover);}
.cbitem.on{background:var(--accent-glass);border-color:rgba(217,119,87,0.25);}
input[type=checkbox]{accent-color:var(--accent);width:13px;height:13px;cursor:pointer;}
.quick-years{display:flex;gap:4px;margin-top:4px;}
.quick-years button{padding:3px 10px;font-size:10px;}

.prev{flex:1;overflow-y:auto;min-height:0;background:rgba(20,20,19,0.06);
  border:1px solid var(--glass-border);border-radius:var(--rs);padding:12px;
  font-family:'Lora',Georgia,serif;font-size:11px;line-height:1.8;
  color:var(--muted);white-space:pre-wrap;}
[data-theme="dark"] .prev{background:rgba(0,0,0,0.15);}
.py{color:var(--accent);font-weight:600;}
.pf{color:var(--muted);}
[data-theme="dark"] .pf{color:rgba(255,255,255,0.6);}

/* ── Splash / loading & error overlay ── */
.splash{position:absolute;inset:0;z-index:10;display:flex;flex-direction:column;
  align-items:center;justify-content:center;gap:14px;
  background:var(--bg-deep);border-radius:var(--r);opacity:1;transition:opacity .35s var(--ease);}
.splash.fade{opacity:0;pointer-events:none;}
.splash-msg{font-size:13px;color:var(--muted);}
.splash-bar{width:200px;height:4px;background:var(--glass-border);border-radius:2px;overflow:hidden;}
.splash-bar-fill{height:100%;width:0%;background:var(--accent);border-radius:2px;
  animation:splash-progress 2.5s var(--ease) forwards;}
@keyframes splash-progress{0%{width:0%}30%{width:45%}60%{width:70%}90%{width:88%}100%{width:100%}}
.splash-err{font-size:13px;color:var(--err);text-align:center;max-width:320px;line-height:1.6;}

/* ── Panel visibility ── */
.panel{display:none;flex-direction:column;gap:8px;flex:1;min-height:0;overflow:hidden;}
.panel.on{display:flex;}
.cnt-wrap{gap:0;}

/* ── Settings overlay ── */
.set-overlay{display:none;position:fixed;inset:0;z-index:900;background:rgba(0,0,0,0.6);
  backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);}
.set-overlay.on{display:flex;align-items:center;justify-content:center;}
.set-dialog{width:420px;max-height:80vh;overflow-y:auto;padding:24px;display:flex;flex-direction:column;gap:14px;}
.set-dialog h3{font-size:16px;font-weight:700;}
.set-dialog .close-btn{position:absolute;top:12px;right:14px;width:28px;height:28px;border-radius:50%;
  border:none;background:var(--glass-hover);color:var(--muted);font-size:16px;cursor:pointer;}

/* ── Spinner ── */
.spin{display:inline-block;width:12px;height:12px;
  border:2px solid rgba(255,255,255,0.15);border-top-color:var(--accent);
  border-radius:50%;animation:sp .6s linear infinite;vertical-align:middle;}
@keyframes sp{to{transform:rotate(360deg)}}

/* ── Empty ── */
.empty{display:flex;flex-direction:column;align-items:center;
  justify-content:center;height:100%;gap:8px;color:var(--muted);}
.empty svg{width:32px;height:32px;stroke:var(--muted);opacity:.3;}

/* ── Toast ── */
#toasts{position:fixed;top:14px;right:14px;z-index:999;
  display:flex;flex-direction:column;gap:6px;pointer-events:none;}
.toast{background:rgba(20,20,19,0.97);
  backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);
  border:1px solid var(--glass-border);border-radius:10px;
  padding:10px 14px;font-size:12px;min-width:200px;
  display:flex;gap:8px;align-items:flex-start;
  animation:tin .25s var(--ease);pointer-events:auto;}
.toast.ok{border-left:3px solid var(--ok);}
.toast.err{border-left:3px solid var(--err);}
.toast.warn{border-left:3px solid var(--warn);}
.toast.inf{border-left:3px solid var(--accent);}
@keyframes tin{from{transform:translateX(110%);opacity:0}}

@media(prefers-reduced-motion:reduce){
  *,*::before,*::after{animation-duration:0.01ms!important;transition-duration:0.01ms!important;}
}
</style>
</head>
<body>

<div class="bg"></div>
<div id="toasts"></div>

<!-- Confirm overlay -->
<div class="set-overlay" id="confirm-overlay">
  <div class="set-dialog" id="confirm-content" style="background:transparent;border:none;backdrop-filter:none;-webkit-backdrop-filter:none"></div>
</div>

<!-- Settings overlay -->
<div class="set-overlay" id="set-overlay">
  <div class="set-dialog gs" style="position:relative">
    <button class="close-btn" onclick="document.getElementById('set-overlay').classList.remove('on')">×</button>
    <h3>⚙ 设置</h3>
    <div class="sec">
      <label class="lbl">代理服务器 (HTTP/HTTPS)</label>
      <div class="srow" style="margin-top:6px">
        <input type="text" id="proxy-url" placeholder="http://127.0.0.1:7890" style="flex:1">
        <button class="btn btn-sec btn-sm" onclick="saveProxy()">保存</button>
        <button class="btn btn-sec btn-sm" onclick="testProxy()">测试</button>
      </div>
      <span class="proxy-status" id="proxy-st"></span>
    </div>
    <div class="sec" style="text-align:right">
      <button class="btn btn-err btn-sm" onclick="clearHistory()">清空下载历史</button>
    </div>
    <div class="sec" style="border-top:1px solid var(--glass-border);padding-top:14px;font-size:12px;color:var(--muted);line-height:1.8">
      <div style="font-weight:700;font-size:14px;color:var(--text);margin-bottom:6px">C-Paper v5.1</div>
      <div>CIE 试卷批量搜索与下载工具</div>
      <div style="margin-top:8px">试卷来源：<a href="https://cie.fraft.cn/" target="_blank" style="color:var(--accent)">https://cie.fraft.cn/</a></div>
      <div>GitHub 仓库：<a href="https://github.com/Ja-son-WU/CIE-Downloader" target="_blank" style="color:var(--accent)">github.com/Ja-son-WU/CIE-Downloader</a></div>
      <div style="margin-top:10px;font-size:10px;opacity:.6">© 2026 Ja-son-WU · MIT License<br>数据源自 Cambridge International Education</div>
    </div>
  </div>
</div>

<div class="app">
  <!-- Header -->
  <header class="hdr g">
    <span class="hdr-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/><line x1="8" y1="7" x2="16" y2="7"/><line x1="8" y1="11" x2="14" y2="11"/></svg></span>
    <span class="hdr-title">C-Paper</span>
    <span class="badge">v5.1</span>
    <button class="theme-btn" onclick="toggleTheme()" title="切换深色/浅色主题" id="theme-btn">☀</button>
    <span class="hdr-status">
      <span class="hdr-dot idle" id="hdr-dot"></span>
      <span id="hdr-st">加载中...</span>
    </span>
  </header>

  <!-- ══ Left Sidebar ══ -->
  <div class="side-l">
    <div class="g" style="flex-shrink:0;padding:5px;display:flex;flex-direction:column;gap:2px;">
      <button class="mode-btn on" id="mode-search" onclick="switchMode('search')">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        按次搜索
      </button>
      <button class="mode-btn" id="mode-batch" onclick="switchMode('batch')">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="21" x2="9" y2="9"/></svg>
        批量下载
      </button>
    </div>

    <!-- Favorites -->
    <div class="g fav-sec">
      <div class="fav-hdr">
        <span>收藏科目</span>
        <button class="fav-add" onclick="addFav()" title="添加当前科目">+</button>
      </div>
      <div id="fav-list">
        <div class="fav-empty">暂无收藏<br>选择科目后点击 + 添加</div>
      </div>
    </div>

    <div class="side-footer">
      <button class="set-btn" onclick="syncProxyToDialog();document.getElementById('set-overlay').classList.add('on')">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
        设置
      </button>
    </div>
  </div>

  <!-- ══ Center Area ══ -->
  <div class="center" style="position:relative">
    <!-- Splash: loading / error overlay -->
    <div class="splash" id="splash">
      <div class="splash-bar"><div class="splash-bar-fill"></div></div>
      <span class="splash-msg">正在加载...</span>
    </div>

    <!-- Search Panel -->
    <div class="panel on" id="pnl-search" style="margin-top:4px">
      <div class="g gs" style="padding:10px 14px;flex-shrink:0;">
        <div id="subj-name" style="font-size:16px;font-weight:700;margin-bottom:8px;display:none"></div>
        <div class="ctrl-row">
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

      <div class="result-panel gs">
        <div class="tbar">
          <button class="btn btn-sec btn-sm" onclick="selAll()">全选</button>
          <button class="btn btn-sec btn-sm" onclick="deselAll()">全不选</button>
          <button class="btn btn-sec btn-sm" onclick="selQP()">仅 QP</button>
          <button class="btn btn-sec btn-sm" onclick="selMS()">仅 MS</button>
          <span class="tbar-r" id="rcnt">共 0 项</span>
        </div>
        <div class="rhead"><div></div><div>题卷 QP</div><div>答案 MS</div><div></div></div>
        <div class="rlist-wrap" id="rlist">
          <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg><div>搜索后显示结果</div></div>
        </div>
      </div>
    </div>

    <!-- Batch Panel -->
    <div class="panel" id="pnl-batch">
      <div class="g gs" style="padding:10px 14px;flex-shrink:0;">
        <div class="ctrl-row">
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
        <div class="quick-years">
          <span style="font-size:9px;color:var(--muted);margin-right:2px">快捷：</span>
          <button class="btn btn-sec btn-sm" onclick="quickYears(2)">近2年</button>
          <button class="btn btn-sec btn-sm" onclick="quickYears(5)">近5年</button>
          <button class="btn btn-sec btn-sm" onclick="quickYears(99)">全部</button>
        </div>
        <div class="bgrid">
          <div>
            <div class="bsec-t">季度</div>
            <div class="cbgrp" id="cbg-seasons">
              <label class="cbitem on"><input type="checkbox" value="Mar" checked onchange="syncCB(this)"> Mar 春</label>
              <label class="cbitem on"><input type="checkbox" value="Jun" checked onchange="syncCB(this)"> Jun 夏</label>
              <label class="cbitem on"><input type="checkbox" value="Nov" checked onchange="syncCB(this)"> Nov 冬</label>
            </div>
          </div>
          <div>
            <div class="bsec-t">试卷类型</div>
            <div class="cbgrp" id="cbg-papers">
              <label class="cbitem on"><input type="checkbox" value="1" checked onchange="syncCB(this)"> Paper 1</label>
              <label class="cbitem on"><input type="checkbox" value="2" checked onchange="syncCB(this)"> Paper 2</label>
              <label class="cbitem on"><input type="checkbox" value="3" checked onchange="syncCB(this)"> Paper 3</label>
              <label class="cbitem on"><input type="checkbox" value="4" checked onchange="syncCB(this)"> Paper 4</label>
              <label class="cbitem on"><input type="checkbox" value="5" checked onchange="syncCB(this)"> Paper 5</label>
              <label class="cbitem on"><input type="checkbox" value="6" checked onchange="syncCB(this)"> Paper 6</label>
            </div>
          </div>
        </div>
        <div style="display:flex;gap:10px;align-items:center;margin-top:10px;">
          <button class="btn btn-sec" id="pvbtn" onclick="doPreview()">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg> 预览
          </button>
          <button class="btn btn-pri" id="bdbtn" onclick="doBatchDL()">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> 开始下载
          </button>
        </div>
      </div>
      <div class="result-panel gs">
        <div class="result-title">预览</div>
        <div class="prev" id="prev">（点击「预览」查看将要下载的文件...）</div>
      </div>
    </div>
  </div>

  <!-- ══ Right Sidebar ══ -->
  <div class="side-r">
    <!-- Settings section -->
    <div class="g sec-title" style="border-radius:var(--r) var(--r) 0 0">设定</div>
    <div class="g sec" style="border-radius:0">
      <div class="srow">
        <label>保存到</label>
        <div class="dir-disp" id="dir-disp"></div>
        <button class="btn btn-sec btn-sm" onclick="browseDir()" title="浏览">📂</button>
        <button class="btn btn-sec btn-sm" onclick="openDir()" title="打开">↗</button>
      </div>
      <div class="srow">
        <label class="chk-row">
          <input type="checkbox" id="dl-ms" checked onchange="syncMS(this);autoSaveSettings()">
          <span>包含 MS</span>
        </label>
      </div>
      <div class="srow">
        <label>速度</label>
        <input type="range" id="b-rate" min="2" max="10" step="1" value="5"
               oninput="document.getElementById('rv').textContent=this.value+'/s';autoSaveSettings()">
        <span class="sval" id="rv">5/s</span>
      </div>
      <div class="srow">
        <label>线程</label>
        <select id="b-thr" style="width:65px" onchange="autoSaveSettings()">
          <option>2</option><option selected>4</option><option>6</option><option>8</option>
        </select>
        <label class="chk-row" style="margin-left:8px">
          <input type="checkbox" id="b-merge" onchange="syncCB(this);autoSaveSettings()">
          <span>合并文件夹</span>
        </label>
      </div>
      <div class="srow">
        <label>去重</label>
        <select id="dup-mode" style="width:100px;font-size:10px" onchange="autoSaveSettings()">
          <option value="overwrite">覆盖下载</option>
          <option value="skip">跳过已下载</option>
          <option value="missing">只补缺失</option>
        </select>
      </div>
    </div>

    <!-- Proxy quick toggle -->
    <div class="g proxy-sec" style="border-radius:0;padding:8px 14px;">
      <div class="toggle-row" onclick="document.querySelector('.proxy-details').classList.toggle('on')">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
        <span style="font-size:10px;color:var(--muted);flex:1">代理</span>
        <span style="font-size:9px;color:var(--muted)" id="proxy-indicator"></span>
      </div>
      <div class="proxy-details">
        <div class="srow">
          <input type="text" id="proxy-url-side" placeholder="http://127.0.0.1:7890" style="flex:1;font-size:10px">
          <button class="btn btn-sec btn-sm" onclick="saveProxySide()">保存</button>
          <button class="btn btn-sec btn-sm" onclick="testProxySide()">测试</button>
        </div>
        <span class="proxy-status" id="proxy-st-side"></span>
      </div>
    </div>

    <!-- Download tasks -->
    <div class="g sec-title" style="border-radius:0">下载任务</div>
    <div class="g dl-sec" style="border-radius:0 0 var(--r) var(--r)">
      <div class="dl-summary-row">
        <span id="dl-total">共 0 项</span>
        <span class="cnt-dl" id="dl-cnt-dl">⬇ 0</span>
        <span class="cnt-ok" id="dl-cnt-ok">✓ 0</span>
        <span class="cnt-err" id="dl-cnt-err">✗ 0</span>
        <span class="cnt-pnd" id="dl-cnt-pnd">⏳ 0</span>
      </div>
      <div class="dlwrap" id="dllist">
        <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>下载后在此查看进度</div></div>
      </div>
      <div class="dl-actions">
        <button class="btn btn-err btn-sm" id="retry-all-btn" onclick="retryAll()">↺ 重试失败</button>
        <button class="btn btn-sec btn-sm" onclick="clearDLList()">清空</button>
      </div>
      <div class="dl-main-btn" style="padding:0 12px 12px">
        <button class="btn btn-ok" id="dlbtn" onclick="doDownloadSel()">📥 下载选中</button>
      </div>
    </div>
  </div>
</div>

<script>
// ── Icons ─────────────────────────────────────────────
const ICO={check:'<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'};
const SVG={sun:'<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>',
moon:'<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'};

// ── State ─────────────────────────────────────────────
const S={
  subjects:[], groups:[], selected:{}, bGroups:[], bSelected:null, saveDir:'',
  poll:null, dlRendered:false, mode:'search',
  theme:'light', favorites:[], currentCode:'', currentName:'',
  downloadHistory:new Set(), settingsDebounce:null,
};

// ── Init ──────────────────────────────────────────────
window.addEventListener('pywebviewready',()=>doInit());

async function doInit(){
  const now=new Date().getFullYear();
  const yrs=Array.from({length:now-1999},(_,i)=>now-i);
  ['s-year','b-yfrom','b-yto'].forEach(id=>{
    const sel=document.getElementById(id);
    yrs.forEach(y=>sel.add(new Option(y,y)));
    sel.value=id==='b-yfrom'?now-2:now;
  });

  try{
    const [subjR,settingsR,favR,histR]=await Promise.all([
      pywebview.api.get_subjects(),
      pywebview.api.load_settings(),
      pywebview.api.get_favorites(),
      pywebview.api.get_download_history(),
    ]);

    // Subjects
    const subj=JSON.parse(subjR);
    if(!subj.ok)throw new Error(subj.error);
    S.subjects=subj.data;
    const frag=document.createDocumentFragment();
    subj.data.forEach(s=>{
      const opt=document.createElement('option');
      opt.value=s.value;
      opt.textContent=s.value+' \u2014 '+s.text;
      frag.appendChild(opt);
    });
    document.getElementById('s-subj').replaceChildren(frag);
    document.getElementById('b-subj').replaceChildren(
      ...[...document.getElementById('s-subj').options].map(o=>new Option(o.textContent,o.value))
    );
    document.getElementById('hdr-st').textContent=`${subj.data.length} 个科目`;
    setDot('idle');

    // Settings
    const settings=JSON.parse(settingsR);
    S.theme=settings.theme||'light'; S.saveDir=settings.save_dir||'';
    document.documentElement.dataset.theme=S.theme;
    updateThemeIcon();
    document.getElementById('dir-disp').textContent=S.saveDir;
    document.getElementById('dl-ms').checked=settings.include_ms!==false;
    document.getElementById('b-rate').value=settings.rate||5; document.getElementById('rv').textContent=(settings.rate||5)+'/s';
    document.getElementById('b-thr').value=settings.threads||4;
    document.getElementById('b-merge').checked=!!settings.merge;
    syncCB(document.getElementById('b-merge'));
    if(settings.last_mode)S.mode=settings.last_mode;
    if(settings.proxy_url){
      document.getElementById('proxy-url-side').value=settings.proxy_url;
      document.getElementById('proxy-indicator').textContent='已配置';
    }

    // Favorites
    const fav=JSON.parse(favR);
    S.favorites=Array.isArray(fav)?fav:[];
    renderFavs();

    // History
    const hist=JSON.parse(histR);
    if(Array.isArray(hist)) hist.forEach(h=>S.downloadHistory.add(h.filename));

    switchMode(S.mode);
    setStat('就绪');
    // Fade out splash
    const sp=document.getElementById('splash');
    if(sp){sp.classList.add('fade');setTimeout(()=>sp.remove(),400);}
  }catch(e){
    // Show error in splash
    const sp=document.getElementById('splash');
    if(sp){
      sp.innerHTML=`<span class="splash-err">\u26a0 \u521d\u59cb\u5316\u5931\u8d25<br>${e.message.replace(/</g,'&lt;')}</span>
        <button class="btn btn-pri" onclick="doInit()">\u21ba \u91cd\u8bd5</button>`;
    }
    document.getElementById('hdr-st').textContent='加载失败';
    setDot('err');
  }
}

// Save settings on close
window.addEventListener('beforeunload',()=>saveSettingsNow());

// ── Theme ─────────────────────────────────────────────
function toggleTheme(){
  S.theme=S.theme==='dark'?'light':'dark';
  document.documentElement.dataset.theme=S.theme;
  updateThemeIcon(); autoSaveSettings();
}
function updateThemeIcon(){
  const btn=document.getElementById('theme-btn');
  btn.innerHTML=S.theme==='dark'
    ?`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${SVG.sun}</svg>`
    :`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${SVG.moon}</svg>`;
}

// ── Settings persistence ──────────────────────────────
function autoSaveSettings(){
  clearTimeout(S.settingsDebounce);
  S.settingsDebounce=setTimeout(()=>saveSettingsNow(),300);
}
async function saveSettingsNow(){
  try{await pywebview.api.save_settings(JSON.stringify({
    theme:S.theme, save_dir:S.saveDir,
    include_ms:document.getElementById('dl-ms').checked,
    rate:+document.getElementById('b-rate').value,
    threads:+document.getElementById('b-thr').value,
    merge:document.getElementById('b-merge').checked,
    proxy_url:document.getElementById('proxy-url-side').value||'',
    last_mode:S.mode,
  }));}catch(e){}
}

// ── Proxy ─────────────────────────────────────────────
async function saveProxySide(){
  const url=document.getElementById('proxy-url-side').value.trim();
  const r=JSON.parse(await pywebview.api.set_proxy(url));
  if(r.ok){toast('代理已保存','ok');document.getElementById('proxy-indicator').textContent=url?'已配置':'';autoSaveSettings();}
  else toast('代理设置失败: '+r.error,'err');
}
function syncProxyToDialog(){
  document.getElementById('proxy-url').value=document.getElementById('proxy-url-side').value;
}
async function saveProxy(){
  const urlS=document.getElementById('proxy-url').value.trim();
  document.getElementById('proxy-url-side').value=urlS;
  await saveProxySide();
  document.getElementById('set-overlay').classList.remove('on');
}
async function testProxySide(){
  const url=document.getElementById('proxy-url-side').value.trim();
  if(!url)return toast('请先输入代理地址','err');
  const st=document.getElementById('proxy-st-side');st.textContent='测试中...';st.className='proxy-status';
  st.style.display='block';
  const r=JSON.parse(await pywebview.api.test_proxy(url));
  if(r.ok){st.textContent=`✓ 连接成功 (${r.latency_ms}ms)`;st.className='proxy-status ok';st.style.display='block';}
  else{st.textContent='✗ 连接失败: '+r.error;st.className='proxy-status err';st.style.display='block';}
}
async function testProxy(){
  document.getElementById('proxy-url-side').value=document.getElementById('proxy-url').value.trim();
  await testProxySide();
}
async function clearHistory(){
  if(!confirm('确认清空所有下载历史?'))return;
  await pywebview.api.clear_history();
  S.downloadHistory.clear();
  document.getElementById('set-overlay').classList.remove('on');
  toast('下载历史已清空','ok');
}

// ── Mode ──────────────────────────────────────────────
function switchMode(name){
  S.mode=name;
  ['search','batch'].forEach(n=>{
    document.getElementById('mode-'+n).classList.toggle('on',n===name);
    document.getElementById('pnl-'+n).classList.toggle('on',n===name);
  });
  autoSaveSettings();
}

// ── Favorites ─────────────────────────────────────────
function renderFavs(){
  const el=document.getElementById('fav-list');el.innerHTML='';
  if(!S.favorites.length){
    el.innerHTML='<div class="fav-empty">暂无收藏<br>选择科目后点击 + 添加</div>';
    return;
  }
  el.innerHTML='';
  S.favorites.forEach(f=>{
    const div=document.createElement('div');div.className='fav-item';
    div.onclick=()=>pickFav(f.code,f.name);
    const code=document.createElement('span');code.className='fav-code';code.textContent=f.code;
    const name=document.createElement('span');name.className='fav-name';name.textContent=f.name;
    const rm=document.createElement('button');rm.className='fav-rm';rm.textContent='\xD7';
    rm.onclick=e=>{e.stopPropagation();removeFav(f.code)};
    div.append(code,name,rm);el.appendChild(div);
  });
}
async function pickFav(code,name){
  S.currentCode=code;S.currentName=name;
  const sn=document.getElementById('subj-name');
  sn.textContent=`${name} (${code})`;sn.style.display='block';
  document.getElementById('s-subj').value=code;
  document.getElementById('b-subj').value=code;
}
async function addFav(){
  let code,name;
  if(S.mode==='search'){
    code=document.getElementById('s-subj').value;
    if(!code)return toast('请先选择科目','err');
    const opt=document.getElementById('s-subj').selectedOptions[0];
    name=opt?opt.text.split(' — ')[1]||opt.text:code;
  }else{
    code=document.getElementById('b-subj').value;
    if(!code)return toast('请先选择科目','err');
    const opt=document.getElementById('b-subj').selectedOptions[0];
    name=opt?opt.text.split(' — ')[1]||opt.text:code;
  }
  const r=JSON.parse(await pywebview.api.add_favorite(code,name));
  if(r.ok){
    S.favorites=JSON.parse(await pywebview.api.get_favorites());
    renderFavs();
    toast(`已收藏 ${code}`,'ok');
  }
}
async function removeFav(code){
  await pywebview.api.remove_favorite(code);
  S.favorites=S.favorites.filter(f=>f.code!==code);
  renderFavs();
}

// ── Search ────────────────────────────────────────────
function updateSubjectDisplay(){
  const sel=S.mode==='search'?document.getElementById('s-subj'):document.getElementById('b-subj');
  const code=sel.value; if(!code)return;
  S.currentCode=code;
  const opt=sel.selectedOptions[0];
  S.currentName=opt?opt.text.split(' — ')[1]||opt.text:code;
  const sn=document.getElementById('subj-name');
  sn.textContent=`${S.currentName} (${S.currentCode})`;sn.style.display='block';
  // Keep search and batch subject selectors in sync
  document.getElementById('s-subj').value=code;
  document.getElementById('b-subj').value=code;
}
// Wire subject selectors
['s-subj','b-subj'].forEach(id=>document.getElementById(id).addEventListener('change',updateSubjectDisplay));

async function doSearch(){
  const subj=document.getElementById('s-subj').value;
  const year=document.getElementById('s-year').value;
  const seas=document.getElementById('s-seas').value;
  if(!subj)return toast('请选择科目','err');
  updateSubjectDisplay();
  setBusy('sbtn','<span class="spin"></span> 搜索中…',true); setStat('搜索中…');
  try{
    const r=JSON.parse(await pywebview.api.search(subj,year,seas));
    if(!r.ok)throw new Error(r.error);
    S.groups=r.groups; S.selected={};
    r.groups.forEach((g,i)=>{
      S.selected[i]={};
      if(g.qp)S.selected[i].qp=true;
      if(g.ms)S.selected[i].ms=true;
    });
    renderResults(); setStat(`找到 ${r.count} 个文件`);
    document.getElementById('hdr-st').textContent=`${r.groups.length} 组试卷`;
    const sn=document.getElementById('subj-name');
    sn.textContent=`${S.currentName} (${subj})`;sn.style.display='block';
    setDot('idle');
  }catch(e){toast('搜索失败: '+e.message,'err');setStat('失败');setDot('err');}
  finally{setBusy('sbtn','搜索',false,'btn-pri');}
}

function renderResults(){
  const el=document.getElementById('rlist');el.innerHTML='';
  if(!S.groups.length){
    el.innerHTML='<div class="empty"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="2" width="20" height="8" rx="2" ry="2"/><rect x="2" y="14" width="20" height="8" rx="2" ry="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg><div>未找到试卷</div></div>';
    document.getElementById('rcnt').textContent='共 0 页';return;
  }
  const byPG={};
  S.groups.forEach((g,i)=>{const pg=g.paper_group||0;(byPG[pg]=byPG[pg]||[]).push([i,g]);});
  Object.keys(byPG).sort((a,b)=>+a-+b).forEach(pg=>{
    const label=+pg>0?`Paper ${pg}`:'其他',items=byPG[pg];
    const grp=document.createElement('div');grp.className='rgrp';grp.dataset.pg=pg;
    grp.innerHTML=`<div class="rgrp-hdr">▾ ${label} <span style="color:var(--muted);font-weight:400">(${items.length} 项)</span></div>`;
    grp.querySelector('.rgrp-hdr').onclick=()=>toggleGrp(pg);
    el.appendChild(grp);
    items.forEach(([i,g])=>{
      const sqp=S.selected[i]&&S.selected[i].qp;const sms=S.selected[i]&&S.selected[i].ms;
      const qp=g.qp?g.qp.replace('.pdf',''):null, ms=g.ms?g.ms.replace('.pdf',''):null;
      const qpDled=qp&&S.downloadHistory.has(g.qp)?' dled':'', msDled=ms&&S.downloadHistory.has(g.ms)?' dled':'';
      const row=document.createElement('div');row.className='rrow';row.dataset.i=i;
      row.innerHTML=`<div class="chk-col">
          <div class="cb${sqp?' on':''}" title="QP">${sqp?ICO.check:''}</div>
          <div class="cb${sms?' on':''}${!g.ms?' dim':''}" title="MS">${sms?ICO.check:''}</div>
        </div>
        <span class="fname ${qp?'exist':'miss'}${qpDled}"></span>
        <span class="fname ${ms?'exist':'miss'}${msDled}"></span>
        <span class="${(g.qp&&g.ms)?'fok':'fno'}">${(g.qp&&g.ms)?'✓':'!'}</span>`;
      row.querySelectorAll('.fname')[0].textContent=qp||'\u2014';
      row.querySelectorAll('.fname')[1].textContent=ms||'\u2014';
      row.querySelector('.cb').onclick=e=>{e.stopPropagation();toggleCB(i,'qp')};
      if(g.ms)row.querySelectorAll('.cb')[1].onclick=e=>{e.stopPropagation();toggleCB(i,'ms')};
      grp.appendChild(row);
    });
  });
  updateCount();
}

function toggleCB(i,ftype){
  if(!S.selected[i])S.selected[i]={}; S.selected[i][ftype]=!(S.selected[i][ftype]);
  const row=document.querySelector(`.rrow[data-i="${i}"]`); if(!row)return;
  const cb=row.querySelectorAll('.cb')[ftype==='qp'?0:1];
  const on=S.selected[i][ftype];
  cb.classList.toggle('on',on); cb.innerHTML=on?ICO.check:''; updateCount();
}
function toggleGrp(pg){
  const rows=[...document.querySelectorAll(`.rgrp[data-pg="${pg}"] .rrow`)];
  const anyOff=rows.some(r=>{
    const i=+r.dataset.i;const g=S.groups[i];if(!g)return false;
    return(g.qp&&!(S.selected[i]&&S.selected[i].qp))||(g.ms&&!(S.selected[i]&&S.selected[i].ms));
  });
  rows.forEach(r=>{
    const i=+r.dataset.i;if(!S.selected[i])S.selected[i]={};const g=S.groups[i];if(!g)return;
    if(g.qp)S.selected[i].qp=anyOff;if(g.ms)S.selected[i].ms=anyOff;
    const cbs=r.querySelectorAll('.cb');
    ['qp','ms'].forEach((ft,idx)=>{
      const on=S.selected[i][ft];
      cbs[idx].classList.toggle('on',!!on);cbs[idx].innerHTML=on?ICO.check:'';
    });
  });updateCount();
}
function selAll(){
  S.groups.forEach((g,i)=>{S.selected[i]={};if(g.qp)S.selected[i].qp=true;if(g.ms)S.selected[i].ms=true;});
  document.querySelectorAll('.cb').forEach(cb=>{cb.classList.add('on');cb.innerHTML=ICO.check;});updateCount();
}
function deselAll(){
  S.groups.forEach((_,i)=>{S.selected[i]={qp:false,ms:false};});
  document.querySelectorAll('.cb').forEach(cb=>{cb.classList.remove('on');cb.innerHTML='';});updateCount();
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
  });return n;
}
function updateCount(){
  const tot=S.groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0);
  document.getElementById('rcnt').textContent=`共 ${tot} 文件，已选 ${countSelected()} 个`;
}

// ── Batch ─────────────────────────────────────────────
function quickYears(n){
  const now=new Date().getFullYear();
  const from=document.getElementById('b-yfrom');const to=document.getElementById('b-yto');
  if(n>=99){from.value=from.options[from.options.length-1].value;to.value=now;}
  else{to.value=now;from.value=now-n+1;}
}
async function doPreview(){
  const code=document.getElementById('b-subj').value;
  const yFrom=+document.getElementById('b-yfrom').value;
  const yTo=+document.getElementById('b-yto').value;
  if(!code)return toast('请选择科目','err');
  if(yFrom>yTo)return toast('年份范围有误','err');
  updateSubjectDisplay();
  const seasons=[...document.querySelectorAll('#cbg-seasons input:checked')].map(el=>el.value);
  const pgs=[...document.querySelectorAll('#cbg-papers input:checked')].map(el=>+el.value);
  if(!seasons.length)return toast('请至少选一个季度','err');
  if(!pgs.length)return toast('请至少选择一种 Paper 类型','err');
  ['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=true;});
  document.getElementById('pvbtn').innerHTML='<span class="spin"></span> 搜索中…';setStat('预览中…');
  try{
    const r=JSON.parse(await pywebview.api.batch_preview(
      JSON.stringify({code,year_from:yFrom,year_to:yTo,seasons,pgs})
    ));
    if(!r.ok)throw new Error(r.error);
    S.bGroups=r.groups;S.bSelected={};
    r.groups.forEach((g,i)=>{S.bSelected[i]={};if(g.qp)S.bSelected[i].qp=true;if(g.ms)S.bSelected[i].ms=true;});
    if(r.warnings&&r.warnings.length)toast(`预览完成，${r.warnings.length} 个查询失败`,'warn');
    renderPreview(r.groups);setStat(`预览: ${r.groups.reduce((a,g)=>(g.qp?1:0)+(g.ms?1:0)+a,0)} 个文件`);
  }catch(e){toast('预览失败: '+e.message,'err');setStat('失败');}
  finally{['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=false;});
    document.getElementById('pvbtn').innerHTML='预览';}
}
function renderPreview(groups){
  const el=document.getElementById('prev');el.innerHTML='';
  if(!groups.length){el.innerHTML='<span style="color:var(--muted)">\uff08\u65e0\u7ed3\u679c\uff09</span>';return;}
  // Checkable list — same logic as renderResults but for bGroups/bSelected
  const byY={};
  groups.forEach((g,i)=>{
    const sy=g.sy||'';let y=sy.length>1?sy.slice(1):'?';
    if(/^\d{2}$/.test(y))y='20'+y;(byY[y]=byY[y]||[]).push([i,g]);
  });
  // Add toolbar
  const tbar=document.createElement('div');tbar.className='tbar';
  tbar.innerHTML='<button class="btn btn-sec btn-sm" onclick="selAllB()">全选</button> <button class="btn btn-sec btn-sm" onclick="deselAllB()">全不选</button> <button class="btn btn-sec btn-sm" onclick="selQPB()">仅 QP</button> <button class="btn btn-sec btn-sm" onclick="selMSB()">仅 MS</button>';
  el.appendChild(tbar);
  Object.keys(byY).sort((a,b)=>+a-+b).forEach(y=>{
    const grp=document.createElement('div');grp.style.marginBottom='4px';
    const hdr=document.createElement('div');hdr.className='rgrp-hdr';
    hdr.textContent=`\u2500\u2500 ${y} \u5e74 (${byY[y].length} \u7ec4) \u2500\u2500`;
    grp.appendChild(hdr);
    byY[y].forEach(([i,g])=>{
      const sqp=S.bSelected[i]&&S.bSelected[i].qp;const sms=S.bSelected[i]&&S.bSelected[i].ms;
      const qp=g.qp?g.qp.replace('.pdf',''):null, ms=g.ms?g.ms.replace('.pdf',''):null;
      const row=document.createElement('div');row.className='rrow';row.dataset.i=i;
      row.innerHTML=`<div class="chk-col">
          <div class="cb${sqp?' on':''}" title="QP">${sqp?ICO.check:''}</div>
          <div class="cb${sms?' on':''}${!g.ms?' dim':''}" title="MS">${sms?ICO.check:''}</div>
        </div>
        <span class="fname ${qp?'exist':'miss'}"></span>
        <span class="fname ${ms?'exist':'miss'}"></span>
        <span class="${(g.qp&&g.ms)?'fok':'fno'}">${(g.qp&&g.ms)?'\u2713':'!'}</span>`;
      row.querySelectorAll('.fname')[0].textContent=qp||'\u2014';
      row.querySelectorAll('.fname')[1].textContent=ms||'\u2014';
      row.querySelector('.cb').onclick=e=>{e.stopPropagation();toggleCBB(i,'qp');e.target.innerHTML=S.bSelected[i].qp?ICO.check:''};
      if(g.ms)row.querySelectorAll('.cb')[1].onclick=e=>{e.stopPropagation();toggleCBB(i,'ms');e.target.innerHTML=S.bSelected[i].ms?ICO.check:''};
      grp.appendChild(row);
    });
    el.appendChild(grp);
  });
}
function toggleCBB(i,ftype){if(!S.bSelected[i])S.bSelected[i]={};S.bSelected[i][ftype]=!(S.bSelected[i][ftype]);}
function selAllB(){S.bGroups.forEach((g,i)=>{S.bSelected[i]={};if(g.qp)S.bSelected[i].qp=true;if(g.ms)S.bSelected[i].ms=true;});renderPreview(S.bGroups);}
function deselAllB(){S.bGroups.forEach((_,i)=>{S.bSelected[i]={qp:false,ms:false};});renderPreview(S.bGroups);}
function selQPB(){S.bGroups.forEach((g,i)=>{S.bSelected[i]={qp:!!g.qp,ms:false};});renderPreview(S.bGroups);}
function selMSB(){S.bGroups.forEach((g,i)=>{S.bSelected[i]={qp:false,ms:!!g.ms};});renderPreview(S.bGroups);}

// ── Downloads ─────────────────────────────────────────
async function doBatchDL(){
  if(!S.bGroups.length)return toast('请先点击预览','err');
  if(!S.saveDir)return toast('请选择保存目录','err');
  // Build items from bGroups with batch selection if available
  let groups=S.bGroups;
  if(S.bSelected){
    groups=[];S.bGroups.forEach((g,i)=>{
      const qpOn=S.bSelected[i]&&S.bSelected[i].qp&&g.qp;
      const msOn=S.bSelected[i]&&S.bSelected[i].ms&&g.ms;
      if(qpOn||msOn)groups.push(Object.assign({},g,qpOn?{qp:g.qp}:{qp:null},msOn?{ms:g.ms}:{ms:null}));
    });
    if(!groups.length)return toast('请至少勾选一个文件','err');
  }
  showConfirm(groups,{
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
      sel.push(Object.assign({},g,qpOn?{qp:g.qp}:{qp:null},msOn?{ms:g.ms}:{ms:null}));
    }
  });
  if(!any)return toast('请先选择文件','err');
  if(!S.saveDir)return toast('请选择保存目录','err');
  showConfirm(sel,{
    merge:document.getElementById('b-merge').checked,
    include_ms:document.getElementById('dl-ms').checked,
    rate:+document.getElementById('b-rate').value,
    threads:+document.getElementById('b-thr').value,
  });
}
function showConfirm(groups,options){
  const qpN=groups.filter(g=>g.qp).length;
  const msN=groups.filter(g=>g.ms).length;
  const hist=new Set();S.downloadHistory.forEach(f=>hist.add(f));
  const dupN=groups.filter(g=>(g.qp&&hist.has(g.qp))||(g.ms&&hist.has(g.ms))).length;
  let html=`<div class="gs" style="position:relative;padding:24px;display:flex;flex-direction:column;gap:12px;max-width:420px">
    <button class="close-btn" style="position:absolute;top:10px;right:12px;width:26px;height:26px;border-radius:50%;border:none;background:var(--glass-hover);color:var(--muted);cursor:pointer;font-size:14px" onclick="document.getElementById('confirm-overlay').classList.remove('on')">×</button>
    <h3 style="font-size:15px;font-weight:700">确认下载</h3>
    <div style="font-size:12px;color:var(--muted);line-height:1.8">
      <div>题卷 QP：${qpN} 个 &nbsp; 答案 MS：${msN} 个 &nbsp; 合计：${qpN+msN} 个</div>
      ${dupN>0?`<div style="color:var(--warn)">⚠ 其中 ${dupN} 个已在下载历史中</div>`:''}
      <div style="margin-top:4px;font-size:10px">保存到：${S.saveDir}</div>
    </div>
    <div style="display:flex;gap:8px;justify-content:flex-end">
      <button class="btn btn-sec btn-sm" onclick="document.getElementById('confirm-overlay').classList.remove('on')">取消</button>
      ${dupN>0?`<button class="btn btn-warn btn-sm" onclick="document.getElementById('confirm-overlay').classList.remove('on');beginDL(groups,options,'skip')">跳过重复</button>`:''}
      <button class="btn btn-pri btn-sm" onclick="document.getElementById('confirm-overlay').classList.remove('on');beginDL(groups,options,'overwrite')">确认下载</button>
    </div></div>`;
  document.getElementById('confirm-content').innerHTML=html;
  document.getElementById('confirm-overlay').classList.add('on');
}
async function beginDL(groups,options,dup_mode){
  options.dup_mode=dup_mode||'overwrite';
  options.rate=+document.getElementById('b-rate').value;
  options.threads=+document.getElementById('b-thr').value;
  options.merge=document.getElementById('b-merge').checked;
  options.include_ms=document.getElementById('dl-ms').checked;
  S.dlRendered=false;document.getElementById('dlbtn').disabled=true;
  document.getElementById('dlbtn').innerHTML='⏹ 取消下载';
  document.getElementById('dlbtn').className='btn btn-err';
  document.getElementById('dlbtn').onclick=cancelDownload;
  setStat('准备下载…');
  try{
    const r=JSON.parse(await pywebview.api.start_download(
      JSON.stringify(groups),S.saveDir,JSON.stringify(options)));
    if(!r.ok)throw new Error(r.error);
    if(r.skipped)toast(`已跳过 ${r.skipped} 个已下载文件`,'info');
    startPoll();
  }catch(e){toast('启动失败: '+e.message,'err');resetDLBtn();}
}
async function cancelDownload(){
  await pywebview.api.cancel_download();
  toast('正在取消...','info');
}
function resetDLBtn(){
  const b=document.getElementById('dlbtn');b.disabled=false;b.innerHTML='📥 下载选中';
  b.className='btn btn-ok';b.onclick=doDownloadSel;
}
async function startDL(groups,options){showConfirm(groups,options);}

// ── Poll ──────────────────────────────────────────────
function startPoll(){if(S.poll)clearInterval(S.poll);S.poll=setInterval(doPoll,700);}
async function doPoll(){
  try{
    const [stJson,listJson]=await Promise.all([
      pywebview.api.get_status(),pywebview.api.get_download_list(),
    ]);
    const st=JSON.parse(stJson);const items=JSON.parse(listJson);
    setStat(st.message);
    updateDLList(items);
    if(st.phase==='done'){
      clearInterval(S.poll);resetDLBtn();setDot('idle');
      const fail=items.filter(i=>i.status==='failed').length;
      if(fail){
        const net=items.filter(i=>i.error_type==='network').length;
        const nf=items.filter(i=>i.error_type==='not_found').length;
        const rl=items.filter(i=>i.error_type==='rate_limit').length;
        const px=items.filter(i=>i.error_type==='proxy').length;
        let parts=[`完成 ${st.success} 个`];if(fail)parts.push(`失败 ${fail} 个`);
        if(net)parts.push(`网络:${net}`);if(nf)parts.push(`404:${nf}`);
        if(rl)parts.push(`限流:${rl}`);if(px)parts.push(`代理:${px}`);
        toast(parts.join(', '),'warn');
      }else if(st.skipped)toast(`完成 ${st.success} 个, 跳过 ${st.skipped} 个已下载`,'ok');
      else toast(`下载完成! 共 ${st.success} 个文件`,'ok');
    }else{setDot('running');}
  }catch(e){clearInterval(S.poll);resetDLBtn();setDot('idle');}
}

// ── DL list rendering ─────────────────────────────────
const DL_ICON={pending:'⏳',downloading:'⬇',done:'✓',failed:'✗',cancelled:'⊘'};
const DL_STAT_TXT={pending:'等待',downloading:'下载中',done:'完成',cancelled:'已取消'};
function dlStatClass(s){return{pending:'s-pnd',downloading:'s-dl',done:'s-ok',failed:'s-err',cancelled:'s-pnd'}[s]||'s-pnd';}
function renderDLListFull(items){
  const el=document.getElementById('dllist');el.innerHTML='';
  if(!items.length){el.innerHTML='<div class="empty"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>等待下载...</div></div>';return;}
  items.forEach(it=>{
    const row=document.createElement('div');
    row.className=`dlrow ${it.status}`;
    row.dataset.id=it.id;
    row.dataset.status=it.status;
    row.dataset.err=it.error||'';
    row.innerHTML=`<span class="ico">${DL_ICON[it.status]||'⏳'}</span>
      <span class="dl-fname${it.status==='done'?' dim':''}"></span>
      <span class="type-${it.ftype}">${it.ftype}</span>
      <span class="dl-label"></span>
      <span class="dl-year"></span>
      <span class="dl-stat ${dlStatClass(it.status)}"></span>
      <span></span>`;
    row.querySelector('.dl-fname').textContent=it.filename;
    row.querySelector('.dl-fname').title=it.filename;
    row.querySelector('.dl-label').textContent=it.label;
    row.querySelector('.dl-label').title=it.label;
    row.querySelector('.dl-year').textContent=it.year;
    row.querySelector('.dl-stat').textContent=it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'');
    if(it.status==='failed')row.querySelector('span:last-child').innerHTML=`<button class="btn btn-err btn-sm" onclick="retryItem(${it.id})">重试</button>`;
    el.appendChild(row);
  });
  S.dlRendered=true;
}
function updateDLList(items){
  if(!S.dlRendered||!document.querySelector('.dlrow')){S.dlRendered=false;renderDLListFull(items);return;}
  items.forEach(it=>{
    const row=document.querySelector(`.dlrow[data-id="${it.id}"]`);if(!row)return;
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
  });updateDLSummary(items);
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
}
async function retryAll(){
  document.getElementById('retry-all-btn').disabled=true;
  const r=JSON.parse(await pywebview.api.retry_failed());
  if(!r.ok){toast(r.error,'err');document.getElementById('retry-all-btn').disabled=false;return;}
  if(r.count===0){toast('没有失败的项目','info');document.getElementById('retry-all-btn').disabled=false;return;}
  S.dlRendered=false;toast(`重试 ${r.count} 个失败项`,'info');startPoll();
}
async function retryItem(id){
  const btn=document.querySelector(`.dlrow[data-id="${id}"] .btn-err`);if(btn)btn.disabled=true;
  const r=JSON.parse(await pywebview.api.retry_item(id));
  if(!r.ok){toast(r.error,'err');if(btn)btn.disabled=false;return;}startPoll();
}
async function clearDLList(){
  const r=JSON.parse(await pywebview.api.clear_download_list());
  if(!r.ok){toast(r.error,'err');return;}
  S.dlRendered=false;document.getElementById('dllist').innerHTML=
    '<div class="empty"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><div>等待下载...</div></div>';
  updateDLSummary([]);setStat('就绪');setDot('idle');
}

// ── Dir ───────────────────────────────────────────────
async function browseDir(){
  const d=await pywebview.api.choose_directory();
  if(d){S.saveDir=d;document.getElementById('dir-disp').textContent=d;autoSaveSettings();}
}
function openDir(){if(S.saveDir)pywebview.api.open_folder(S.saveDir);}

// ── Helpers ───────────────────────────────────────────
function setStat(msg){const el=document.getElementById('hdr-st');if(el)el.textContent=msg;}
function setDot(s){const d=document.getElementById('hdr-dot');if(d){d.className='hdr-dot '+s;if(s==='running')d.classList.add('ok');}}
function setAllDis(dis){['sbtn','pvbtn','bdbtn','dlbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=dis;});}
function setBusy(id,html,dis,cls){const b=document.getElementById(id);if(!b)return;b.innerHTML=html;b.disabled=dis;if(cls)b.className='btn '+cls;}
function syncCB(el){const p=el.closest('.cbitem');if(p)p.classList.toggle('on',el.checked);}
function syncMS(el){el.closest('.chk-row').style.color=el.checked?'var(--muted)':'var(--err)';}
function toast(msg,type){
  const el=document.createElement('div');el.className=`toast ${type||'info'}`;
  const ico={ok:'✓',err:'✗',warn:'!',info:'i'}[type]||'';
  el.innerHTML=`<span style="font-weight:700">${ico}</span><span></span>`;
  el.querySelector('span:last-child').textContent=msg;
  document.getElementById('toasts').appendChild(el);
  setTimeout(()=>el.style.opacity='0',3500);setTimeout(()=>el.remove(),3800);
}
function esc(str){
  const d=document.createElement('div');d.textContent=str;return d.innerHTML;
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
        "C-Paper",
        html=HTML,
        js_api=api,
        width=1280, height=900,
        min_size=(1024, 700),
        background_color="#faf9f5",
    )
    api.window = window
    webview.start(debug=False)
