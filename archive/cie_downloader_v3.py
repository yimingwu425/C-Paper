#!/usr/bin/env python3
"""CIE 试卷下载器 v3 — 毛玻璃 UI (pywebview)"""

import webview
import json, os, re, threading, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.request, urllib.parse

BASE_URL  = "https://cie.fraft.cn"
SEASONS   = [("Mar","春季"),("Jun","夏季"),("Nov","冬季")]
CACHE_DIR = os.path.expanduser("~/.cie_cache")


# ── 缓存 ──────────────────────────────────────────────

def load_cache(key):
    p = os.path.join(CACHE_DIR, f"{key}.json")
    if os.path.exists(p):
        try:
            with open(p, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return None

def save_cache(key, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(os.path.join(CACHE_DIR,f"{key}.json"),"w",encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass


# ── 网络 API ──────────────────────────────────────────

def fetch_subjects():
    req = urllib.request.Request(
        f"{BASE_URL}/obj/Common/Subject/combo",
        method="POST", headers={"Content-Length":"0"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())

def search_papers(subject, year, season):
    key = f"{subject}_{year}_{season}"
    cached = load_cache(key)
    if cached:
        return cached
    data = urllib.parse.urlencode(
        {"subject":str(subject),"year":str(year),"season":season}
    ).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/obj/Common/Fetch/renum", data=data, method="POST",
        headers={"Content-Type":"application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        result = json.loads(r.read().decode())
        save_cache(key, result)
        return result

def download_file(filename, save_path):
    url = f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"
    req = urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r, open(save_path,"wb") as f:
        f.write(r.read())

def safe_download(filename, save_path, delay=1.0, retries=3):
    import time
    for attempt in range(retries):
        try:
            if delay > 0 and attempt > 0:
                time.sleep(delay)
            download_file(filename, save_path)
            return
        except Exception as e:
            if attempt == retries - 1:
                raise
            time.sleep(2.0 * (attempt + 1))


# ── 解析 & 分组 ───────────────────────────────────────

def parse_filename(fname):
    m = re.match(r"(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf", fname)
    if not m: return None
    return dict(subject=m.group(1), sy=m.group(2), type=m.group(3),
                number=m.group(4) or "", filename=fname)

def get_year(sy):
    y = sy[1:] if len(sy) > 1 and sy[0] in "msw" else "unknown"
    return "20" + y if y.isdigit() and len(y) == 2 else y

def paper_group_of(number):
    if not number: return 0
    n = int(number)
    return n // 10 if n >= 10 else n

def group_papers(rows):
    pairs, standalone = {}, []
    for row in rows:
        fname = row["file"]
        p = parse_filename(fname)
        if not p or p["type"] not in ("qp","ms"):
            standalone.append(dict(label=fname.replace(".pdf",""), files={fname:fname},
                                   has_qp=False, has_ms=False, is_standalone=True,
                                   paper_group=0, sy="", number=""))
            continue
        key = (p["subject"], p["sy"], p["number"])
        if key not in pairs:
            pairs[key] = dict(subject=p["subject"], sy=p["sy"], number=p["number"],
                              files={}, has_qp=False, has_ms=False, is_standalone=False,
                              paper_group=paper_group_of(p["number"]))
        pairs[key]["files"][p["type"]] = fname
        if p["type"] == "qp": pairs[key]["has_qp"] = True
        else:                  pairs[key]["has_ms"] = True

    result = list(pairs.values()) + standalone
    result.sort(key=lambda g: (g["paper_group"],
                               int(g["number"]) if g["number"].isdigit() else 999))
    return result

def build_folders(groups, save_dir, merge):
    """预建目录，返回 {year: {qp:.., ms:..}} 或 {'root':...}"""
    os.makedirs(save_dir, exist_ok=True)
    folders = {}
    if merge:
        folders["root"] = save_dir
        return folders
    for g in groups:
        year = get_year(g.get("sy",""))
        if year not in folders:
            folders[year] = {
                "qp": os.path.join(save_dir, year, "QP"),
                "ms": os.path.join(save_dir, year, "MS"),
            }
            os.makedirs(folders[year]["qp"], exist_ok=True)
            os.makedirs(folders[year]["ms"], exist_ok=True)
    return folders


# ── Python ↔ JS 桥接 ──────────────────────────────────

class API:
    def __init__(self):
        self.window   = None
        self._status  = {"phase":"idle","done":0,"total":0,"success":0,"message":"就绪"}
        self._dl_items: list = []          # 每个文件的下载状态
        self._dl_lock = threading.Lock()

    # ── 初始化 / 工具 ──────────────────────────────────

    def get_default_dir(self):
        return os.path.expanduser("~/Downloads/CIE_Papers")

    def get_subjects(self):
        try:
            data = fetch_subjects()
            return json.dumps({"ok":True,"data":data})
        except Exception as e:
            return json.dumps({"ok":False,"error":str(e)})

    # ── 搜索 ───────────────────────────────────────────

    def search(self, subject, year, season):
        try:
            result = search_papers(subject, year, season)
            groups = group_papers(result.get("rows",[]))
            return json.dumps({"ok":True,"groups":groups,"count":len(result.get("rows",[]))})
        except Exception as e:
            return json.dumps({"ok":False,"error":str(e)})

    # ── 批量预览 ───────────────────────────────────────

    def batch_preview(self, params_json):
        try:
            p = json.loads(params_json)
            queries = [(y,s)
                       for y in range(int(p["year_from"]), int(p["year_to"])+1)
                       for s in p["seasons"]]
            all_groups = []
            with ThreadPoolExecutor(max_workers=3) as ex:
                futs = {ex.submit(search_papers, p["code"], y, s): (y,s) for y,s in queries}
                for fut in as_completed(futs):
                    try:
                        res = fut.result(timeout=30)
                        gs = group_papers(res.get("rows",[]))
                        all_groups.extend(
                            g for g in gs
                            if not g["is_standalone"] and g["paper_group"] in p["pgs"]
                        )
                    except Exception:
                        pass
            return json.dumps({"ok":True,"groups":all_groups})
        except Exception as e:
            return json.dumps({"ok":False,"error":str(e)})

    # ── 下载 ───────────────────────────────────────────

    def start_download(self, groups_json, save_dir, options_json):
        groups  = json.loads(groups_json)
        options = json.loads(options_json)
        merge   = bool(options.get("merge", False))
        delay   = float(options.get("delay", 1.0))
        threads = int(options.get("threads", 4))

        folders = build_folders(groups, save_dir, merge)

        # 预构建每个文件的下载项
        items = []
        for g in groups:
            year  = get_year(g.get("sy",""))
            label = f"Paper {g['number']}" if not g["is_standalone"] else g.get("label","")
            for ftype in ("qp","ms"):
                fname = g["files"].get(ftype)
                if not fname: continue
                if merge:
                    fdir = folders["root"]
                else:
                    fdir = folders.get(year, {}).get(ftype, save_dir)
                items.append({
                    "id":        len(items),
                    "filename":  fname,
                    "ftype":     ftype.upper(),
                    "label":     label,
                    "year":      year,
                    "save_path": os.path.join(fdir, fname),
                    "status":    "pending",
                    "error":     "",
                })

        with self._dl_lock:
            self._dl_items = items
        self._status = {"phase":"running","done":0,"total":len(items),"success":0,"message":"准备下载..."}
        threading.Thread(target=self._run_downloads,
                         args=(items, delay, threads), daemon=True).start()
        return json.dumps({"ok":True,"total":len(items)})

    def _run_downloads(self, items, delay, threads):
        lock = threading.Lock()
        total = len(items)

        def worker(item):
            with self._dl_lock:
                item["status"] = "downloading"
            try:
                safe_download(item["filename"], item["save_path"], delay)
                with self._dl_lock:
                    item["status"] = "done"
                return True
            except Exception as e:
                with self._dl_lock:
                    item["status"] = "failed"
                    item["error"]  = str(e)
                return False

        def on_done(future):
            with lock:
                self._status["done"] += 1
                try:
                    if future.result():
                        self._status["success"] += 1
                except Exception:
                    pass
                done = self._status["done"]
                suc  = self._status["success"]
                self._status["message"] = f"下载中... ({done}/{total})"
                if done >= total:
                    self._status["phase"]   = "done"
                    self._status["message"] = f"完成 ({suc}/{total} 成功)"

        with ThreadPoolExecutor(max_workers=threads) as ex:
            for item in items:
                ex.submit(worker, item).add_done_callback(on_done)

    # ── 状态查询 ───────────────────────────────────────

    def get_status(self):
        return json.dumps(self._status)

    def get_download_list(self):
        with self._dl_lock:
            return json.dumps(list(self._dl_items))

    # ── 重试 ───────────────────────────────────────────

    def retry_failed(self):
        if self._status["phase"] == "running":
            return json.dumps({"ok":False,"error":"下载进行中，请等待完成"})
        with self._dl_lock:
            failed = [i for i in self._dl_items if i["status"] == "failed"]
            for i in failed:
                i["status"] = "pending"
                i["error"]  = ""
        if not failed:
            return json.dumps({"ok":True,"count":0})
        delay   = 1.0
        threads = 4
        self._status = {"phase":"running","done":0,"total":len(failed),"success":0,"message":"重试中..."}
        threading.Thread(target=self._run_downloads,
                         args=(failed, delay, threads), daemon=True).start()
        return json.dumps({"ok":True,"count":len(failed)})

    def retry_item(self, item_id):
        if self._status["phase"] == "running":
            return json.dumps({"ok":False,"error":"下载进行中"})
        with self._dl_lock:
            item = next((i for i in self._dl_items if i["id"] == item_id), None)
            if not item:
                return json.dumps({"ok":False,"error":"找不到该项"})
            item["status"] = "pending"
            item["error"]  = ""
        self._status = {"phase":"running","done":0,"total":1,"success":0,"message":"重试中..."}
        threading.Thread(target=self._run_downloads,
                         args=([item], 1.0, 1), daemon=True).start()
        return json.dumps({"ok":True})

    def clear_download_list(self):
        if self._status["phase"] == "running":
            return json.dumps({"ok":False,"error":"下载进行中"})
        with self._dl_lock:
            self._dl_items = []
        self._status = {"phase":"idle","done":0,"total":0,"success":0,"message":"就绪"}
        return json.dumps({"ok":True})

    # ── 文件系统 ───────────────────────────────────────

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
            else:                              # Linux
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


# ── HTML / CSS / JS ───────────────────────────────────

HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>CIE 试卷下载器</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --blur:saturate(180%) blur(28px);
  --glass:rgba(255,255,255,0.07);
  --glass-b:rgba(255,255,255,0.12);
  --border:rgba(255,255,255,0.13);
  --border-s:rgba(255,255,255,0.21);
  --accent:#818cf8;--accent2:#6366f1;
  --text:rgba(255,255,255,0.93);--muted:rgba(255,255,255,0.46);
  --ok:#4ade80;--err:#f87171;--warn:#fb923c;
  --r:14px;--rs:8px;
}
html,body{height:100%;overflow:hidden;
  font-family:-apple-system,'SF Pro Text','Helvetica Neue',sans-serif;
  background:#090915;color:var(--text);-webkit-font-smoothing:antialiased;}

/* ── Background ── */
.bg{position:fixed;inset:0;z-index:0;
  background:radial-gradient(ellipse 80% 60% at 8% 8%,#1e1b4b,transparent),
             radial-gradient(ellipse 70% 60% at 92% 92%,#1a103a,transparent),#090915;}
.orb{position:fixed;border-radius:50%;pointer-events:none;filter:blur(90px);}
.o1{width:700px;height:700px;top:-180px;left:-120px;
    background:radial-gradient(circle,rgba(79,70,229,.42),transparent 70%);}
.o2{width:550px;height:550px;bottom:-120px;right:-80px;
    background:radial-gradient(circle,rgba(124,58,237,.32),transparent 70%);}
.o3{width:400px;height:400px;top:42%;left:46%;
    background:radial-gradient(circle,rgba(14,165,233,.18),transparent 70%);}

/* ── Glass ── */
.g {background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
    border:1px solid var(--border);border-radius:var(--r);}
.gs{background:var(--glass-b);backdrop-filter:saturate(200%) blur(36px);
    -webkit-backdrop-filter:saturate(200%) blur(36px);
    border:1px solid var(--border-s);border-radius:var(--r);}

/* ── Layout ── */
.app{position:relative;z-index:1;display:flex;flex-direction:column;
     height:100vh;padding:14px;gap:10px;}

/* ── Header ── */
.hdr{padding:12px 22px;display:flex;align-items:center;gap:10px;flex-shrink:0;}
.hdr-icon{font-size:21px;}
.hdr-title{font-size:17px;font-weight:700;letter-spacing:-.3px;}
.badge{background:var(--accent2);color:#fff;font-size:10px;font-weight:700;
       padding:2px 9px;border-radius:20px;letter-spacing:.4px;}
.hdr-status{margin-left:auto;font-size:12px;color:var(--muted);}

/* ── Tabs ── */
.tabs{padding:5px;display:flex;gap:4px;flex-shrink:0;}
.tab{flex:1;padding:8px 14px;border:none;border-radius:var(--rs);
     background:transparent;color:var(--muted);font-size:13px;font-weight:500;
     cursor:pointer;transition:all .18s;}
.tab:hover{color:var(--text);background:rgba(255,255,255,.05);}
.tab.on{background:rgba(129,140,248,.18);color:var(--accent);font-weight:600;}

/* ── Panels ── */
.panel{display:none;flex-direction:column;gap:10px;flex:1;min-height:0;overflow:hidden;}
.panel.on{display:flex;}

/* ── Controls ── */
.ctrl{padding:14px 18px;flex-shrink:0;}
.row{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap;}
.fld{display:flex;flex-direction:column;gap:5px;}
.fld.grow{flex:1;min-width:180px;}
.lbl{font-size:10px;color:var(--muted);font-weight:600;
     text-transform:uppercase;letter-spacing:.5px;}

/* ── Inputs ── */
select,input[type=text]{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.11);
  border-radius:var(--rs);color:var(--text);font-size:13px;padding:8px 11px;outline:none;
  width:100%;transition:border-color .18s;-webkit-appearance:none;appearance:none;}
select{background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='rgba(255,255,255,.45)' stroke-width='2'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:right 9px center;padding-right:28px;}
select option{background:#1e1b4b;color:#fff;}
select:focus,input:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(129,140,248,.15);}

/* ── Buttons ── */
.btn{display:inline-flex;align-items:center;gap:6px;padding:9px 18px;border-radius:var(--rs);
     font-size:13px;font-weight:600;cursor:pointer;border:none;transition:all .18s;white-space:nowrap;}
.btn-p{background:linear-gradient(135deg,#6366f1,#818cf8);color:#fff;
       box-shadow:0 4px 14px rgba(99,102,241,.3);}
.btn-p:hover{transform:translateY(-1px);box-shadow:0 7px 20px rgba(99,102,241,.45);}
.btn-s{background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.13);color:var(--text);}
.btn-s:hover{background:rgba(255,255,255,.12);}
.btn-g{background:linear-gradient(135deg,#059669,#10b981);color:#fff;
       box-shadow:0 4px 14px rgba(16,185,129,.3);}
.btn-g:hover{transform:translateY(-1px);box-shadow:0 7px 20px rgba(16,185,129,.4);}
.btn-r{background:linear-gradient(135deg,#dc2626,#ef4444);color:#fff;
       box-shadow:0 4px 14px rgba(239,68,68,.3);}
.btn-r:hover{transform:translateY(-1px);box-shadow:0 7px 20px rgba(239,68,68,.4);}
.btn:disabled{opacity:.35;cursor:not-allowed;transform:none!important;box-shadow:none!important;}
.btn-sm{padding:5px 12px;font-size:12px;}

/* ── Toolbar ── */
.tbar{display:flex;align-items:center;gap:7px;margin-bottom:10px;flex-shrink:0;}
.tbar-r{margin-left:auto;font-size:12px;color:var(--muted);}

/* ── Result list ── */
.rlist-wrap{flex:1;overflow-y:auto;min-height:0;
            border:1px solid rgba(255,255,255,.07);border-radius:var(--rs);}
.rlist-wrap::-webkit-scrollbar{width:5px;}
.rlist-wrap::-webkit-scrollbar-thumb{background:rgba(255,255,255,.12);border-radius:3px;}
.rhead{display:grid;grid-template-columns:32px 80px 1fr 1fr 44px;gap:8px;padding:8px 13px;
  background:rgba(255,255,255,.035);border-bottom:1px solid rgba(255,255,255,.06);
  font-size:10px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;
  position:sticky;top:0;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);}
.rgrp-hdr{padding:6px 13px;font-size:11px;font-weight:600;color:var(--accent);
  background:rgba(129,140,248,.06);border-bottom:1px solid rgba(255,255,255,.04);
  cursor:pointer;display:flex;align-items:center;gap:6px;transition:background .15s;}
.rgrp-hdr:hover{background:rgba(129,140,248,.12);}
.rrow{display:grid;grid-template-columns:32px 80px 1fr 1fr 44px;gap:8px;padding:8px 13px;
  border-bottom:1px solid rgba(255,255,255,.04);cursor:pointer;font-size:12px;
  align-items:center;transition:background .12s;}
.rrow:hover{background:rgba(255,255,255,.04);}
.rrow.sel{background:rgba(129,140,248,.1);}
.chk{font-size:15px;}
.fname{font-family:'SF Mono','Menlo',monospace;font-size:11px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.fok{color:var(--ok)}.fno{color:var(--muted);opacity:.4;}
.sok{color:var(--ok);font-size:13px;}.sbad{color:var(--err);font-size:13px;}

/* ── Batch ── */
.bgrid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:12px;}
.bsec-t{font-size:10px;color:var(--muted);font-weight:600;
  text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px;}
.cbgrp{display:flex;gap:8px;flex-wrap:wrap;}
.cbitem{display:flex;align-items:center;gap:5px;cursor:pointer;font-size:12px;
  padding:5px 10px;border-radius:6px;border:1px solid rgba(255,255,255,.1);
  transition:all .15s;user-select:none;}
.cbitem:hover{background:rgba(255,255,255,.05);}
.cbitem.on{background:rgba(129,140,248,.13);border-color:rgba(129,140,248,.32);}
.cbitem input{accent-color:var(--accent);width:13px;height:13px;}
.srow{display:flex;align-items:center;gap:8px;}
input[type=range]{flex:1;height:4px;border-radius:2px;
  background:rgba(255,255,255,.15);accent-color:var(--accent);cursor:pointer;}
.sval{font-size:12px;color:var(--muted);width:36px;text-align:right;
  font-variant-numeric:tabular-nums;}

/* ── Preview text ── */
.prev{flex:1;overflow-y:auto;min-height:0;background:rgba(0,0,0,.22);
  border:1px solid rgba(255,255,255,.06);border-radius:var(--rs);padding:13px;
  font-family:'SF Mono','Menlo',monospace;font-size:12px;line-height:1.75;
  color:var(--muted);white-space:pre-wrap;}
.prev::-webkit-scrollbar{width:5px;}
.prev::-webkit-scrollbar-thumb{background:rgba(255,255,255,.1);border-radius:3px;}
.py{color:var(--accent);font-weight:600;}.pf{color:rgba(255,255,255,.72);}

/* ── Download list ── */
.dlsummary{display:flex;align-items:center;gap:12px;padding:10px 14px;
  border-bottom:1px solid rgba(255,255,255,.07);flex-shrink:0;font-size:12px;}
.cnt-ok {color:var(--ok); font-weight:600;}
.cnt-err{color:var(--err);font-weight:600;}
.cnt-pnd{color:var(--muted);}
.cnt-dl {color:var(--accent);font-weight:600;}

.dlwrap{flex:1;overflow-y:auto;min-height:0;}
.dlwrap::-webkit-scrollbar{width:5px;}
.dlwrap::-webkit-scrollbar-thumb{background:rgba(255,255,255,.12);border-radius:3px;}

.dlrow{display:grid;
  grid-template-columns:26px 1fr 50px 90px 52px minmax(80px,1fr) 64px;
  gap:8px;padding:8px 14px;border-bottom:1px solid rgba(255,255,255,.04);
  font-size:12px;align-items:center;transition:background .12s;}
.dlrow:last-child{border-bottom:none;}
.dlrow:hover{background:rgba(255,255,255,.03);}
.dlrow.downloading{background:rgba(99,102,241,.06);}
.dlrow.failed     {background:rgba(248,113,113,.06);}
.dlrow.done       {}
.dlrow .ico{font-size:14px;text-align:center;}
.dlrow .dl-fname{font-family:'SF Mono','Menlo',monospace;font-size:11px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text);}
.dl-fname.dim{color:var(--muted);}
.type-QP{background:rgba(99,102,241,.2);color:#a5b4fc;
  padding:2px 7px;border-radius:4px;font-size:10px;font-weight:700;text-align:center;}
.type-MS{background:rgba(16,185,129,.2);color:#6ee7b7;
  padding:2px 7px;border-radius:4px;font-size:10px;font-weight:700;text-align:center;}
.dl-label{color:var(--muted);font-size:11px;overflow:hidden;
  text-overflow:ellipsis;white-space:nowrap;}
.dl-year{color:var(--muted);font-size:11px;text-align:center;}
.dl-stat{font-size:11px;}
.dl-stat.s-pnd{color:var(--muted);}
.dl-stat.s-dl {color:var(--accent);}
.dl-stat.s-ok {color:var(--ok);}
.dl-stat.s-err{color:var(--err);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.dl-act{text-align:right;}

/* ── Download bar ── */
.dlbar{padding:11px 18px;display:flex;align-items:center;gap:14px;flex-shrink:0;}
.dir-row{display:flex;align-items:center;gap:8px;flex:1;min-width:0;}
.dir-disp{flex:1;min-width:0;background:rgba(255,255,255,.05);
  border:1px solid rgba(255,255,255,.09);border-radius:6px;color:var(--muted);
  font-size:11px;font-family:'SF Mono','Menlo',monospace;padding:7px 10px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.prog-sec{display:flex;align-items:center;gap:11px;flex-shrink:0;}
.prog-wrap{width:150px;height:5px;background:rgba(255,255,255,.1);
  border-radius:3px;overflow:hidden;}
.prog-fill{height:100%;width:0%;border-radius:3px;
  background:linear-gradient(90deg,#6366f1,#818cf8);transition:width .35s ease;}
.stat{font-size:12px;color:var(--muted);white-space:nowrap;min-width:100px;}

/* ── Spinner ── */
.spin{display:inline-block;width:12px;height:12px;
  border:2px solid rgba(255,255,255,.18);border-top-color:var(--accent);
  border-radius:50%;animation:sp .65s linear infinite;vertical-align:middle;}
@keyframes sp{to{transform:rotate(360deg)}}

/* ── Empty state ── */
.empty{display:flex;flex-direction:column;align-items:center;
  justify-content:center;height:100%;gap:10px;color:var(--muted);}
.empty-ico{font-size:36px;opacity:.3;}

/* ── Toast ── */
#toasts{position:fixed;top:16px;right:16px;z-index:999;
  display:flex;flex-direction:column;gap:7px;pointer-events:none;}
.toast{background:rgba(18,16,38,.97);
  backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);
  border:1px solid rgba(255,255,255,.12);border-radius:10px;
  padding:10px 14px;font-size:13px;min-width:210px;
  display:flex;gap:8px;align-items:flex-start;
  animation:tin .22s ease;pointer-events:auto;}
.toast.ok {border-left:3px solid var(--ok);}
.toast.err{border-left:3px solid var(--err);}
.toast.inf{border-left:3px solid var(--accent);}
@keyframes tin{from{transform:translateX(110%);opacity:0}}
</style>
</head>
<body>

<div class="bg"></div>
<div class="orb o1"></div><div class="orb o2"></div><div class="orb o3"></div>
<div id="toasts"></div>

<div class="app">

  <!-- Header -->
  <header class="hdr g">
    <span class="hdr-icon">📚</span>
    <span class="hdr-title">CIE 试卷下载器</span>
    <span class="badge">v3.0</span>
    <span class="hdr-status" id="hdr-st">加载中...</span>
  </header>

  <!-- Tabs -->
  <div class="tabs g">
    <button class="tab on"  onclick="switchTab('search')">🔍 按次搜索</button>
    <button class="tab"     onclick="switchTab('batch')">📦 批量下载</button>
    <button class="tab"     onclick="switchTab('dllist')" id="tab-dl">📋 下载列表</button>
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
          <select id="s-year" style="width:88px"></select>
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
          <button class="btn btn-p" id="sbtn" onclick="doSearch()">🔍 搜索</button>
        </div>
      </div>
    </div>

    <div class="gs" style="flex:1;min-height:0;padding:15px 18px;display:flex;flex-direction:column;overflow:hidden;">
      <div class="tbar">
        <button class="btn btn-s btn-sm" onclick="selAll()">全选</button>
        <button class="btn btn-s btn-sm" onclick="deselAll()">全不选</button>
        <button class="btn btn-s btn-sm" onclick="selQP()">仅 QP</button>
        <button class="btn btn-s btn-sm" onclick="selMS()">仅 MS</button>
        <span class="tbar-r" id="rcnt">共 0 项</span>
      </div>
      <div class="rhead">
        <div></div><div>编号</div><div>题卷 QP</div><div>答案 MS</div><div>状态</div>
      </div>
      <div class="rlist-wrap" id="rlist">
        <div class="empty"><div class="empty-ico">🔍</div><div>搜索后显示结果</div></div>
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
          <select id="b-yfrom" style="width:88px"></select>
        </div>
        <div class="fld">
          <label class="lbl">到</label>
          <select id="b-yto" style="width:88px"></select>
        </div>
        <div class="fld">
          <label class="lbl">线程</label>
          <select id="b-thr" style="width:74px">
            <option>2</option><option selected>4</option><option>6</option><option>8</option>
          </select>
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
      <div style="display:flex;align-items:center;gap:18px;margin-top:13px;flex-wrap:wrap;">
        <div style="display:flex;align-items:center;gap:8px;">
          <label class="lbl">下载间隔</label>
          <div class="srow" style="width:140px">
            <input type="range" id="b-delay" min="0.5" max="5" step="0.5" value="1"
                   oninput="document.getElementById('dval').textContent=this.value+'s'">
            <span class="sval" id="dval">1s</span>
          </div>
        </div>
        <label class="cbitem" id="merge-cb">
          <input type="checkbox" id="b-merge" onchange="syncCB(this)"> 同一文件夹
        </label>
        <div style="margin-left:auto;display:flex;gap:9px;">
          <button class="btn btn-s" id="pvbtn" onclick="doPreview()">👁 预览</button>
          <button class="btn btn-p" id="bdbtn" onclick="doBatchDL()">🚀 开始下载</button>
        </div>
      </div>
    </div>
    <div class="gs" style="flex:1;min-height:0;padding:15px 18px;display:flex;flex-direction:column;overflow:hidden;">
      <div class="bsec-t">预览</div>
      <div class="prev" id="prev">（点击「预览」查看将要下载的文件…）</div>
    </div>
  </div>

  <!-- ══ Download List Panel ══ -->
  <div class="panel" id="pnl-dllist">
    <div class="gs" style="flex:1;min-height:0;display:flex;flex-direction:column;overflow:hidden;">
      <!-- Summary bar -->
      <div class="dlsummary">
        <span style="color:var(--text);font-weight:600" id="dl-total">共 0 项</span>
        <span class="cnt-dl"  id="dl-cnt-dl">⬇ 0 下载中</span>
        <span class="cnt-ok"  id="dl-cnt-ok">✓ 0 完成</span>
        <span class="cnt-err" id="dl-cnt-err">✗ 0 失败</span>
        <span class="cnt-pnd" id="dl-cnt-pnd">⏳ 0 等待</span>
        <div style="margin-left:auto;display:flex;gap:8px;">
          <button class="btn btn-r btn-sm" id="retry-all-btn" onclick="retryAll()">↺ 重试失败</button>
          <button class="btn btn-s btn-sm" onclick="clearDLList()">清空</button>
        </div>
      </div>
      <!-- Column headers -->
      <div style="display:grid;grid-template-columns:26px 1fr 50px 90px 52px minmax(80px,1fr) 64px;
                  gap:8px;padding:7px 14px;background:rgba(255,255,255,.025);
                  border-bottom:1px solid rgba(255,255,255,.06);font-size:10px;
                  font-weight:600;color:var(--muted);text-transform:uppercase;
                  letter-spacing:.5px;flex-shrink:0;">
        <div></div><div>文件名</div><div>类型</div><div>分组</div>
        <div style="text-align:center">年份</div><div>状态</div><div></div>
      </div>
      <!-- List -->
      <div class="dlwrap" id="dllist">
        <div class="empty"><div class="empty-ico">📋</div><div>下载后在此查看进度</div></div>
      </div>
    </div>
  </div>

  <!-- Download bar -->
  <div class="dlbar g">
    <div class="dir-row">
      <label class="lbl">保存到</label>
      <div class="dir-disp" id="dir-disp"></div>
      <button class="btn btn-s btn-sm" onclick="browseDir()">浏览</button>
      <button class="btn btn-s btn-sm" onclick="openDir()">打开</button>
    </div>
    <div class="prog-sec">
      <div class="prog-wrap"><div class="prog-fill" id="prog"></div></div>
      <span class="stat" id="stat">就绪</span>
    </div>
    <button class="btn btn-g" id="dlbtn" onclick="doDownloadSel()">📥 下载选中</button>
  </div>

</div><!-- .app -->

<script>
// ── State ────────────────────────────────────────────
const S = {
  subjects:[], groups:[], selected:new Set(),
  bGroups:[], saveDir:'',
  poll:null, dlRendered:false,
};

// ── Init ─────────────────────────────────────────────
window.addEventListener('pywebviewready', async () => {
  const now = new Date().getFullYear();
  const yrs = Array.from({length:now-1999},(_,i)=>now-i);
  ['s-year','b-yfrom','b-yto'].forEach(id=>{
    const sel=document.getElementById(id);
    yrs.forEach(y=>sel.add(new Option(y,y)));
    sel.value = id==='b-yfrom' ? now-2 : now;
  });
  S.saveDir = await pywebview.api.get_default_dir();
  document.getElementById('dir-disp').textContent = S.saveDir;
  try {
    const r = JSON.parse(await pywebview.api.get_subjects());
    if (!r.ok) throw new Error(r.error);
    S.subjects = r.data;
    const opts = r.data.map(s=>`<option value="${s.value}">${s.value} — ${s.text}</option>`).join('');
    document.getElementById('s-subj').innerHTML = opts;
    document.getElementById('b-subj').innerHTML = opts;
    document.getElementById('hdr-st').textContent = `${r.data.length} 个科目`;
    setStat('就绪');
  } catch(e) {
    toast('加载科目失败：'+e.message,'err');
    document.getElementById('hdr-st').textContent='加载失败';
  }
});

// ── Tabs ─────────────────────────────────────────────
function switchTab(name) {
  const names=['search','batch','dllist'];
  document.querySelectorAll('.tab').forEach((b,i)=>b.classList.toggle('on',names[i]===name));
  names.forEach(n=>{
    document.getElementById('pnl-'+n).classList.toggle('on',n===name);
  });
}

// ── Search ────────────────────────────────────────────
async function doSearch() {
  const subj=document.getElementById('s-subj').value;
  const year=document.getElementById('s-year').value;
  const seas=document.getElementById('s-seas').value;
  if (!subj) return toast('请选择科目','err');
  setBusy('sbtn','<span class="spin"></span> 搜索中…',true);
  setStat('搜索中…');
  try {
    const r=JSON.parse(await pywebview.api.search(subj,year,seas));
    if (!r.ok) throw new Error(r.error);
    S.groups=r.groups;
    S.selected=new Set(r.groups.map((_,i)=>i));
    renderResults();
    setStat(`找到 ${r.count} 个文件`);
    document.getElementById('hdr-st').textContent=`${r.groups.length} 组试卷`;
  } catch(e){ toast('搜索失败：'+e.message,'err'); setStat('失败'); }
  finally{ setBusy('sbtn','🔍 搜索',false); }
}

function renderResults() {
  const el=document.getElementById('rlist');
  if (!S.groups.length){
    el.innerHTML='<div class="empty"><div class="empty-ico">📭</div><div>未找到试卷</div></div>';
    document.getElementById('rcnt').textContent='共 0 项'; return;
  }
  const byPG={};
  S.groups.forEach((g,i)=>{ const pg=g.paper_group||0; (byPG[pg]=byPG[pg]||[]).push([i,g]); });
  let html='';
  Object.keys(byPG).sort((a,b)=>+a-+b).forEach(pg=>{
    const label=+pg>0?`Paper ${pg}`:'其他', items=byPG[pg];
    html+=`<div class="rgrp" data-pg="${pg}">
      <div class="rgrp-hdr" onclick="toggleGrp(${pg})">
        ▾ ${label} <span style="color:var(--muted);font-weight:400">(${items.length} 项)</span>
      </div>`;
    items.forEach(([i,g])=>{
      const sel=S.selected.has(i);
      const qp=g.files.qp?g.files.qp.replace('.pdf',''):null;
      const ms=g.files.ms?g.files.ms.replace('.pdf',''):null;
      const ok=(g.has_qp&&g.has_ms)?'<span class="sok">✓</span>':'<span class="sbad">!</span>';
      html+=`<div class="rrow${sel?' sel':''}" data-i="${i}" onclick="toggleRow(this,${i})">
        <span class="chk">${sel?'☑':'☐'}</span>
        <span>${g.is_standalone?(g.label||'—'):('P'+g.number)}</span>
        <span class="fname ${qp?'fok':'fno'}">${qp||'—'}</span>
        <span class="fname ${ms?'fok':'fno'}">${ms||'—'}</span>
        ${ok}
      </div>`;
    });
    html+='</div>';
  });
  el.innerHTML=html; updateCount();
}

function toggleRow(el,i){
  S.selected.has(i)?S.selected.delete(i):S.selected.add(i);
  el.classList.toggle('sel',S.selected.has(i));
  el.querySelector('.chk').textContent=S.selected.has(i)?'☑':'☐';
  updateCount();
}
function toggleGrp(pg){
  const rows=[...document.querySelectorAll(`.rgrp[data-pg="${pg}"] .rrow`)];
  const anyOff=rows.some(r=>!r.classList.contains('sel'));
  rows.forEach(r=>{
    const i=+r.dataset.i; anyOff?S.selected.add(i):S.selected.delete(i);
    r.classList.toggle('sel',S.selected.has(i));
    r.querySelector('.chk').textContent=S.selected.has(i)?'☑':'☐';
  }); updateCount();
}
function selAll()  {S.selected=new Set(S.groups.map((_,i)=>i));applyAll(true); updateCount();}
function deselAll(){S.selected.clear();applyAll(false);updateCount();}
function selQP(){S.selected.clear();document.querySelectorAll('.rrow').forEach(r=>{const g=S.groups[+r.dataset.i];const on=g&&g.has_qp;on?S.selected.add(+r.dataset.i):0;r.classList.toggle('sel',!!on);r.querySelector('.chk').textContent=on?'☑':'☐';});updateCount();}
function selMS(){S.selected.clear();document.querySelectorAll('.rrow').forEach(r=>{const g=S.groups[+r.dataset.i];const on=g&&g.has_ms;on?S.selected.add(+r.dataset.i):0;r.classList.toggle('sel',!!on);r.querySelector('.chk').textContent=on?'☑':'☐';});updateCount();}
function applyAll(v){document.querySelectorAll('.rrow').forEach(r=>{r.classList.toggle('sel',v);r.querySelector('.chk').textContent=v?'☑':'☐';});}
function updateCount(){document.getElementById('rcnt').textContent=`共 ${S.groups.length} 项，已选 ${S.selected.size} 项`;}

// ── Batch Preview ─────────────────────────────────────
async function doPreview(){
  const code=document.getElementById('b-subj').value;
  const yFrom=+document.getElementById('b-yfrom').value;
  const yTo=+document.getElementById('b-yto').value;
  if(!code) return toast('请选择科目','err');
  if(yFrom>yTo) return toast('年份范围有误','err');
  const seasons=[...document.querySelectorAll('.cbgrp input:checked')]
    .filter(el=>'Mar Jun Nov'.includes(el.value)).map(el=>el.value);
  const pgs=[...document.querySelectorAll('.cbgrp input:checked')]
    .map(el=>+el.value).filter(v=>v>=1&&v<=6);
  if(!seasons.length) return toast('请至少选一个季度','err');
  ['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=true;});
  document.getElementById('pvbtn').innerHTML='<span class="spin"></span> 搜索中…';
  setStat('预览中…');
  try{
    const r=JSON.parse(await pywebview.api.batch_preview(
      JSON.stringify({code,year_from:yFrom,year_to:yTo,seasons,pgs})
    ));
    if(!r.ok) throw new Error(r.error);
    S.bGroups=r.groups; renderPreview(r.groups);
    setStat(`预览完成：${r.groups.length} 项`);
  }catch(e){toast('预览失败：'+e.message,'err');setStat('失败');}
  finally{
    ['pvbtn','bdbtn'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=false;});
    document.getElementById('pvbtn').innerHTML='👁 预览';
  }
}

function renderPreview(groups){
  if(!groups.length){document.getElementById('prev').textContent='（无结果）';return;}
  const byY={};
  groups.forEach(g=>{
    const sy=g.sy||'';let y=sy.length>1?sy.slice(1):'?';
    if(/^\d{2}$/.test(y))y='20'+y;(byY[y]=byY[y]||[]).push(g);
  });
  const el=document.getElementById('prev');el.innerHTML='';
  Object.keys(byY).sort((a,b)=>+a-+b).forEach(y=>{
    const d=document.createElement('div');
    d.innerHTML=`<span class="py">── ${y} 年 (${byY[y].length} 项) ──</span>\n`;
    byY[y].forEach(g=>{
      const ln=document.createElement('div');ln.className='pf';
      ln.textContent=g.is_standalone?'  '+Object.keys(g.files)[0]
        :`  ${(g.files.qp||'-').replace('.pdf','')}  ＋  ${(g.files.ms||'-').replace('.pdf','')}`;
      d.appendChild(ln);
    });
    d.appendChild(document.createTextNode('\n'));el.appendChild(d);
  });
}

// ── Downloads ─────────────────────────────────────────
async function doBatchDL(){
  if(!S.bGroups.length) return toast('请先点击「预览」','err');
  if(!S.saveDir) return toast('请选择保存目录','err');
  startDL(S.bGroups,{
    merge:document.getElementById('b-merge').checked,
    delay:+document.getElementById('b-delay').value,
    threads:+document.getElementById('b-thr').value,
  });
}
async function doDownloadSel(){
  if(!S.selected.size) return toast('请先选择试卷','err');
  if(!S.saveDir) return toast('请选择保存目录','err');
  startDL([...S.selected].sort((a,b)=>a-b).map(i=>S.groups[i]),{merge:false,delay:1,threads:4});
}
async function startDL(groups,options){
  S.dlRendered=false;
  setAllDis(true);setProgress(0);setStat('准备下载…');
  try{
    const r=JSON.parse(await pywebview.api.start_download(
      JSON.stringify(groups),S.saveDir,JSON.stringify(options)
    ));
    if(!r.ok) throw new Error(r.error);
    switchTab('dllist');   // 自动切到下载列表
    startPoll();
  }catch(e){toast('启动失败：'+e.message,'err');setAllDis(false);}
}

// ── Poll ──────────────────────────────────────────────
function startPoll(){
  if(S.poll) clearInterval(S.poll);
  S.poll=setInterval(doPoll,700);
}
async function doPoll(){
  try{
    const [stJson,listJson]=await Promise.all([
      pywebview.api.get_status(),
      pywebview.api.get_download_list(),
    ]);
    const st=JSON.parse(stJson);
    const items=JSON.parse(listJson);
    setStat(st.message);
    if(st.total>0) setProgress(st.done/st.total*100);
    updateDLList(items);
    updateTabBadge(items);
    if(st.phase==='done'){
      clearInterval(S.poll);setProgress(100);setAllDis(false);
      const fail=items.filter(i=>i.status==='failed').length;
      if(!fail) toast(`下载完成！共 ${st.success} 个文件`,'ok');
      else toast(`完成 ${st.success} 个，失败 ${fail} 个`,'inf');
      // 高亮重试按钮
      if(fail>0){
        const rb=document.getElementById('retry-all-btn');
        if(rb){rb.style.animation='pulse 1s ease 3';}
      }
    }
  }catch(e){clearInterval(S.poll);setAllDis(false);}
}

// ── Download list rendering ────────────────────────────
const DL_ICON={pending:'⏳',downloading:'⬇️',done:'✅',failed:'❌'};
const DL_STAT_TXT={pending:'等待中',downloading:'下载中...',done:'完成',};
function dlStatClass(s){return{pending:'s-pnd',downloading:'s-dl',done:'s-ok',failed:'s-err'}[s]||'s-pnd';}

function renderDLListFull(items){
  const el=document.getElementById('dllist');
  if(!items.length){
    el.innerHTML='<div class="empty"><div class="empty-ico">📋</div><div>下载后在此查看进度</div></div>';
    return;
  }
  el.innerHTML=items.map(it=>`
    <div class="dlrow ${it.status}" data-id="${it.id}" data-status="${it.status}" data-err="${it.error}">
      <span class="ico">${DL_ICON[it.status]||'⏳'}</span>
      <span class="dl-fname${it.status==='done'?' dim':''}" title="${it.filename}">${it.filename}</span>
      <span class="type-${it.ftype}">${it.ftype}</span>
      <span class="dl-label" title="${it.label}">${it.label}</span>
      <span class="dl-year">${it.year}</span>
      <span class="dl-stat ${dlStatClass(it.status)}">${it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'')}</span>
      <span class="dl-act">${it.status==='failed'?`<button class="btn btn-r btn-sm" onclick="retryItem(${it.id})">重试</button>`:'&nbsp;'}</span>
    </div>`).join('');
  S.dlRendered=true;
}

function updateDLList(items){
  if(!S.dlRendered||!document.querySelector('.dlrow')){
    renderDLListFull(items);return;
  }
  let anyChange=false;
  items.forEach(it=>{
    const row=document.querySelector(`.dlrow[data-id="${it.id}"]`);
    if(!row) return;
    if(row.dataset.status===it.status && row.dataset.err===it.error) return;
    anyChange=true;
    row.dataset.status=it.status; row.dataset.err=it.error;
    row.className=`dlrow ${it.status}`;
    row.querySelector('.ico').textContent=DL_ICON[it.status]||'⏳';
    row.querySelector('.dl-fname').className=`dl-fname${it.status==='done'?' dim':''}`;
    const statEl=row.querySelector('.dl-stat');
    statEl.className=`dl-stat ${dlStatClass(it.status)}`;
    statEl.textContent=it.status==='failed'?it.error:(DL_STAT_TXT[it.status]||'');
    const actEl=row.querySelector('.dl-act');
    actEl.innerHTML=it.status==='failed'
      ?`<button class="btn btn-r btn-sm" onclick="retryItem(${it.id})">重试</button>`
      :'&nbsp;';
    // auto-scroll to first downloading item
    if(it.status==='downloading') row.scrollIntoView({block:'nearest',behavior:'smooth'});
  });
  if(anyChange) updateDLSummary(items);
}

function updateDLSummary(items){
  const dl  =items.filter(i=>i.status==='downloading').length;
  const ok  =items.filter(i=>i.status==='done').length;
  const fail=items.filter(i=>i.status==='failed').length;
  const pend=items.filter(i=>i.status==='pending').length;
  document.getElementById('dl-total').textContent=`共 ${items.length} 个文件`;
  document.getElementById('dl-cnt-dl').textContent=`⬇ ${dl} 下载中`;
  document.getElementById('dl-cnt-ok').textContent=`✓ ${ok} 完成`;
  document.getElementById('dl-cnt-err').textContent=`✗ ${fail} 失败`;
  document.getElementById('dl-cnt-pnd').textContent=`⏳ ${pend} 等待`;
  document.getElementById('dl-cnt-err').style.opacity=fail>0?'1':'0.4';
}

function updateTabBadge(items){
  const fail=items.filter(i=>i.status==='failed').length;
  const btn=document.getElementById('tab-dl');
  btn.textContent=fail>0?`📋 下载列表 (${fail}失败)`:'📋 下载列表';
}

// ── Retry ─────────────────────────────────────────────
async function retryAll(){
  const r=JSON.parse(await pywebview.api.retry_failed());
  if(!r.ok){toast(r.error,'err');return;}
  if(r.count===0){toast('没有失败的项目','inf');return;}
  S.dlRendered=false;
  toast(`重试 ${r.count} 个失败项`,'inf');
  startPoll();
}
async function retryItem(id){
  const r=JSON.parse(await pywebview.api.retry_item(id));
  if(!r.ok){toast(r.error,'err');return;}
  startPoll();
}
async function clearDLList(){
  const r=JSON.parse(await pywebview.api.clear_download_list());
  if(!r.ok){toast(r.error,'err');return;}
  S.dlRendered=false;
  renderDLListFull([]);
  updateDLSummary([]);
  document.getElementById('tab-dl').textContent='📋 下载列表';
  setProgress(0);setStat('就绪');
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
function setAllDis(dis){
  ['sbtn','pvbtn','bdbtn','dlbtn'].forEach(id=>{
    const b=document.getElementById(id);if(b)b.disabled=dis;
  });
}
function setBusy(id,html,dis){const b=document.getElementById(id);if(!b)return;b.innerHTML=html;b.disabled=dis;}
function syncCB(el){el.closest('.cbitem').classList.toggle('on',el.checked);}
function toast(msg,type='inf'){
  const el=document.createElement('div');el.className=`toast ${type}`;
  const ico={ok:'✅',err:'❌',inf:'ℹ️'}[type]||'';
  el.innerHTML=`<span>${ico}</span><span>${msg}</span>`;
  document.getElementById('toasts').appendChild(el);
  setTimeout(()=>el.style.opacity='0',3500);
  setTimeout(()=>el.remove(),3800);
}
</script>
</body>
</html>
"""


# ── Entry ─────────────────────────────────────────────

if __name__ == "__main__":
    api = API()
    window = webview.create_window(
        "CIE 试卷下载器",
        html=HTML,
        js_api=api,
        width=1120, height=840,
        min_size=(900, 700),
        background_color="#090915",
    )
    api.window = window
    webview.start(debug=False)
