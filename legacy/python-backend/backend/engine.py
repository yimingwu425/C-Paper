"""DownloadEngine — rate-limited, circuit-breaker-protected PDF downloader"""
import os
import shutil
import threading

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .const import BASE_URL, USER_AGENT
from .limiter import CircuitBreaker, TokenBucket


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
        self._active_count = 0
        self._active_cond = threading.Condition()
        self.breaker = CircuitBreaker(failure_threshold=5, recovery_timeout=30.0)
        self._lock = threading.Lock()
        self._stats = {"done": 0, "success": 0, "failed": 0}
        self._proxy_url = ""
        self._tlocal = threading.local()

    def _acquire_slot(self):
        with self._active_cond:
            while self._active_count >= self._max_concurrent:
                if not self._active_cond.wait(timeout=60):
                    raise TimeoutError("timed out waiting for download slot")
            self._active_count += 1

    def _release_slot(self):
        with self._active_cond:
            self._active_count -= 1
            self._active_cond.notify()

    def _get_worker_session(self) -> requests.Session:
        if not hasattr(self._tlocal, 'session') or self._tlocal.session is None:
            self._tlocal.session = create_session(self._proxy_url)
        return self._tlocal.session

    def update_rate(self, rate: float):
        self.bucket.update_rate(rate)

    def update_concurrency(self, n: int):
        with self._active_cond:
            self._max_concurrent = n
            self._active_cond.notify_all()

    def download_one(self, filename: str, save_path: str) -> None:
        st = self.breaker.state
        if st == CircuitBreaker.OPEN:
            raise RuntimeError("CB open — server overloaded")
        self.bucket.acquire()
        self._acquire_slot()
        tmp_path = f"{save_path}.part.{threading.get_ident()}"
        try:
            url = f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"
            try:
                with self._get_worker_session().get(url, timeout=(10, 60), stream=True) as resp:
                    resp.raise_for_status()
                    os.makedirs(os.path.dirname(save_path) or ".", exist_ok=True)
                    with open(tmp_path, "wb") as f:
                        shutil.copyfileobj(resp.raw, f, length=1024 * 1024)
                    os.replace(tmp_path, save_path)
                self.breaker.record_success()
            except requests.exceptions.HTTPError as e:
                try:
                    os.unlink(tmp_path)
                except FileNotFoundError:
                    pass
                code = e.response.status_code if e.response is not None else 0
                if code == 429:
                    self.bucket.drain()
                if code == 429 or code >= 500:
                    self.breaker.record_failure()
                raise
            except requests.exceptions.RequestException:
                try:
                    os.unlink(tmp_path)
                except FileNotFoundError:
                    pass
                self.breaker.record_failure()
                raise
            except Exception:
                try:
                    os.unlink(tmp_path)
                except FileNotFoundError:
                    pass
                raise
        finally:
            self._release_slot()

    def rebuild_session(self, proxy_url: str = ""):
        self._proxy_url = proxy_url
        if hasattr(self._tlocal, 'session'):
            try: self._tlocal.session.close()
            except Exception: pass
            self._tlocal.session = None

    def reset_stats(self, total: int):
        with self._lock:
            self._stats = {"done": 0, "success": 0, "failed": 0, "total": total}

    def record_result(self, success: bool):
        with self._lock:
            self._stats["done"] += 1
            if success: self._stats["success"] += 1
            else: self._stats["failed"] += 1

    def get_stats(self):
        with self._lock:
            return dict(self._stats)
