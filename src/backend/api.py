"""API — Python ↔ JS bridge for C-Paper"""
import json
import logging
import os
import subprocess
import threading
import time
import webbrowser
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

from .cache import read_json, write_json
from .const import BASE_URL, CACHE_DIR, HISTORY_MAX, PLUGINS_DIR, VERSION
from .engine import DownloadEngine, create_session
from .parser import build_folders, fetch_subjects, get_year, group_papers, search_papers
from .plugin_manager import PluginManager
from .updater import check_update, skip_version, set_update_check

logger = logging.getLogger(__name__)


class API:
    def __init__(self):
        self.window = None
        self._dl_items: list = []
        self._dl_lock = threading.Lock()
        self._status_lock = threading.Lock()
        self._status = {"phase": "idle", "done": 0, "total": 0, "success": 0, "message": "就绪"}
        self.engine = DownloadEngine(rate=5.0, capacity=15, max_concurrent=4)
        self._cancel = threading.Event()
        self.session = create_session()
        self._batch_tlocal = threading.local()

        self._fav_path = os.path.join(CACHE_DIR, "favorites.json")
        self._hist_path = os.path.join(CACHE_DIR, "download_history.json")
        self._settings_path = os.path.join(CACHE_DIR, "settings.json")
        self._persist_lock = threading.Lock()
        self._hist_set: set = set()
        self.plugin_manager = PluginManager(PLUGINS_DIR)
        self._hist_loaded = False

    def _ensure_hist_loaded(self):
        if self._hist_loaded:
            return
        with self._persist_lock:
            if self._hist_loaded:
                return
            hist = read_json(self._hist_path, {"items": []})
            self._hist_set = {e["filename"] for e in hist.get("items", [])}
            self._hist_loaded = True

    def _get_batch_session(self) -> requests.Session:
        if not hasattr(self._batch_tlocal, 'session') or self._batch_tlocal.session is None:
            proxy = ""
            if self.session and self.session.proxies:
                proxy = self.session.proxies.get("https", "")
            self._batch_tlocal.session = create_session(proxy)
        return self._batch_tlocal.session

    def _is_safe_filename(self, fname):
        if not fname:
            return False
        dangerous_patterns = ['..', os.path.sep, '/', '\\', '%2e', '%2E', '<', '>', ':', '|', '?', '*', '"']
        if any(pattern in fname for pattern in dangerous_patterns):
            return False
        base = os.path.basename(fname)
        if not base or base != fname:
            return False
        if base in ('.', '..') or base.startswith('.'):
            return False
        return True

    # ── Init ──

    def get_default_dir(self):
        return os.path.expanduser("~/Downloads/C-Paper")

    def get_subjects(self):
        try:
            data = fetch_subjects(self.session)
            return json.dumps({"ok": True, "data": data}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    # ── Search ──

    def search(self, subject, year, season):
        try:
            result = search_papers(self.session, subject, year, season)
            groups = group_papers(result.get("rows", []))
            try:
                self.plugin_manager.dispatch("on_search_result", {
                    "subject": subject,
                    "year": year,
                    "season": season,
                    "groups": groups,
                })
            except Exception:
                logger.exception("Plugin dispatch failed for on_search_result")
            return json.dumps({"ok": True, "groups": groups,
                               "count": len(result.get("rows", []))}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    # ── Batch Preview ──

    def batch_preview(self, params_json):
        p = json.loads(params_json)

        year_from = int(p.get("year_from", 2000))
        year_to = int(p.get("year_to", 2100))
        if not (1900 <= year_from <= year_to <= 2100):
            return json.dumps({"ok": False, "error": "年份范围无效"})

        seasons = p.get("seasons", [])
        pgs = p.get("pgs", [])
        if not seasons or not pgs:
            return json.dumps({"ok": False, "error": "请至少选择一个季度和 Paper 类型"})

        max_queries = 100
        query_count = (year_to - year_from + 1) * len(seasons)
        if query_count > max_queries:
            return json.dumps({"ok": False, "error": f"查询数量过多（{query_count}），请缩小年份范围"})

        queries = [(y, s) for y in range(year_from, year_to + 1) for s in seasons]
        all_groups = []
        errors = []
        with ThreadPoolExecutor(max_workers=3) as ex:
            futs = {ex.submit(search_papers, self._get_batch_session(), p["code"], y, s): (y, s) for y, s in queries}
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

    # ── Download ──

    def start_download(self, groups_json, save_dir, options_json):
        groups = json.loads(groups_json)
        options = json.loads(options_json)
        merge = bool(options.get("merge", False))
        include_ms = bool(options.get("include_ms", True))
        rate = float(options.get("rate", 5.0))
        threads = int(options.get("threads", 4))
        dup_mode = str(options.get("dup_mode", "overwrite"))
        rate = max(1.0, min(20.0, rate))
        threads = max(1, min(16, threads))

        self._cancel.clear()
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

                if not self._is_safe_filename(fname):
                    continue
                fname = os.path.basename(fname)
                if not fname or not fname.lower().endswith(".pdf"):
                    continue
                fdir = folders["root"] if merge else folders.get(year, {}).get(ftype_key, save_dir)
                save_path = os.path.realpath(os.path.join(fdir, fname))
                base = os.path.realpath(save_dir)
                if os.path.commonpath([base, save_path]) != base:
                    continue
                is_dup = fname in self._hist_set
                if dup_mode == "skip" and is_dup:
                    skipped_count += 1
                    continue
                if dup_mode == "missing" and is_dup and os.path.exists(save_path):
                    skipped_count += 1
                    continue
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
        # Dispatch batch start hook
        self.plugin_manager.dispatch("on_batch_start", {
            "total": len(items),
            "groups": groups,
        })
        threading.Thread(target=self._run_downloads, args=(items,), daemon=True).start()
        return json.dumps({"ok": True, "total": len(items), "skipped": skipped_count})

    def _run_downloads(self, items, retry_round: int = 0, batch_total: int = None):
        MAX_AUTO = 3
        if batch_total is None:
            batch_total = len(items)
        current_round = retry_round

        while True:
            if self._cancel.is_set():
                self._mark_all_cancelled(items)
                return

            self.engine.reset_stats(len(items))
            max_w = getattr(self.engine, '_max_concurrent', 4)
            self._execute_download_batch(items, batch_total)

            if self._cancel.is_set():
                self._mark_all_cancelled(items)
                return

            with self._dl_lock:
                failed = [i for i in self._dl_items if i["status"] == "failed"]

            if failed and current_round < MAX_AUTO:
                self._handle_auto_retry(failed, current_round)
                items = failed
                current_round += 1
            else:
                with self._dl_lock:
                    total_done = sum(1 for i in self._dl_items if i["status"] == "done")
                    failed_count = sum(1 for i in self._dl_items if i["status"] == "failed")
                    skipped_count = sum(1 for i in self._dl_items if i["status"] == "skipped")
                # Dispatch batch_complete hook before marking phase done
                self.plugin_manager.dispatch("on_batch_complete", {
                    "total": batch_total,
                    "success": total_done,
                    "failed": failed_count,
                    "skipped": skipped_count,
                    "retry_rounds": current_round,
                })
                with self._status_lock:
                    self._status["phase"] = "done"
                    self._status["total"] = batch_total
                    self._status["success"] = total_done
                    msg = f"完成 ({total_done}/{batch_total} 成功)"
                    if current_round > 0:
                        msg += f" (经过{current_round}轮重试)"
                    self._status["message"] = msg
                return

    def _create_download_worker(self):
        def worker(item):
            if self._cancel.is_set():
                return None
            with self._dl_lock:
                item["status"] = "downloading"
            self.plugin_manager.dispatch("on_download_start", {
                "filename": item["filename"],
                "save_path": item["save_path"],
                "ftype": item["ftype"],
                "label": item["label"],
                "year": item["year"],
            })
            success = None
            try:
                self.engine.download_one(item["filename"], item["save_path"])
                with self._dl_lock:
                    item["status"] = "done"
                    item["error"] = ""
                self._record_one_history(item["filename"], item["label"], item["year"], item["save_path"])
                success = True
                return True
            except requests.exceptions.Timeout:
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = "网络超时"
                    item["error_type"] = "network"
                success = False
                return False
            except requests.exceptions.ConnectionError:
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = "连接失败"
                    item["error_type"] = "network"
                success = False
                return False
            except requests.exceptions.HTTPError as e:
                code = e.response.status_code if e.response is not None else 0
                with self._dl_lock:
                    item["status"] = "failed"
                    if code == 404:
                        item["error"] = "文件不存在 (404)"
                        item["error_type"] = "not_found"
                    elif code == 429:
                        item["error"] = "请求过频 (429)"
                        item["error_type"] = "rate_limit"
                    elif code >= 500:
                        item["error"] = f"服务器错误 ({code})"
                        item["error_type"] = "server"
                    else:
                        item["error"] = f"HTTP {code}"
                        item["error_type"] = "unknown"
                success = False
                return False
            except Exception as e:
                msg = str(e)
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"] = msg
                    if "proxy" in msg.lower() or "代理" in msg:
                        item["error_type"] = "proxy"
                    elif "断路器" in msg:
                        item["error_type"] = "rate_limit"
                    else:
                        item["error_type"] = "unknown"
                success = False
                return False
            finally:
                try:
                    if success:
                        self.plugin_manager.dispatch("on_download_complete", {
                            "filename": item["filename"],
                            "save_path": item["save_path"],
                            "ftype": item["ftype"],
                            "label": item["label"],
                            "year": item["year"],
                        })
                    elif success is False:
                        self.plugin_manager.dispatch("on_download_failed", {
                            "filename": item["filename"],
                            "ftype": item["ftype"],
                            "label": item["label"],
                            "year": item["year"],
                            "error": item.get("error", ""),
                            "error_type": item.get("error_type", "unknown"),
                        })
                except Exception:
                    logger.exception("Plugin dispatch failed in download worker")
        return worker

    def _execute_download_batch(self, items, batch_total):
        worker = self._create_download_worker()
        max_w = getattr(self.engine, '_max_concurrent', 4)
        done_count = 0
        fail_count = 0
        with ThreadPoolExecutor(max_workers=max_w) as ex:
            futures = [ex.submit(worker, item) for item in items]
            for fut in as_completed(futures):
                if self._cancel.is_set():
                    break
                result = fut.result()
                if result is not None:
                    self.engine.record_result(result)
                if result is True:
                    done_count += 1
                elif result is False:
                    fail_count += 1
                with self._status_lock:
                    self._status["done"] = done_count + fail_count
                    self._status["total"] = batch_total
                    self._status["success"] = done_count
                    self._status["message"] = f"下载中... ({done_count+fail_count}/{batch_total})"

    def _handle_auto_retry(self, failed, current_round):
        delay = min(5 * (2 ** current_round), 30)
        with self._status_lock:
            self._status["message"] = f"{len(failed)} 失败, {delay}s 后自动重试 (第{current_round+1}轮)..."
        time.sleep(delay)
        if self._cancel.is_set():
            return
        with self._dl_lock:
            for item in failed:
                item["status"] = "pending"
                item["error"] = ""

    def _mark_all_cancelled(self, items):
        with self._dl_lock:
            for item in self._dl_items:
                if item["status"] in ("pending", "downloading"):
                    item["status"] = "cancelled"
                    item["error"] = "用户取消"
        with self._status_lock:
            self._status["phase"] = "done"
            self._status["message"] = "已取消"

    def cancel_download(self):
        self._cancel.set()
        return json.dumps({"ok": True})

    # ── Download history ──

    def _record_one_history(self, filename, label, year, save_path=""):
        self._ensure_hist_loaded()
        with self._persist_lock:
            if filename in self._hist_set:
                return
            hist = read_json(self._hist_path, {"items": []})
            hist["items"].append({
                "filename": filename, "label": label, "year": year,
                "save_path": save_path,
                "downloaded_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            })
            if len(hist["items"]) > HISTORY_MAX:
                evicted = hist["items"][:-HISTORY_MAX]
                hist["items"] = hist["items"][-HISTORY_MAX:]
                for e in evicted:
                    self._hist_set.discard(e["filename"])
            write_json(self._hist_path, hist)
            self._hist_set.add(filename)

    def get_download_history(self):
        hist = read_json(self._hist_path, {"items": []})
        return json.dumps(hist.get("items", []))

    def check_downloaded(self, filename):
        self._ensure_hist_loaded()
        return json.dumps({"downloaded": filename in self._hist_set, "date": ""})

    def clear_history(self):
        with self._persist_lock:
            write_json(self._hist_path, {"items": []})
            self._hist_set.clear()
        return json.dumps({"ok": True})

    # ── Status / List ──

    def get_status(self):
        with self._status_lock:
            return json.dumps(dict(self._status), ensure_ascii=False)

    def get_download_list(self):
        with self._dl_lock:
            return json.dumps(list(self._dl_items), ensure_ascii=False)

    # ── Retry ──

    def retry_failed(self):
        self._cancel.clear()
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
        self._cancel.clear()
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

    # ── Favorites ──

    def get_favorites(self):
        return json.dumps(read_json(self._fav_path, []))

    def add_favorite(self, code, name):
        with self._persist_lock:
            data = read_json(self._fav_path, [])
            if not any(f.get("code") == code for f in data):
                data.append({"code": code, "name": name})
                write_json(self._fav_path, data)
        return json.dumps({"ok": True})

    def remove_favorite(self, code):
        with self._persist_lock:
            data = read_json(self._fav_path, [])
            data = [f for f in data if f.get("code") != code]
            write_json(self._fav_path, data)
        return json.dumps({"ok": True})

    # ── Settings ──

    def load_settings(self):
        defaults = {
            "theme": "light", "save_dir": self.get_default_dir(),
            "include_ms": True, "rate": 5, "threads": 4,
            "merge": False, "proxy_url": "", "last_subject": "",
            "last_mode": "search",
        }
        saved = read_json(self._settings_path, {})
        defaults.update(saved)
        return json.dumps(defaults)

    def save_settings(self, settings_json):
        with self._persist_lock:
            write_json(self._settings_path, json.loads(settings_json))
        return json.dumps({"ok": True})

    # ── Proxy ──

    def get_pdf_url(self, filename):
        if not filename or '/' in filename or '\\' in filename or '..' in filename:
            return json.dumps({"ok": False, "error": "无效文件名"})
        filename = os.path.basename(filename)
        url = f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"
        return json.dumps({"ok": True, "url": url})

    def set_proxy(self, proxy_url):
        with self._status_lock:
            if self._status["phase"] == "running":
                return json.dumps({"ok": False, "error": "下载进行中，无法修改代理"})
        try:
            old = self.session
            self.session = create_session(proxy_url)
            try: old.close()
            except Exception: pass
            self.engine.rebuild_session(proxy_url)
            self._batch_tlocal = threading.local()
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def get_proxy(self):
        p = self.session.proxies.get("https", "") if self.session and self.session.proxies else ""
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

    # ── File system ──

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

    # ── Auto Update ──

    def check_update(self, force="false"):
        try:
            result = check_update(force=(force.lower() == "true"))
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e), "has_update": False})

    def skip_version(self, version):
        try:
            skip_version(version)
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def set_update_check(self, enabled_json):
        try:
            enabled = json.loads(enabled_json)
            set_update_check(bool(enabled))
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def open_url(self, url):
        """Open URL in system default browser."""
        try:
            webbrowser.open(url)
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    # ── Plugins ──

    def get_plugins(self):
        try:
            return json.dumps({"ok": True, "plugins": self.plugin_manager.list_plugins()}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def toggle_plugin(self, plugin_id, enabled_json):
        try:
            enabled = json.loads(enabled_json)
            ok = self.plugin_manager.enable_plugin(plugin_id, bool(enabled))
            return json.dumps({"ok": ok})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def get_plugin_config(self, plugin_id):
        try:
            config = self.plugin_manager.get_plugin_config(plugin_id)
            return json.dumps({"ok": True, "config": config}, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def set_plugin_config(self, plugin_id, config_json):
        try:
            config = json.loads(config_json)
            ok = self.plugin_manager.set_plugin_config(plugin_id, config)
            return json.dumps({"ok": ok})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})

    def open_plugins_dir(self):
        try:
            import sys
            if sys.platform == "darwin":
                subprocess.run(["open", PLUGINS_DIR])
            elif sys.platform == "win32":
                subprocess.run(["explorer", PLUGINS_DIR])
            else:
                subprocess.run(["xdg-open", PLUGINS_DIR])
            return json.dumps({"ok": True})
        except Exception as e:
            return json.dumps({"ok": False, "error": str(e)})
