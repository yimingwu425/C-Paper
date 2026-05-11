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


# ── 美观的主题样式 ───────────────────────────────────

class ModernTheme:
    """现代化主题样式"""

    # 颜色主题
    COLORS = {
        'primary': '#2196F3',      # 主色调 - 蓝色
        'primary_dark': '#1976D2',
        'secondary': '#4CAF50',    # 辅助色 - 绿色
        'accent': '#FF9800',       # 强调色 - 橙色
        'background': '#F5F5F5',   # 背景色
        'surface': '#FFFFFF',     # 表面色
        'text_primary': '#212121',  # 主文本
        'text_secondary': '#757575', # 次文本
        'border': '#E0E0E0',      # 边框色
        'error': '#F44336',        # 错误色
        'success': '#4CAF50',      # 成功色
    }

    # 字体设置
    FONTS = {
        'title': ('Helvetica Neue', 12, 'bold'),
        'subtitle': ('Helvetica Neue', 11, 'bold'),
        'body': ('Helvetica Neue', 10),
        'small': ('Helvetica Neue', 9),
    }

    @classmethod
    def configure_styles(cls):
        """配置主题样式"""
        style = ttk.Style()

        try:
            # 尝试使用系统主题
            if os.name == 'nt':  # Windows
                style.theme_use('vista')
            elif os.name == 'posix':  # macOS/Linux
                style.theme_use('clam')
        except:
            style.theme_use('default')

        # 配置Treeview样式
        style.configure('Modern.Treeview',
                       font=cls.FONTS['body'],
                       background='#FFFFFF',
                       foreground='#000000',
                       fieldbackground='#FFFFFF',
                       rowheight=28,
                       borderwidth=1,
                       focuscolor='none')

        style.map('Modern.Treeview',
                 background=[('selected', cls.COLORS['primary'])])

        # 配置Treeview头部
        style.configure('Modern.Treeview.Heading',
                       font=cls.FONTS['subtitle'],
                       background='#F0F0F0',
                       foreground='#333333',
                       relief='flat',
                       padding=(8, 4))

        style.map('Modern.Treeview.Heading',
                 background=[('active', '#E3F2FD')])

        # 配置按钮样式
        style.configure('Modern.TButton',
                       font=cls.FONTS['body'],
                       background=cls.COLORS['primary'],
                       foreground='white',
                       borderwidth=0,
                       focuscolor='none',
                       padding=(12, 8))

        style.map('Modern.TButton',
                 background=[('active', cls.COLORS['primary_dark']),
                           ('pressed', cls.COLORS['primary_dark'])])

        # 配置次要按钮
        style.configure('Modern.TSecondaryButton',
                       font=cls.FONTS['body'],
                       background='#F0F0F0',
                       foreground='#333333',
                       borderwidth=1,
                       relief='solid',
                       focuscolor='none',
                       padding=(12, 8))

        style.map('Modern.TSecondaryButton',
                 background=[('active', '#E0E0E0')])

        # 配置进度条
        style.configure('Horizontal.TProgressbar',
                       background=cls.COLORS['primary'],
                       troughcolor='#E0E0E0',
                       borderwidth=0,
                       lightcolor=cls.COLORS['primary'],
                       darkcolor=cls.COLORS['primary'])

        # 配置Notebook
        style.configure('Modern.TNotebook',
                       background=cls.COLORS['background'],
                       tabposition='n')

        style.configure('Modern.TNotebook.Tab',
                       background='#E0E0E0',
                       foreground='#666666',
                       padding=[16, 8],
                       font=cls.FONTS['body'],
                       borderwidth=1)

        style.map('Modern.TNotebook.Tab',
                 background=[('selected', '#FFFFFF'),
                           ('active', '#F0F0F0')],
                 foreground=[('selected', cls.COLORS['primary'])])

        # 配置Frame和LabelFrame
        style.configure('Modern.TFrame',
                       background=cls.COLORS['background'])

        style.configure('Modern.TLabelframe',
                       background=cls.COLORS['surface'],
                       foreground=cls.COLORS['text_primary'],
                       borderwidth=1,
                       relief='solid')

        style.configure('Modern.TLabelframe.Label',
                       background=cls.COLORS['surface'],
                       foreground=cls.COLORS['text_primary'],
                       font=cls.FONTS['subtitle'])

        # 配置标签
        style.configure('Modern.TLabel',
                       font=cls.FONTS['body'],
                       foreground=cls.COLORS['text_primary'],
                       background=cls.COLORS['surface'])

        # 配置复选框
        style.configure('Modern.TCheckbutton',
                       font=cls.FONTS['body'],
                       background=cls.COLORS['surface'],
                       foreground=cls.COLORS['text_primary'])

        # 配置输入框
        style.configure('Modern.TCombobox',
                       font=cls.FONTS['body'],
                       fieldbackground='#FFFFFF',
                       background=cls.COLORS['surface'],
                       foreground=cls.COLORS['text_primary'])


# ── 美观的GUI ───────────────────────────────────────

class App:
    def __init__(self, root):
        self.root = root
        self.root.title("CIE 试卷下载器")
        self.root.geometry("1000x800")
        self.root.minsize(900, 700)

        # 配置主题
        ModernTheme.configure_styles()
        self._setup_window()

        # 初始化变量
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
        self.b_preview_btn = None
        self.batch_btn = None
        self.b_year_from_cb = None
        self.b_year_to_cb = None
        self.b_threads_var = tk.StringVar(value="4")

        # 延迟初始化UI
        self.root.after(100, self._init_ui)

    def _setup_window(self):
        """设置窗口样式"""
        # 设置窗口图标（如果需要）
        self.root.configure(bg='#F5F5F5')

        # 设置窗口属性
        if os.name == 'nt':  # Windows
            self.root.state('zoomed')  # 最大化窗口

    def _init_ui(self):
        """初始化UI"""
        self._create_main_layout()
        self._load_subjects()
        self._start_background_threads()
        self.root.protocol("WM_DELETE_WINDOW", self._on_closing)

    def _create_main_layout(self):
        """创建主布局"""
        # 主容器
        main_container = ttk.Frame(self.root, style='Modern.TFrame')
        main_container.pack(fill=tk.BOTH, expand=True, padx=16, pady=16)

        # 顶部标题区域
        header = ttk.Frame(main_container, style='Modern.TFrame')
        header.pack(fill=tk.X, pady=(0, 16))

        title_label = ttk.Label(header, text="CIE 试卷下载器",
                               font=('Helvetica Neue', 20, 'bold'),
                               style='Modern.TLabel')
        title_label.pack(side=tk.LEFT)

        # 版本信息
        version_label = ttk.Label(header, text="v2.0",
                                font=('Helvetica Neue', 10),
                                style='Modern.TLabel')
        version_label.pack(side=tk.RIGHT)

        # 创建主要的Notebook
        self.nb = ttk.Notebook(main_container, style='Modern.TNotebook')
        self.nb.pack(fill=tk.BOTH, expand=True)

        # 创建标签页
        self._create_search_tab()
        self._create_batch_tab()

        # 底部下载栏
        self._create_download_bar()

    def _create_search_tab(self):
        """创建搜索标签页"""
        search_frame = ttk.Frame(self.nb, style='Modern.TFrame')
        self.nb.add(search_frame, text='🔍 按次搜索')

        # 搜索区域
        search_container = ttk.LabelFrame(search_frame,
                                        text='搜索设置',
                                        padding=20,
                                        style='Modern.TLabelframe')
        search_container.pack(fill=tk.X, padx=16, pady=(16, 8))

        # 使用网格布局
        grid_frame = ttk.Frame(search_container, style='Modern.TFrame')
        grid_frame.pack(fill=tk.X)

        # 科目选择
        ttk.Label(grid_frame, text='科目:', style='Modern.TLabel').grid(
            row=0, column=0, sticky=tk.W, padx=(0, 12), pady=8)
        self.s_subject_var = tk.StringVar()
        self.s_subject_cb = ttk.Combobox(grid_frame, textvariable=self.s_subject_var,
                                       width=40, state='readonly')
        self.s_subject_cb.grid(row=0, column=1, sticky=tk.W, padx=(0, 20), pady=8)

        # 年份选择
        ttk.Label(grid_frame, text='年份:', style='Modern.TLabel').grid(
            row=0, column=2, sticky=tk.W, padx=(0, 12), pady=8)
        self.s_year_var = tk.StringVar(value=str(datetime.datetime.now().year))
        self.s_year_cb = ttk.Combobox(grid_frame, textvariable=self.s_year_var,
                                    width=10, state='readonly')
        self.s_year_cb['values'] = [str(y) for y in range(datetime.datetime.now().year, 2000, -1)]
        self.s_year_cb.grid(row=0, column=3, sticky=tk.W, padx=(0, 20), pady=8)

        # 季度选择
        ttk.Label(grid_frame, text='季度:', style='Modern.TLabel').grid(
            row=0, column=4, sticky=tk.W, padx=(0, 12), pady=8)
        self.s_season_var = tk.StringVar()
        self.s_season_cb = ttk.Combobox(grid_frame, textvariable=self.s_season_var,
                                      width=15, state='readonly')
        self.s_season_cb['values'] = [f"{c} - {n}" for c, n in SEASONS]
        self.s_season_cb.current(2)
        self.s_season_cb.grid(row=0, column=5, sticky=tk.W, pady=8)

        # 搜索按钮
        self.search_btn = ttk.Button(search_frame,
                                   text='🔍 开始搜索',
                                   command=self._queue_search,
                                   style='Modern.TButton')
        self.search_btn.pack(pady=(0, 16))

        # 结果区域
        results_container = ttk.LabelFrame(search_frame,
                                         text='搜索结果',
                                         padding=16,
                                         style='Modern.TLabelframe')
        results_container.pack(fill=tk.BOTH, expand=True, padx=16, pady=(0, 16))

        # 工具栏
        toolbar = ttk.Frame(results_container, style='Modern.TFrame')
        toolbar.pack(fill=tk.X, pady=(0, 12))

        # 按钮组
        button_group = ttk.Frame(toolbar, style='Modern.TFrame')
        button_group.pack(side=tk.LEFT)

        ttk.Button(button_group, text='全选', command=self._sel_all,
                  style='Modern.TSecondaryButton', width=10).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(button_group, text='全不选', command=self._desel_all,
                  style='Modern.TSecondaryButton', width=10).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(button_group, text='仅选QP', command=self._sel_qp,
                  style='Modern.TSecondaryButton', width=10).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(button_group, text='仅选MS', command=self._sel_ms,
                  style='Modern.TSecondaryButton', width=10).pack(side=tk.LEFT, padx=(0, 8))

        # 计数标签
        self.count_var = tk.StringVar(value='共 0 项')
        ttk.Label(toolbar, textvariable=self.count_var,
                font=('Helvetica Neue', 10, 'bold'),
                style='Modern.TLabel').pack(side=tk.RIGHT, padx=16)

        # Treeview容器
        tree_container = ttk.Frame(results_container, style='Modern.TFrame')
        tree_container.pack(fill=tk.BOTH, expand=True)

        # 滚动条
        vsb = ttk.Scrollbar(tree_container, orient='vertical')
        vsb.pack(side=tk.RIGHT, fill=tk.Y)

        hsb = ttk.Scrollbar(tree_container, orient='horizontal')
        hsb.pack(side=tk.BOTTOM, fill=tk.X)

        # Treeview
        cols = ('sel', 'paper', 'qp', 'ms', 'status')
        self.tree = ttk.Treeview(tree_container, columns=cols, show='tree headings',
                              selectmode='none', style='Modern.Treeview',
                              height=20)
        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

        self.tree.heading('#0', text='分类')
        self.tree.heading('sel', text='✓')
        self.tree.heading('paper', text='编号')
        self.tree.heading('qp', text='试卷')
        self.tree.heading('ms', text='答案')
        self.tree.heading('status', text='状态')

        self.tree.column('#0', width=120, stretch=False)
        self.tree.column('sel', width=40, stretch=False)
        self.tree.column('paper', width=60, stretch=False)
        self.tree.column('qp', width=130, stretch=False)
        self.tree.column('ms', width=130, stretch=False)
        self.tree.column('status', width=70, stretch=False)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vsb.config(command=self.tree.yview)
        hsb.config(command=self.tree.xview)

        self.tree.bind('<ButtonRelease-1>', self._on_tree_click)

    def _create_batch_tab(self):
        """创建批量下载标签页"""
        batch_frame = ttk.Frame(self.nb, style='Modern.TFrame')
        self.nb.add(batch_frame, text='📦 批量下载')

        # 设置容器
        settings_container = ttk.LabelFrame(batch_frame,
                                          text='批量下载设置',
                                          padding=20,
                                          style='Modern.TLabelframe')
        settings_container.pack(fill=tk.X, padx=16, pady=(16, 8))

        # 创建设置网格
        settings_grid = ttk.Frame(settings_container, style='Modern.TFrame')
        settings_grid.pack(fill=tk.X)

        # 基础设置行
        ttk.Label(settings_grid, text='科目:', style='Modern.TLabel').grid(
            row=0, column=0, sticky=tk.W, padx=(0, 12), pady=8)
        self.b_subject_var = tk.StringVar()
        self.b_subject_cb = ttk.Combobox(settings_grid, textvariable=self.b_subject_var,
                                       width=40, state='readonly')
        self.b_subject_cb.grid(row=0, column=1, columnspan=2, sticky=tk.W, pady=8)

        # 文件夹选项
        folder_frame = ttk.Frame(settings_grid, style='Modern.TFrame')
        folder_frame.grid(row=0, column=3, sticky=tk.W, padx=(20, 0), pady=8)
        ttk.Checkbutton(folder_frame, text='同一文件夹', variable=self.merge_in_same_folder,
                       style='Modern.TCheckbutton').pack(side=tk.LEFT)

        # 年份范围
        ttk.Label(settings_grid, text='年份范围:', style='Modern.TLabel').grid(
            row=1, column=0, sticky=tk.W, padx=(0, 12), pady=8)
        self.b_year_from = tk.StringVar(value=str(datetime.datetime.now().year - 2))
        self.b_year_from_cb = ttk.Combobox(settings_grid, textvariable=self.b_year_from,
                                         width=8, state='readonly')
        self.b_year_from_cb['values'] = [str(y) for y in range(datetime.datetime.now().year, 2000, -1)]
        self.b_year_from_cb.grid(row=1, column=1, sticky=tk.W, padx=(0, 8), pady=8)

        ttk.Label(settings_grid, text='—', style='Modern.TLabel').grid(
            row=1, column=2, pady=8)

        self.b_year_to = tk.StringVar(value=str(datetime.datetime.now().year))
        self.b_year_to_cb = ttk.Combobox(settings_grid, textvariable=self.b_year_to,
                                       width=8, state='readonly')
        self.b_year_to_cb['values'] = [str(y) for y in range(datetime.datetime.now().year, 2000, -1)]
        self.b_year_to_cb.grid(row=1, column=3, sticky=tk.W, padx=(8, 0), pady=8)

        # 性能设置行
        ttk.Label(settings_grid, text='线程数:', style='Modern.TLabel').grid(
            row=2, column=0, sticky=tk.W, padx=(0, 12), pady=8)
        self.b_threads_cb = ttk.Combobox(settings_grid, textvariable=self.b_threads_var,
                                       width=8, state='readonly',
                                       values=["2", "4", "6", "8"])
        self.b_threads_cb.grid(row=2, column=1, sticky=tk.W, pady=8)

        ttk.Label(settings_grid, text='下载间隔(秒):', style='Modern.TLabel').grid(
            row=2, column=2, sticky=tk.W, padx=(20, 12), pady=8)
        delay_frame = ttk.Frame(settings_grid, style='Modern.TFrame')
        delay_frame.grid(row=2, column=3, sticky=tk.W, pady=8)
        ttk.Scale(delay_frame, from_=0.5, to=5.0, variable=self.download_delay,
                 orient=tk.HORIZONTAL, length=100).pack(side=tk.LEFT)
        ttk.Label(delay_frame, textvariable=self.download_delay, width=4).pack(side=tk.LEFT, padx=4)
        ttk.Label(delay_frame, text='秒').pack(side=tk.LEFT)

        # 季度和试卷类型设置
        options_frame = ttk.Frame(settings_container, style='Modern.TFrame')
        options_frame.pack(fill=tk.X, pady=(12, 0))

        # 季度选择
        season_frame = ttk.LabelFrame(options_frame, text='季度选择',
                                    padding=12,
                                    style='Modern.TLabelframe')
        season_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 12))

        self.b_season_vars = {}
        season_container = ttk.Frame(season_frame, style='Modern.TFrame')
        season_container.pack()
        for code, name in SEASONS:
            var = tk.BooleanVar(value=True)
            self.b_season_vars[code] = var
            cb = ttk.Checkbutton(season_container, text=f'{code}({name})',
                               variable=var, style='Modern.TCheckbutton')
            cb.pack(side=tk.LEFT, padx=8)

        # 试卷类型选择
        paper_frame = ttk.LabelFrame(options_frame, text='试卷类型',
                                   padding=12,
                                   style='Modern.TLabelframe')
        paper_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.b_paper_vars = {}
        paper_container = ttk.Frame(paper_frame, style='Modern.TFrame')
        paper_container.pack()
        for i in range(1, 7):
            var = tk.BooleanVar(value=True)
            self.b_paper_vars[i] = var
            cb = ttk.Checkbutton(paper_container, text=f'Paper {i}',
                               variable=var, style='Modern.TCheckbutton')
            cb.pack(side=tk.LEFT, padx=8)

        # 按钮区域
        button_container = ttk.Frame(batch_frame, style='Modern.TFrame')
        button_container.pack(fill=tk.X, padx=16, pady=(8, 16))

        button_group = ttk.Frame(button_container, style='Modern.TFrame')
        button_group.pack()

        self.b_preview_btn = ttk.Button(button_group, text='👁️ 预览',
                                     command=self._queue_batch_preview,
                                     style='Modern.TSecondaryButton', width=12)
        self.b_preview_btn.pack(side=tk.LEFT, padx=(0, 12))

        self.batch_btn = ttk.Button(button_group, text='🚀 开始下载',
                                  command=self._queue_batch_download,
                                  style='Modern.TButton', width=12)
        self.batch_btn.pack(side=tk.LEFT)

        # 预览区域
        preview_container = ttk.LabelFrame(batch_frame,
                                          text='预览',
                                          padding=16,
                                          style='Modern.TLabelframe')
        preview_container.pack(fill=tk.BOTH, expand=True, padx=16, pady=(0, 16))

        # 预览文本框
        preview_frame = ttk.Frame(preview_container, style='Modern.TFrame')
        preview_frame.pack(fill=tk.BOTH, expand=True)

        # 滚动条
        vsb = ttk.Scrollbar(preview_frame, orient='vertical')
        vsb.pack(side=tk.RIGHT, fill=tk.Y)

        hsb = ttk.Scrollbar(preview_frame, orient='horizontal')
        hsb.pack(side=tk.BOTTOM, fill=tk.X)

        # 文本框
        self.batch_text = tk.Text(preview_frame,
                                 wrap=tk.NONE,
                                 font=('Consolas', 10),
                                 bg='#FAFAFA',
                                 fg='#333333',
                                 relief=tk.FLAT,
                                 padx=8,
                                 pady=8)
        self.batch_text.pack(fill=tk.BOTH, expand=True)
        self.batch_text.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        vsb.config(command=self.batch_text.yview)
        hsb.config(command=self.batch_text.xview)
        self.batch_text.configure(state='disabled')

    def _create_download_bar(self):
        """创建底部下载栏"""
        download_bar = ttk.Frame(self.root, style='Modern.TFrame')
        download_bar.pack(fill=tk.X, side=tk.BOTTOM)

        # 分隔线
        ttk.Separator(download_bar, orient=tk.HORIZONTAL).pack(fill=tk.X, pady=(8, 0))

        # 内容容器
        content = ttk.Frame(download_bar, style='Modern.TFrame')
        content.pack(fill=tk.X, padx=16, pady=8)

        # 保存目录
        dir_container = ttk.Frame(content, style='Modern.TFrame')
        dir_container.pack(side=tk.LEFT, fill=tk.X, expand=True)

        ttk.Label(dir_container, text='保存到:', style='Modern.TLabel').pack(side=tk.LEFT, padx=(0, 8))
        self.dir_var = tk.StringVar(value=self.save_dir)
        dir_entry = ttk.Entry(dir_container, textvariable=self.dir_var,
                            font=('Helvetica Neue', 10))
        dir_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        ttk.Button(dir_container, text='浏览...',
                  command=self._browse,
                  style='Modern.TSecondaryButton').pack(side=tk.LEFT)

        # 进度和状态
        progress_container = ttk.Frame(content, style='Modern.TFrame')
        progress_container.pack(side=tk.RIGHT, padx=(32, 0))

        self.progress = ttk.Progressbar(progress_container,
                                      mode='determinate',
                                      length=200,
                                      style='Horizontal.TProgressbar')
        self.progress.pack(side=tk.LEFT, padx=(0, 16))

        self.status_var = tk.StringVar(value='就绪')
        status_label = ttk.Label(progress_container,
                               textvariable=self.status_var,
                               font=('Helvetica Neue', 10),
                               style='Modern.TLabel')
        status_label.pack(side=tk.LEFT)

        # 下载按钮
        self.dl_btn = ttk.Button(content,
                                text='📥 下载选中',
                                command=self._queue_download_selected,
                                style='Modern.TButton')
        self.dl_btn.pack(side=tk.RIGHT, padx=(16, 0))

    # ═══════════════════════════════════════════════════
    #  Background Task Processing
    # ═══════════════════════════════════════════════════

    def _start_background_threads(self):
        """启动后台处理线程"""
        threading.Thread(target=self._process_search_queue, daemon=True).start()
        threading.Thread(target=self._process_download_queue, daemon=True).start()

    def _queue_search(self):
        """排队搜索任务"""
        self.search_btn.configure(state='disabled')
        self.search_btn.configure(text='搜索中...')
        self.search_queue.put(('search', {
            'code': self.s_subject_var.get().split(" - ")[0],
            'year': self.s_year_var.get(),
            'season': self.s_season_var.get().split(" - ")[0]
        }))

    def _queue_batch_preview(self):
        """排队批量预览任务"""
        if not self.b_preview_btn or not self.batch_btn:
            return
        for btn in [self.b_preview_btn, self.batch_btn]:
            btn.configure(state='disabled')
        self.batch_btn.configure(text='预览中...')
        self.download_queue.put(('batch_preview', {
            'code': self.b_subject_var.get().split(" - ")[0],
            'year_from': self.b_year_from.get(),
            'year_to': self.b_year_to.get(),
            'seasons': [c for c, _ in SEASONS if self.b_season_vars[c].get()],
            'pgs': [i for i in range(1, 7) if self.b_paper_vars[i].get()]
        }))

    def _queue_batch_download(self):
        """排队批量下载任务"""
        if not self._batch_groups:
            messagebox.showwarning('提示', '请先点击「预览」')
            return
        if not self.batch_btn:
            return
        self.batch_btn.configure(state='disabled')
        self.batch_btn.configure(text='下载中...')
        self.download_queue.put(('batch_download', {
            'groups': self._batch_groups,
            'save_dir': self.dir_var.get(),
            'threads': int(self.b_threads_var.get())
        }))

    def _queue_download_selected(self):
        """排队下载选中任务"""
        if not self.selected:
            messagebox.showwarning('提示', '请先选择要下载的试卷')
            return
        self.dl_btn.configure(state='disabled')
        self.dl_btn.configure(text='下载中...')
        groups = [self.paper_groups[i] for i in sorted(self.selected)]
        self.download_queue.put(('download_selected', {
            'groups': groups,
            'save_dir': self.dir_var.get()
        }))

    def _process_search_queue(self):
        """处理搜索队列"""
        while True:
            task = self.search_queue.get()
            if task[0] == 'search':
                self._do_search(task[1])
            self.search_queue.task_done()

    def _process_download_queue(self):
        """处理下载队列"""
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
        """加载科目列表"""
        threading.Thread(target=self._fetch_subjects, daemon=True).start()

    def _fetch_subjects(self):
        """获取科目列表"""
        try:
            self.status_var.set('加载科目列表...')
            data = fetch_subjects()
            self.root.after(0, self._subjects_ready, data)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror('错误', f'无法加载科目: {e}'))
            self.root.after(0, lambda: self.status_var.set('加载失败'))

    def _subjects_ready(self, data):
        """科目加载完成"""
        self.subjects_raw = data
        vals = [f'{s["value"]} - {s["text"]}' for s in data]
        for cb in (self.s_subject_cb, self.b_subject_cb):
            cb['values'] = vals
            if vals:
                cb.current(0)
        self.status_var.set('就绪')

    # ═══════════════════════════════════════════════════
    #  Tab 1: 按次搜索
    # ═══════════════════════════════════════════════════

    def _do_search(self, params):
        """执行搜索"""
        try:
            self.root.after(0, lambda: self.status_var.set('搜索中...'))
            res = search_papers(params['code'], params['year'], params['season'])
            self.root.after(0, lambda: self._search_done(res))
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror('错误', f'搜索失败: {e}'))
            self.root.after(0, self._reset_btn)

    def _search_done(self, result):
        """搜索完成"""
        rows = result.get('rows', [])
        if not rows:
            messagebox.showinfo('结果', '未找到试卷')
            self._reset_btn()
            self.status_var.set('无结果')
            return

        self.paper_groups = group_papers(rows)
        self.selected = set()
        self.tree.delete(*self.tree.get_children())

        # 构建分类
        categories = {}
        for i, g in enumerate(self.paper_groups):
            pg = g.get('paper_group', 0)
            categories.setdefault(pg, []).append(i)

        # 批量插入数据
        for pg in sorted(categories.keys()):
            indices = categories[pg]
            label = f'Paper {pg}' if pg > 0 else '其他'
            cat_id = self.tree.insert('', tk.END,
                                    text=f'{label}  ({len(indices)} 项)',
                                    values=('', '', '', '', ''),
                                    tags=('cat',), open=True)
            for i in indices:
                g = self.paper_groups[i]
                if g['is_standalone']:
                    self.tree.insert(cat_id, tk.END, iid=str(i),
                                   text='',
                                   values=('☐', g['label'],
                                          list(g['files'].keys())[0], '-', ''),
                                   tags=('standalone',))
                else:
                    qp = g['files'].get('qp', '-')
                    ms = g['files'].get('ms', '-')
                    status = '✓' if g['has_qp'] and g['has_ms'] else '✗'
                    if g['has_qp']:
                        qp = qp.replace('.pdf', '')
                    if g['has_ms']:
                        ms = ms.replace('.pdf', '')
                    tags = []
                    if g['has_qp']:
                        tags.append('available')
                    else:
                        tags.append('missing')
                    if g['has_ms']:
                        tags.append('available')
                    else:
                        tags.append('missing')
                    self.tree.insert(cat_id, tk.END, iid=str(i),
                                   text='',
                                   values=('☐', g['number'], qp, ms, status),
                                   tags=' '.join(tags))

        self._sel_all()
        self.count_var.set(f'共 {len(self.paper_groups)} 项')
        self._reset_btn()
        self.status_var.set(f'找到 {len(rows)} 个文件')

    # ── Selection Methods ──

    def _on_tree_click(self, event):
        """处理树点击事件"""
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
                    self.tree.set(c, 'sel', '☐')
                else:
                    self.selected.add(idx)
                    self.tree.set(c, 'sel', '☑')
        else:
            try:
                idx = int(item)
            except ValueError:
                return
            if idx in self.selected:
                self.selected.discard(idx)
                self.tree.set(item, 'sel', '☐')
            else:
                self.selected.add(idx)
                self.tree.set(item, 'sel', '☑')

    def _sel_all(self):
        """全选"""
        self.selected = set(range(len(self.paper_groups)))
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                self.tree.set(child, 'sel', '☑')

    def _desel_all(self):
        """全不选"""
        self.selected = set()
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                self.tree.set(child, 'sel', '☐')

    def _sel_qp(self):
        """仅选QP"""
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                idx = int(child)
                if self.paper_groups[idx]['has_qp']:
                    self.selected.add(idx)
                    self.tree.set(child, 'sel', '☑')
                else:
                    self.tree.set(child, 'sel', '☐')

    def _sel_ms(self):
        """仅选MS"""
        for cat in self.tree.get_children():
            for child in self.tree.get_children(cat):
                idx = int(child)
                if self.paper_groups[idx]['has_ms']:
                    self.selected.add(idx)
                    self.tree.set(child, 'sel', '☑')
                else:
                    self.tree.set(child, 'sel', '☐')

    # ═══════════════════════════════════════════════════
    #  Tab 2: 批量下载
    # ═══════════════════════════════════════════════════

    def _do_batch_preview(self, params):
        """批量预览"""
        try:
            self.root.after(0, lambda: self.status_var.set('预览中...'))

            all_groups = []
            queries = [(y, s) for y in range(int(params['year_from']), int(params['year_to']) + 1)
                      for s in params['seasons']]

            # 并行搜索
            with ThreadPoolExecutor(max_workers=3) as executor:
                futures = []
                for y, s in queries:
                    future = executor.submit(search_papers, params['code'], y, s)
                    futures.append((y, s, future))

                for y, s, future in futures:
                    self.root.after(0, lambda y=y, s=s: self.status_var.set(f'搜索 {y} {s}...'))
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
            self.root.after(0, lambda: messagebox.showerror('错误', f'预览失败: {e}'))
            self.root.after(0, self._reset_batch_btns)

    def _batch_preview_done(self, groups):
        """预览完成"""
        self._batch_groups = groups
        self._reset_batch_btns()

        self.batch_text.configure(state='normal')
        self.batch_text.delete('1.0', tk.END)

        # 按年份分组
        by_year = {}
        for g in groups:
            sy = g.get('sy', '')
            year = sy[1:] if len(sy) > 1 and sy[0] in ['m', 's', 'w'] else 'unknown'
            if year.isdigit() and len(year) == 2:
                year = '20' + year
            by_year.setdefault(year, []).append(g)

        for year in sorted(by_year.keys(), key=lambda x: int(x) if x.isdigit() else 0):
            items = by_year[year]
            self.batch_text.insert(tk.END, f'── {year} 年 ({len(items)} 项) ──\n')
            by_pg = {}
            for g in items:
                pg = g.get('paper_group', 0)
                by_pg.setdefault(pg, []).append(g)
            for pg in sorted(by_pg.keys()):
                pg_items = by_pg[pg]
                for g in pg_items:
                    if g['is_standalone']:
                        self.batch_text.insert(tk.END, f'  {list(g["files"].keys())[0]}\n')
                    else:
                        qp = g['files'].get('qp', '-')
                        ms = g['files'].get('ms', '-')
                        self.batch_text.insert(tk.END, f'  {qp.replace(".pdf", "")} + {ms.replace(".pdf", "")}\n')
            self.batch_text.insert(tk.END, '\n')

        self.batch_text.configure(state='disabled')
        self.status_var.set(f'预览完成: {len(groups)} 项')

    def _do_batch_download(self, params):
        """批量下载"""
        save_dir = params['save_dir']
        os.makedirs(save_dir, exist_ok=True)
        max_workers = params['threads']

        self._start_download(params['groups'], save_dir, max_workers)

    def _do_download_selected(self, params):
        """下载选中项"""
        save_dir = params['save_dir']
        os.makedirs(save_dir, exist_ok=True)
        self._start_download(params['groups'], save_dir, 4)

    # ═══════════════════════════════════════════════════
    #  Download Engine
    # ═══════════════════════════════════════════════════

    def _start_download(self, groups, save_dir, max_workers):
        self.cancelled = False
        total = len(groups)
        if total == 0:
            self.root.after(0, lambda: self.status_var.set('没有可下载的试卷'))
            self.root.after(0, self._reset_dl_btn)
            return

        self.root.after(0, lambda: self._set_buttons(False))
        self.root.after(0, lambda: self.progress.configure(value=0))
        self.root.after(0, lambda: self.status_var.set('准备下载...'))

        folders = {}
        if self.merge_in_same_folder.get():
            os.makedirs(save_dir, exist_ok=True)
            folders['root'] = save_dir
        else:
            for g in groups:
                sy = g.get('sy', 'unknown')
                year = sy[1:] if len(sy) > 1 and sy[0] in 'msw' else 'unknown'
                if year.isdigit() and len(year) == 2:
                    year = '20' + year
                if year not in folders:
                    folders[year] = {
                        'qp': os.path.join(save_dir, year, 'QP'),
                        'ms': os.path.join(save_dir, year, 'MS'),
                    }
                    os.makedirs(folders[year]['qp'], exist_ok=True)
                    os.makedirs(folders[year]['ms'], exist_ok=True)

        delay = self.download_delay.get()
        lock = threading.Lock()
        counts = {'done': 0, 'success': 0}

        def worker(group):
            if self.cancelled:
                return False
            try:
                sy = group.get('sy', 'unknown')
                year = sy[1:] if len(sy) > 1 and sy[0] in 'msw' else 'unknown'
                if year.isdigit() and len(year) == 2:
                    year = '20' + year

                if self.merge_in_same_folder.get():
                    folder_qp = folder_ms = folders['root']
                else:
                    folder_qp = folders.get(year, {}).get('qp', save_dir)
                    folder_ms = folders.get(year, {}).get('ms', save_dir)

                qp = group['files'].get('qp')
                ms = group['files'].get('ms')
                if qp:
                    safe_download(qp, os.path.join(folder_qp, qp), delay)
                if ms:
                    safe_download(ms, os.path.join(folder_ms, ms), delay)
                return True
            except Exception:
                return False

        def on_done(future):
            with lock:
                counts['done'] += 1
                try:
                    if future.result():
                        counts['success'] += 1
                except Exception:
                    pass
                done = counts['done']
                success = counts['success']
            self.root.after(0, lambda: self.progress.configure(value=done / total * 100))
            self.root.after(0, lambda: self.status_var.set(f'下载中... ({done}/{total})'))
            if done >= total:
                self.root.after(0, lambda: self._dl_finished(success, total))

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            for g in groups:
                if self.cancelled:
                    break
                executor.submit(worker, g).add_done_callback(on_done)

    def _dl_finished(self, success, total):
        self._set_buttons(True)
        self.progress.configure(value=100)
        if success == total:
            self.status_var.set('下载完成!')
            messagebox.showinfo('完成', f'已下载 {success} 组试卷\n保存到: {self.dir_var.get()}')
        else:
            self.status_var.set(f'完成 ({success}/{total} 成功)')
            messagebox.showwarning('部分失败', f'成功 {success}/{total}\n保存到: {self.dir_var.get()}')

    # ═══════════════════════════════════════════════════
    #  Helper Methods
    # ═══════════════════════════════════════════════════

    def _reset_dl_btn(self):
        self.dl_btn.configure(state='normal', text='📥 下载选中')

    def _browse(self):
        """浏览目录"""
        d = filedialog.askdirectory(initialdir=self.dir_var.get())
        if d:
            self.dir_var.set(d)

    def _reset_btn(self):
        """重置搜索按钮"""
        self.search_btn.configure(state='normal')
        self.search_btn.configure(text='🔍 开始搜索')

    def _reset_batch_btns(self):
        """重置批量下载按钮"""
        if self.b_preview_btn and self.batch_btn:
            for btn in [self.b_preview_btn, self.batch_btn]:
                btn.configure(state='normal')
            self.batch_btn.configure(text='🚀 开始下载')

    def _set_buttons(self, enabled):
        """设置按钮状态"""
        state = 'normal' if enabled else 'disabled'
        for btn in [self.dl_btn, self.search_btn, self.batch_btn]:
            if btn:
                btn.configure(state=state)
                if btn == self.search_btn:
                    btn.configure(text='🔍 开始搜索' if enabled else '搜索中...')
                elif btn == self.batch_btn:
                    btn.configure(text='🚀 开始下载' if enabled else '下载中...')
                elif btn == self.dl_btn:
                    btn.configure(text='📥 下载选中' if enabled else '下载中...')

    def _on_closing(self):
        """窗口关闭"""
        self.cancelled = True
        self.root.destroy()


if __name__ == '__main__':
    root = tk.Tk()
    app = App(root)
    root.mainloop()