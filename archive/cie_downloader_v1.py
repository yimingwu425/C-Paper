#!/usr/bin/env python3
"""CIE 试卷下载器 - Frank的CIE工坊客户端
搜索、批量下载试卷（QP和MS可选分别存放）"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import urllib.request
import urllib.parse
import json
import os
import re
import threading
import time
import datetime
from queue import Queue
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE_URL = "https://cie.fraft.cn"
SEASONS = [("Mar", "春季"), ("Jun", "夏季"), ("Nov", "冬季")]
CACHE_DIR = os.path.expanduser("~/.cie_cache")


# ── 缓存机制 ─────────────────────────────────────────

def get_cache_key(subject, year, season):
    return f"{subject}_{year}_{season}"

def load_from_cache(cache_key):
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.json")
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            pass
    return None

def save_to_cache(cache_key, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        cache_file = os.path.join(CACHE_DIR, f"{cache_key}.json")
        with open(cache_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
    except:
        pass


# ── API ──────────────────────────────────────────────

def fetch_subjects():
    req = urllib.request.Request(
        f"{BASE_URL}/obj/Common/Subject/combo",
        method="POST", headers={"Content-Length": "0"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode())


def search_papers(subject, year, season):
    cache_key = get_cache_key(subject, year, season)
    cached = load_from_cache(cache_key)
    if cached:
        return cached

    data = urllib.parse.urlencode({
        "subject": str(subject), "year": str(year), "season": season,
    }).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/obj/Common/Fetch/renum", data=data, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read().decode())
        save_to_cache(cache_key, result)
        return result


def download_file(filename, save_path):
    url = f"{BASE_URL}/obj/Common/Fetch/redir/{filename}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=30) as response, open(save_path, 'wb') as out_file:
        out_file.write(response.read())


# ─── Download helpers with delay ──────────────────────

def safe_download(filename, save_path, delay=1.0, max_retries=3):
    """带延迟和重试机制的下载"""
    for attempt in range(max_retries):
        try:
            if delay > 0 and attempt > 0:
                time.sleep(delay)
            download_file(filename, save_path)
            return True
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            time.sleep(2.0 * (attempt + 1))  # 递增延迟


# ── Parsing & Grouping ──────────────────────────────

def parse_filename(filename):
    m = re.match(r'(\d+)_([mws]\d{2})_(qp|ms|ci|gt|er|ir|in|sr)(?:_(\d+))?\.pdf', filename)
    if not m:
        return None
    return dict(subject=m.group(1), sy=m.group(2), type=m.group(3),
                number=m.group(4) or '', filename=filename)


def get_paper_group(number):
    if not number:
        return 0
    n = int(number)
    return n // 10 if n >= 10 else n


def group_papers(rows):
    pairs, standalone = {}, []
    for row in rows:
        fname = row['file']
        parsed = parse_filename(fname)
        if not parsed or parsed['type'] not in ('qp', 'ms'):
            standalone.append(dict(label=fname.replace('.pdf', ''),
                                   files={fname: fname}, has_qp=False, has_ms=False,
                                   is_standalone=True, paper_group=0))
            continue
        key = (parsed['subject'], parsed['sy'], parsed['number'])
        if key not in pairs:
            pairs[key] = dict(subject=parsed['subject'], sy=parsed['sy'],
                              number=parsed['number'], files={},
                              has_qp=False, has_ms=False, is_standalone=False,
                              paper_group=get_paper_group(parsed['number']))
        pairs[key]['files'][parsed['type']] = fname
        if parsed['type'] == 'qp':
            pairs[key]['has_qp'] = True
        else:
            pairs[key]['has_ms'] = True

    result = []
    for g in pairs.values():
        result.append(g)
    result.extend(standalone)

    def sk(g):
        pg = g.get('paper_group', 0)
        try:
            return (pg, int(g.get('number', '999')))
        except ValueError:
            return (pg, 999)
    result.sort(key=sk)
    return result


# ── GUI ─────────────────────────────────────────────

class App:
    def __init__(self, root):
        self.root = root
        root.title("CIE 试卷下载器")
        root.geometry("980x760")
        root.minsize(800, 580)

        # 优化UI响应
        self.root.after_idle(self._init_ui)

    def _init_ui(self):
        self.subjects_raw = []
        self.paper_groups = []
        self.selected = set()
        self.save_dir = os.path.expanduser("~/Downloads/CIE_Papers")
        self.cancelled = False
        self._batch_groups = []
        self.merge_in_same_folder = tk.BooleanVar(value=False)
        self.download_delay = tk.DoubleVar(value=1.0)
        self.search_queue = Queue()
        self.download_queue = Queue()

        self._build_ui()
        self._load_subjects()
        self._start_background_threads()

    def _start_background_threads(self):
        # 启动后台处理线程
        threading.Thread(target=self._process_search_queue, daemon=True).start()
        threading.Thread(target=self._process_download_queue, daemon=True).start()

    # ═══════════════════════════════════════════════════
    #  UI Construction
    # ═══════════════════════════════════════════════════

    def _build_ui(self):
        main = ttk.Frame(self.root, padding=10)
        main.pack(fill=tk.BOTH, expand=True)

        self.nb = ttk.Notebook(main)
        self.nb.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        tab1 = ttk.Frame(self.nb, padding=5)
        self.nb.add(tab1, text="  按次搜索  ")
        self._build_search_tab(tab1)

        tab2 = ttk.Frame(self.nb, padding=5)
        self.nb.add(tab2, text="  批量下载  ")
        self._build_batch_tab(tab2)

        self._build_download_bar(main)

        # 绑定窗口关闭事件
        self.root.protocol("WM_DELETE_WINDOW", self._on_closing)

    # ── Tab 1: 按次搜索 ──

    def _build_search_tab(self, parent):
        sf = ttk.LabelFrame(parent, text="搜索", padding=8)
        sf.pack(fill=tk.X, pady=(0, 6))

        # 使用grid布局更精确控制
        ttk.Label(sf, text="科目:").grid(row=0, column=0, padx=(0, 4), sticky=tk.W)
        self.s_subject_var = tk.StringVar()
        self.s_subject_cb = ttk.Combobox(sf, textvariable=self.s_subject_var,
                                         width=35, state="readonly")
        self.s_subject_cb.grid(row=0, column=1, padx=(0, 12), sticky=tk.W)

        ttk.Label(sf, text="年份:").grid(row=0, column=2, padx=(0, 4), sticky=tk.W)
        self.s_year_var = tk.StringVar(value=str(datetime.datetime.now().year))
        self.s_year_cb = ttk.Combobox(sf, textvariable=self.s_year_var,
                                      width=8, state="readonly")
        self.s_year_cb['values'] = [str(y) for y in range(datetime.datetime.now().year, 2000, -1)]
        self.s_year_cb.grid(row=0, column=3, padx=(0, 12), sticky=tk.W)

        ttk.Label(sf, text="季度:").grid(row=0, column=4, padx=(0, 4), sticky=tk.W)
        self.s_season_var = tk.StringVar()
        self.s_season_cb = ttk.Combobox(sf, textvariable=self.s_season_var,
                                        width=16, state="readonly")
        self.s_season_cb['values'] = [f"{c} - {n}" for c, n in SEASONS]
        self.s_season_cb.current(2)
        self.s_season_cb.grid(row=0, column=5, padx=(0, 12), sticky=tk.W)

        self.search_btn = ttk.Button(sf, text="搜 索", command=self._queue_search)
        self.search_btn.grid(row=0, column=6, padx=8)

        # Results tree
        rf = ttk.LabelFrame(parent, text="结果", padding=5)
        rf.pack(fill=tk.BOTH, expand=True)

        toolbar = ttk.Frame(rf)
        toolbar.pack(fill=tk.X, pady=(0, 4))

        ttk.Button(toolbar, text="全选", command=self._sel_all, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="全不选", command=self._desel_all, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="全选QP", command=self._sel_qp, width=8).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="全选MS", command=self._sel_ms, width=8).pack(side=tk.LEFT, padx=2)

        self.count_var = tk.StringVar(value="共 0 项")
        ttk.Label(toolbar, textvariable=self.count_var).pack(side=tk.RIGHT, padx=8)

        # 使用PanedWindow允许调整大小
        paned = ttk.PanedWindow(rf, orient=tk.HORIZONTAL)
        paned.pack(fill=tk.BOTH, expand=True)

        cols = ("sel", "paper", "qp", "ms", "status")
        self.tree = ttk.Treeview(paned, columns=cols, show="tree headings",
                                 selectmode="none", height=15)
        self.tree.heading("#0", text="分类")
        self.tree.heading("sel", text="✓")
        self.tree.heading("paper", text="编号")
        self.tree.heading("qp", text="试卷")
        self.tree.heading("ms", text="答案")
        self.tree.heading("status", text="状态")
        self.tree.column("#0", width=120, minwidth=100)
        self.tree.column("sel", width=35, anchor=tk.CENTER, stretch=False)
        self.tree.column("paper", width=50, anchor=tk.CENTER)
        self.tree.column("qp", width=110, anchor=tk.CENTER)
        self.tree.column("ms", width=110, anchor=tk.CENTER)
        self.tree.column("status", width=60, anchor=tk.CENTER)

        self.tree.tag_configure("cat", font=("", 10, "bold"))
        self.tree.tag_configure("available", foreground="#1565C0")
        self.tree.tag_configure("missing", foreground="#888")
        self.tree.tag_configure("standalone", foreground="#666")

        # 添加滚动条
        vsb = ttk.Scrollbar(self.tree, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        paned.add(self.tree)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)

        paned.add(ttk.Label(rf, text="拖动调整大小", width=20))  # 占位符

        self.tree.bind("<ButtonRelease-1>", self._on_tree_click)

    # ── Tab 2: 批量下载 ──

    def _build_batch_tab(self, parent):
        cf = ttk.LabelFrame(parent, text="批量下载设置", padding=10)
        cf.pack(fill=tk.X, pady=(0, 6))

        now = datetime.datetime.now().year
        years = [str(y) for y in range(now, 2000, -1)]

        # 使用notebook来组织设置
        nb = ttk.Notebook(cf)
        nb.pack(fill=tk.X, pady=5)

        # 基础设置页
        basic_frame = ttk.Frame(nb, padding=5)
        nb.add(basic_frame, text="基础设置")

        ttk.Label(basic_frame, text="科目:").grid(row=0, column=0, sticky=tk.W, padx=(0, 4))
        self.b_subject_var = tk.StringVar()
        self.b_subject_cb = ttk.Combobox(basic_frame, textvariable=self.b_subject_var,
                                         width=35, state="readonly")
        self.b_subject_cb.grid(row=0, column=1, columnspan=3, sticky=tk.W, pady=2)

        folder_frame = ttk.Frame(basic_frame)
        folder_frame.grid(row=1, column=0, columnspan=4, pady=5)
        ttk.Label(folder_frame, text="文件夹:").pack(side=tk.LEFT, padx=(0, 8))
        ttk.Checkbutton(folder_frame, text="同一文件夹",
                        variable=self.merge_in_same_folder).pack(side=tk.LEFT, padx=4)

        # 高级设置页
        adv_frame = ttk.Frame(nb, padding=5)
        nb.add(adv_frame, text="高级设置")

        ttk.Label(adv_frame, text="年份:").grid(row=0, column=0, sticky=tk.W, padx=(0, 4))
        self.b_year_from = tk.StringVar(value=str(now - 2))
        ttk.Combobox(adv_frame, textvariable=self.b_year_from, width=6,
                     state="readonly", values=years).grid(row=0, column=1, sticky=tk.W, padx=(0, 2))
        ttk.Label(adv_frame, text="—").grid(row=0, column=2)
        self.b_year_to = tk.StringVar(value=str(now))
        ttk.Combobox(adv_frame, textvariable=self.b_year_to, width=6,
                     state="readonly", values=years).grid(row=0, column=3, sticky=tk.W, padx=(0, 12))

        ttk.Label(adv_frame, text="季度:").grid(row=1, column=0, sticky=tk.W, padx=(0, 4))
        self.b_season_vars = {}
        sf = ttk.Frame(adv_frame)
        sf.grid(row=1, column=1, columnspan=3, sticky=tk.W)
        for code, name in SEASONS:
            var = tk.BooleanVar(value=True)
            self.b_season_vars[code] = var
            ttk.Checkbutton(sf, text=f"{code}({name})", variable=var).pack(side=tk.LEFT, padx=4)

        ttk.Label(adv_frame, text="试卷:").grid(row=2, column=0, sticky=tk.W, padx=(0, 4), pady=4)
        self.b_paper_vars = {}
        pf = ttk.Frame(adv_frame)
        pf.grid(row=2, column=1, columnspan=3, sticky=tk.W)
        for i in range(1, 7):
            var = tk.BooleanVar(value=True)
            self.b_paper_vars[i] = var
            ttk.Checkbutton(pf, text=f"Paper {i}", variable=var).pack(side=tk.LEFT, padx=4)

        # 性能设置页
        perf_frame = ttk.Frame(nb, padding=5)
        nb.add(perf_frame, text="性能")

        ttk.Label(perf_frame, text="线程数:").grid(row=0, column=0, sticky=tk.W, padx=(0, 4))
        self.b_threads_var = tk.StringVar(value="4")
        ttk.Combobox(perf_frame, textvariable=self.b_threads_var, width=4,
                     state="readonly", values=["2", "4", "6", "8"]
                     ).grid(row=0, column=1, sticky=tk.W, padx=(0, 12))

        ttk.Label(perf_frame, text="下载间隔(秒):").grid(row=1, column=0, sticky=tk.W, padx=(0, 4))
        delay_frame = ttk.Frame(perf_frame)
        delay_frame.grid(row=1, column=1, sticky=tk.W, padx=(0, 8))
        ttk.Scale(delay_frame, from_=0.5, to=5.0, variable=self.download_delay,
                 orient=tk.HORIZONTAL, length=100).pack(side=tk.LEFT)
        ttk.Label(delay_frame, textvariable=self.download_delay, width=4).pack(side=tk.LEFT, padx=4)
        ttk.Label(delay_frame, text="秒").pack(side=tk.LEFT)

        # 按钮
        button_frame = ttk.Frame(cf)
        button_frame.pack(fill=tk.X, pady=10)
        self.b_preview_btn = ttk.Button(button_frame, text="预 览", command=self._queue_batch_preview)
        self.b_preview_btn.pack(side=tk.LEFT, padx=8)
        self.batch_btn = ttk.Button(button_frame, text="一键下载", command=self._queue_batch_download)
        self.batch_btn.pack(side=tk.LEFT)

        # 预览区域
        pf2 = ttk.LabelFrame(parent, text="预览", padding=5)
        pf2.pack(fill=tk.BOTH, expand=True)

        # 使用TextCtrl替代Text，性能更好
        self.batch_text = tk.Text(pf2, wrap=tk.NONE, state="disabled",
                                  font=("Menlo", 10), height=10)
        bxsb = ttk.Scrollbar(pf2, orient=tk.HORIZONTAL, command=self.batch_text.xview)
        bysb = ttk.Scrollbar(pf2, orient=tk.VERTICAL, command=self.batch_text.yview)
        self.batch_text.configure(xscrollcommand=bxsb.set, yscrollcommand=bysb.set)
        self.batch_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        bysb.pack(side=tk.RIGHT, fill=tk.Y)
        bxsb.pack(side=tk.BOTTOM, fill=tk.X)

    # ── Shared download bar ──

    def _build_download_bar(self, parent):
        df = ttk.LabelFrame(parent, text="下载", padding=8)
        df.pack(fill=tk.X)

        d1 = ttk.Frame(df)
        d1.pack(fill=tk.X, pady=(0, 6))
        ttk.Label(d1, text="保存到:").pack(side=tk.LEFT, padx=(0, 4))
        self.dir_var = tk.StringVar(value=self.save_dir)
        ttk.Entry(d1, textvariable=self.dir_var).pack(side=tk.LEFT, fill=tk.X,
                                                       expand=True, padx=(0, 4))
        ttk.Button(d1, text="浏览...", command=self._browse).pack(side=tk.LEFT)

        d2 = ttk.Frame(df)
        d2.pack(fill=tk.X)
        self.progress = ttk.Progressbar(d2, mode="determinate", length=400)
        self.progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        self.status_var = tk.StringVar(value="就绪")
        ttk.Label(d2, textvariable=self.status_var, width=32, anchor=tk.W).pack(
            side=tk.LEFT, padx=(0, 8))
        self.dl_btn = ttk.Button(d2, text="下载选中", command=self._queue_download_selected)
        self.dl_btn.pack(side=tk.LEFT)

    # ═══════════════════════════════════════════════════
    #  Background Task Processing
    # ═══════════════════════════════════════════════════

    def _queue_search(self):
        self.search_btn.configure(state="disabled")
        self.search_queue.put(('search', {
            'code': self.s_subject_var.get().split(" - ")[0],
            'year': self.s_year_var.get(),
            'season': self.s_season_var.get().split(" - ")[0]
        }))

    def _queue_batch_preview(self):
        self.b_preview_btn.configure(state="disabled")
        self.batch_btn.configure(state="disabled")
        self.download_queue.put(('batch_preview', {
            'code': self.b_subject_var.get().split(" - ")[0],
            'year_from': self.b_year_from.get(),
            'year_to': self.b_year_to.get(),
            'seasons': [c for c, _ in SEASONS if self.b_season_vars[c].get()],
            'pgs': [i for i in range(1, 7) if self.b_paper_vars[i].get()]
        }))

    def _queue_batch_download(self):
        if not self._batch_groups:
            messagebox.showwarning("提示", "请先点击「预览」")
            return
        self.batch_btn.configure(state="disabled")
        self.download_queue.put(('batch_download', {
            'groups': self._batch_groups,
            'save_dir': self.dir_var.get(),
            'threads': int(self.b_threads_var.get())
        }))

    def _queue_download_selected(self):
        if not self.selected:
            messagebox.showwarning("提示", "请先选择要下载的试卷")
            return
        self.dl_btn.configure(state="disabled")
        groups = [self.paper_groups[i] for i in sorted(self.selected)]
        self.download_queue.put(('download_selected', {
            'groups': groups,
            'save_dir': self.dir_var.get()
        }))

    def _process_search_queue(self):
        while True:
            task = self.search_queue.get()
            if task[0] == 'search':
                self._do_search(task[1])
            self.search_queue.task_done()

    def _process_download_queue(self):
        while True:
            task = self.download_queue.get()
            if task[0] == 'batch_preview':
                self._do_batch_preview(task[1])
            elif task[0] == 'batch_download':
                self._do_batch_download(task[1])
            elif task[0] == 'download_selected':
                self._do_download_selected(task[1])
            self.download_queue.task_done()

    # ═══════════════════════════════════════════════════
    #  Subject Loading
    # ═══════════════════════════════════════════════════

    def _load_subjects(self):
        threading.Thread(target=self._fetch_subjects, daemon=True).start()

    def _fetch_subjects(self):
        try:
            self.status_var.set("加载科目列表...")
            data = fetch_subjects()
            self.root.after(0, self._subjects_ready, data)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("错误", f"无法加载科目: {e}"))
            self.root.after(0, lambda: self.status_var.set("加载失败"))

    def _subjects_ready(self, data):
        self.subjects_raw = data
        vals = [f"{s['value']} - {s['text']}" for s in data]
        for cb in (self.s_subject_cb, self.b_subject_cb):
            cb['values'] = vals
            if vals:
                cb.current(0)
        self.status_var.set("就绪")

    # ═══════════════════════════════════════════════════
    #  Tab 1: 按次搜索
    # ═══════════════════════════════════════════════════

    def _do_search(self, params):
        try:
            self.root.after(0, lambda: self.status_var.set("搜索中..."))
            res = search_papers(params['code'], params['year'], params['season'])
            self.root.after(0, lambda: self._search_done(res))
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("错误", f"搜索失败: {e}"))
            self.root.after(0, self._reset_btn)

    def _search_done(self, result):
        rows = result.get('rows', [])
        if not rows:
            messagebox.showinfo("结果", "未找到试卷")
            self._reset_btn()
            self.status_var.set("无结果")
            return

        self.paper_groups = group_papers(rows)
        self.selected = set()
        self.tree.delete(*self.tree.get_children())

        # 使用批量更新提高性能
        updates = []
        categories = {}
        for i, g in enumerate(self.paper_groups):
            pg = g.get('paper_group', 0)
            categories.setdefault(pg, []).append(i)

        for pg in sorted(categories.keys()):
            indices = categories[pg]
            label = f"Paper {pg}" if pg > 0 else "其他"
            cat_id = self.tree.insert("", tk.END,
                                      text=f"{label}  ({len(indices)} 项)",
                                      values=("", "", "", "", ""),
                                      tags=("cat",), open=True)
            for i in indices:
                g = self.paper_groups[i]
                if g['is_standalone']:
                    updates.append((cat_id, str(i), "☐", g['label'],
                                   list(g['files'].keys())[0], "-", "", "standalone"))
                else:
                    qp = g['files'].get('qp', '-')
                    ms = g['files'].get('ms', '-')
                    status = "✓" if g['has_qp'] and g['has_ms'] else "✗"
                    if g['has_qp']:
                        qp = qp.replace('.pdf', '')
                    if g['has_ms']:
                        ms = ms.replace('.pdf', '')
                    tags = []
                    if g['has_qp']:
                        tags.append("available")
                    else:
                        tags.append("missing")
                    if g['has_ms']:
                        tags.append("available")
                    else:
                        tags.append("missing")
                    updates.append((cat_id, str(i), "☐", g['number'], qp, ms, status, " ".join(tags)))

        # 批量插入
        self.root.after(0, lambda: self._apply_tree_updates(updates))
        self._sel_all()
        self.count_var.set(f"共 {len(self.paper_groups)} 项")
        self._reset_btn()
        self.status_var.set(f"找到 {len(rows)} 个文件")

    def _apply_tree_updates(self, updates):
        for cat_id, item_id, sel, paper, qp, ms, status, tags in updates:
            self.tree.insert(cat_id, tk.END, iid=item_id,
                             text="", values=(sel, paper, qp, ms, status),
                             tags=tags.split())

    # ── Selection ──

    def _on_tree_click(self, event):
        item = self.tree.identify_row(event.y)
        if not item:
            return
        children = self.tree.get_children(item)
        if children:
            all_sel = all(int(c) in self.selected for c in children)
            for c in children:
                idx = int(c)
                if all_sel:
                    self.selected.discard(idx)
                    self.tree.set(c, "sel", "☐")
                else:
                    self.selected.add(idx)
                    self.tree.set(c, "sel", "☑")
        else:
            try:
                idx = int(item)
            except ValueError:
                return
            if idx in self.selected:
                self.selected.discard(idx)
                self.tree.set(item, "sel", "☐")
            else:
                self.selected.add(idx)
                self.tree.set(item, "sel", "☑")

    def _sel_all(self):
        self.selected = set(range(len(self.paper_groups)))
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                self.tree.set(child, "sel", "☑")

    def _desel_all(self):
        self.selected = set()
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                self.tree.set(child, "sel", "☐")

    def _sel_qp(self):
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                idx = int(child)
                if self.paper_groups[idx]['has_qp']:
                    self.selected.add(idx)
                    self.tree.set(child, "sel", "☑")
                else:
                    self.tree.set(child, "sel", "☐")

    def _sel_ms(self):
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                idx = int(child)
                if self.paper_groups[idx]['has_ms']:
                    self.selected.add(idx)
                    self.tree.set(child, "sel", "☑")
                else:
                    self.tree.set(child, "sel", "☐")

    # ═══════════════════════════════════════════════════
    #  Tab 2: 批量下载
    # ═══════════════════════════════════════════════════

    def _do_batch_preview(self, params):
        try:
            self.root.after(0, lambda: self.status_var.set("预览中..."))

            all_groups = []
            queries = [(y, s) for y in range(int(params['year_from']), int(params['year_to']) + 1)
                      for s in params['seasons']]

            # 并行搜索多个年份/季度
            with ThreadPoolExecutor(max_workers=3) as executor:
                futures = []
                for y, s in queries:
                    future = executor.submit(search_papers, params['code'], y, s)
                    futures.append((y, s, future))

                for y, s, future in futures:
                    self.root.after(0, lambda y=y, s=s: self.status_var.set(f"搜索 {y} {s}..."))
                    try:
                        res = future.result(timeout=30)
                        rows = res.get('rows', [])
                        groups = group_papers(rows)
                        filtered = [g for g in groups if g.get('paper_group', 0) in params['pgs']]
                        all_groups.extend(filtered)
                    except Exception:
                        pass

            self.root.after(0, lambda: self._batch_preview_done(all_groups))
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("错误", f"预览失败: {e}"))
            self.root.after(0, lambda: self._reset_batch_btns())

    def _batch_preview_done(self, groups):
        self._batch_groups = groups
        self.b_preview_btn.configure(state="normal")
        self.batch_btn.configure(state="normal")

        self.batch_text.configure(state="normal")
        self.batch_text.delete("1.0", tk.END)

        # Group by year
        by_year = {}
        for g in groups:
            sy = g.get('sy', '')
            year = sy[1:] if len(sy) > 1 and sy[0] in ['m', 's', 'w'] else 'unknown'
            if year.isdigit() and len(year) == 2:
                year = "20" + year
            by_year.setdefault(year, []).append(g)

        for year in sorted(by_year.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            items = by_year[year]
            self.batch_text.insert(tk.END, f"── {year} 年 ({len(items)} 项) ──\n")
            by_pg = {}
            for g in items:
                pg = g.get('paper_group', 0)
                by_pg.setdefault(pg, []).append(g)
            for pg in sorted(by_pg.keys()):
                pg_items = by_pg[pg]
                for g in pg_items:
                    if g['is_standalone']:
                        self.batch_text.insert(tk.END, f"  {list(g['files'].keys())[0]}\n")
                    else:
                        qp = g['files'].get('qp', '-')
                        ms = g['files'].get('ms', '-')
                        self.batch_text.insert(tk.END, f"  {qp.replace('.pdf', '')} + {ms.replace('.pdf', '')}\n")
            self.batch_text.insert(tk.END, "\n")

        self.batch_text.configure(state="disabled")
        self.status_var.set(f"预览完成: {len(groups)} 项")

    def _do_batch_download(self, params):
        save_dir = params['save_dir']
        os.makedirs(save_dir, exist_ok=True)
        max_workers = params['threads']

        self._start_download(params['groups'], save_dir, max_workers)

    def _do_download_selected(self, params):
        save_dir = params['save_dir']
        os.makedirs(save_dir, exist_ok=True)
        self._start_download(params['groups'], save_dir, 4)

    # ═══════════════════════════════════════════════════
    #  Download Engine (优化版)
    # ═══════════════════════════════════════════════════

    def _start_download(self, groups, save_dir, max_workers):
        self.cancelled = False
        total = len(groups)
        self._set_buttons(False)
        self.progress.configure(value=0)
        self.status_var.set(f"准备下载...")

        # 预先创建所有文件夹
        folders = {}
        if self.merge_in_same_folder.get():
            folders = {'root': save_dir}
        else:
            for g in groups:
                sy = g.get('sy', 'unknown')
                year = sy[1:] if len(sy) > 1 and sy[0] in ['m', 's', 'w'] else 'unknown'
                if year.isdigit() and len(year) == 2:
                    year = "20" + year
                if year not in folders:
                    year_dir = os.path.join(save_dir, year)
                    folders[year] = {
                        'qp': os.path.join(year_dir, 'QP') if not self.merge_in_same_folder.get() else None,
                        'ms': os.path.join(year_dir, 'MS') if not self.merge_in_same_folder.get() else None,
                        'root': year_dir if not self.merge_in_same_folder.get() else save_dir
                    }
                    if not self.merge_in_same_folder.get():
                        os.makedirs(folders[year]['qp'], exist_ok=True)
                        os.makedirs(folders[year]['ms'], exist_ok=True)

        # 使用线程池执行下载
        delay = self.download_delay.get()

        def worker(group):
            if self.cancelled:
                return False, group
            try:
                qp = group['files'].get('qp')
                ms = group['files'].get('ms')

                sy = group.get('sy', 'unknown')
                year = sy[1:] if len(sy) > 1 and sy[0] in ['m', 's', 'w'] else 'unknown'
                if year.isdigit() and len(year) == 2:
                    year = "20" + year
                folder = folders.get(year, folders['root'])

                if isinstance(folder, dict):
                    if qp:
                        qp_path = os.path.join(folder['qp'], qp)
                        safe_download(qp, qp_path, delay)
                    if ms:
                        ms_path = os.path.join(folder['ms'], ms)
                        safe_download(ms, ms_path, delay)
                else:
                    if qp:
                        qp_path = os.path.join(folder, qp)
                        safe_download(qp, qp_path, delay)
                    if ms:
                        ms_path = os.path.join(folder, ms)
                        safe_download(ms, ms_path, delay)
                return True, group
            except Exception as e:
                return False, e

        # 使用ThreadPoolExecutor，限制并发数
        completed = 0
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for g in groups:
                if self.cancelled:
                    break
                future = executor.submit(worker, g)
                future.add_done_callback(lambda f, c=completed: self._on_download_complete(f, c, total))
                futures.append(future)
                completed += 1

        # 等待所有任务完成
        for future in as_completed(futures):
            if self.cancelled:
                break

    def _on_download_complete(self, future, completed, total):
        try:
            success, result = future.result()
            self.root.after(0, lambda: self.progress.configure(value=completed / total * 100))
            self.root.after(0, lambda c=completed, t=total: self.status_var.set(
                f"下载中... ({c}/{t})"))

            if completed >= total:
                self.root.after(0, lambda: self._dl_finished(success, total))
        except Exception:
            pass

    def _dl_finished(self, success, total):
        self._set_buttons(True)
        self.progress.configure(value=100)
        if success == total:
            self.status_var.set("下载完成!")
            messagebox.showinfo("完成", f"已下载 {success} 组试卷\n保存到: {self.dir_var.get()}")
        else:
            self.status_var.set(f"完成 ({success}/{total} 成功)")
            messagebox.showwarning("部分失败", f"成功 {success}/{total}\n保存到: {self.dir_var.get()}")

    # ═══════════════════════════════════════════════════
    #  Helpers
    # ═══════════════════════════════════════════════════

    def _browse(self):
        d = filedialog.askdirectory(initialdir=self.dir_var.get())
        if d:
            self.dir_var.set(d)

    def _reset_btn(self):
        self.search_btn.configure(state="normal")

    def _reset_batch_btns(self):
        self.b_preview_btn.configure(state="normal")
        self.batch_btn.configure(state="normal")

    def _set_buttons(self, enabled):
        s = "normal" if enabled else "disabled"
        for w in (self.dl_btn, self.search_btn, self.batch_btn, self.b_preview_btn):
            w.configure(state=s)

    def _on_closing(self):
        self.cancelled = True
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()