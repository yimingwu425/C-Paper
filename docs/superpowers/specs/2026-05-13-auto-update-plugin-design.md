# C-Paper v5.2 功能设计文档

> 主题：自动更新检查 + 插件扩展系统
> 版本：v5.2
> 日期：2026-05-13（修订：2026-05-14）
> 状态：待审核

---

## 一、概述

### 1.1 背景

C-Paper v5.1 是一个基于 Python + pywebview 的跨平台桌面应用，用于搜索和下载 CIE 历年试卷。当前版本已具备搜索、批量下载、收藏管理、历史记录等核心功能。

### 1.2 目标

本次迭代新增两个独立功能模块：

1. **自动更新检查** —— 在应用启动时自动检测 GitHub 最新 Release，提示用户更新
2. **插件扩展系统** —— 允许用户通过 Python 脚本钩子或外部命令扩展应用行为

### 1.3 非目标

- 不实现应用内自动下载/安装更新包（跨平台安装逻辑复杂，超出范围）
- 不实现插件商店/在线安装（首期仅支持本地插件）
- 不修改现有核心下载/搜索逻辑（除非插件系统需要暴露 Hook 点）

---

## 二、自动更新检查

### 2.1 需求

| ID | 需求 | 优先级 |
|---|---|---|
| AU-01 | 应用启动时自动检查 GitHub Releases 最新版本 | P0 |
| AU-02 | 每天最多检查一次，避免频繁请求 | P0 |
| AU-03 | 发现新版本时，在 UI 上以非侵入式提示展示 | P0 |
| AU-04 | 提供"前往下载"按钮，通过 Python 端 `webbrowser.open()` 打开浏览器（pywebview 中 `window.open` 不可靠） | P0 |
| AU-05 | 提供"跳过此版本"选项，用户选择后不再提示该版本 | P1 |
| AU-06 | GitHub API 不可用时，fallback 到仓库 version.json | P1 |
| AU-07 | 用户可在设置中关闭自动检查 | P1 |

### 2.2 架构

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   UI (JS)       │────▶│  API (Python)    │────▶│  GitHub API     │
│  更新提示弹窗    │     │  check_update()  │     │  /releases/latest│
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │  ~/.cie_cache/   │
                        │  update_state.json│
                        └──────────────────┘
```

### 2.3 数据模型

**`update_state.json`**（存储在 `~/.cie_cache/`）：

```json
{
  "last_check": "2026-05-13T10:30:00",
  "skipped_version": "5.2.0",
  "check_enabled": true
}
```

**`version.json`**（仓库根目录，作为 GitHub API 的 fallback）：

```json
{
  "version": "5.2.0",
  "min_version": "5.0.0",
  "download_url": "https://github.com/Ja-son-WU/CIE-Downloader/releases/tag/v5.2.0",
  "release_notes": "- 新增插件系统\n- 新增自动更新检查",
  "force_update": false,
  "published_at": "2026-05-10T00:00:00Z"
}
```

### 2.4 API 接口

```python
class API:
    # 新增方法
    def check_update(self) -> str:
        """
        检查更新，返回 JSON:
        {
          "ok": true,
          "has_update": true,
          "current_version": "5.1.0",
          "latest_version": "5.2.0",
          "download_url": "...",
          "release_notes": "...",
          "force_update": false
        }
        """
        pass

    def skip_version(self, version: str) -> str:
        """标记跳过指定版本"""
        pass

    def set_update_check(self, enabled: bool) -> str:
        """开启/关闭自动检查"""
        pass

    def open_url(self, url: str) -> str:
        """
        通过 webbrowser.open() 在系统默认浏览器中打开 URL。
        （pywebview 中 window.open() 不可靠，统一走 Python 端）
        """
        pass
```

### 2.5 UI 设计

**更新提示 Toast**（非侵入式，显示在右上角）：

```
┌─────────────────────────────────────┐
│   C-Paper v5.2.0 已发布              │
│    新增插件系统、自动更新检查          │
│    [查看详情]  [跳过此版本]  [×]     │
└─────────────────────────────────────┘
```

**设置面板新增选项**：

```
[✓] 启动时检查更新
    上次检查：2026-05-13
```

### 2.6 版本比对逻辑

```python
def _parse_version(v: str) -> tuple:
    """解析 '5.2.0' 或 'v5.2.0' -> (5, 2, 0)"""
    return tuple(int(x) for x in v.lstrip("v").split(".")[:3])

def _version_gte(v1: str, v2: str) -> bool:
    """v1 >= v2"""
    return _parse_version(v1) >= _parse_version(v2)
```

### 2.7 错误处理

| 场景 | 行为 |
|---|---|
| GitHub API 429/503 | 静默失败，记录日志，下次启动再试 |
| 网络完全不可用 | 静默失败，不打扰用户 |
| version.json 解析失败 | 视为无更新 |
| 版本号格式异常 | 视为无更新 |

---

## 三、插件扩展系统

### 3.1 需求

| ID | 需求 | 优先级 |
|---|---|---|
| PL-01 | 支持 Python 脚本钩子插件 | P0 |
| PL-02 | 支持外部命令插件（任意语言） | P0 |
| PL-03 | 插件在特定生命周期事件触发（下载前/后、搜索后等） | P0 |
| PL-04 | 插件配置通过 JSON 文件声明 | P0 |
| PL-05 | 插件可在设置面板中启用/禁用 | P1 |
| PL-06 | 插件错误不影响主应用运行 | P0 |
| PL-07 | 提供插件开发文档和示例 | P1 |
| PL-08 | 下载失败 hook 在 worker 统一 return 处分发一次，避免在每个 except 块中重复 | P0 |

### 3.2 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        C-Paper 主应用                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Search    │  │  Download   │  │   Plugin Manager    │  │
│  │   Engine    │  │   Engine    │  │                     │  │
│  └──────┬──────┘  └──────┬──────┘  └─────────────────────┘  │
│         │                │                      │             │
│         ▼                ▼                      ▼             │
│  ┌─────────────────────────────────────────────────────┐     │
│  │              Plugin Hook Dispatcher                  │     │
│  │   on_search_result  │  on_download_start             │     │
│  │   on_download_complete│ on_download_failed            │     │
│  │   on_batch_start    │  on_batch_complete              │     │
│  └─────────────────────────────────────────────────────┘     │
│                      │              │                         │
│         ┌────────────┘              └────────────┐            │
│         ▼                                        ▼            │
│  ┌─────────────┐                        ┌─────────────┐      │
│  │ Python Hook │                        │ Ext Command │      │
│  │  .py 脚本   │                        │  任意可执行  │      │
│  └─────────────┘                        └─────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 插件目录结构

```
~/.cie_cache/
└── plugins/
    ├── example_py/
    │   ├── plugin.json          # 插件元数据
    │   └── main.py              # Python 钩子入口
    └── example_cmd/
        ├── plugin.json          # 插件元数据
        └── notify.sh            # 外部命令（macOS/Linux）
        # 或 notify.exe / notify.bat（Windows）
```

### 3.4 插件配置格式（`plugin.json`）

```json
{
  "name": "下载完成通知",
  "id": "com.example.notify",
  "version": "1.0.0",
  "author": "Example",
  "description": "下载完成后发送系统通知",
  "type": "python",
  "entry": "main.py",
  "hooks": ["on_download_complete"],
  "enabled": true,
  "config": {
    "show_file_name": true
  }
}
```

字段说明：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `name` | string | 是 | 插件显示名称 |
| `id` | string | 是 | 唯一标识，反向域名格式 |
| `version` | string | 是 | 插件版本 |
| `author` | string | 否 | 作者 |
| `description` | string | 否 | 描述 |
| `type` | string | 是 | `python` 或 `command` |
| `entry` | string | 是 | 入口文件（相对路径） |
| `hooks` | array | 是 | 订阅的事件列表 |
| `enabled` | boolean | 否 | 默认是否启用 |
| `config` | object | 否 | 插件自定义配置 |

### 3.5 Hook 事件定义

| 事件名 | 触发时机 | 传入数据 |
|---|---|---|
| `on_search_result` | 搜索完成后 | `{subject, year, season, groups[]}` |
| `on_download_start` | 单个文件开始下载前 | `{filename, save_path, ftype, label, year}` |
| `on_download_complete` | 单个文件下载成功 | `{filename, save_path, ftype, label, year}` |
| `on_download_failed` | 单个文件下载失败 | `{filename, ftype, label, year, error, error_type}` |
| `on_batch_start` | 批量下载任务开始 | `{total, groups[]}` |
| `on_batch_complete` | 批量下载任务全部结束（含所有重试） | `{total, success, failed, skipped, retry_rounds}` |

### 3.6 Python 钩子插件接口

**`main.py` 示例**：

```python
# 插件入口必须定义 Plugin 类
class Plugin:
    def __init__(self, config: dict):
        """初始化时传入 plugin.json 中的 config"""
        self.config = config

    def on_download_complete(self, data: dict) -> dict:
        """
        事件处理函数，返回 dict:
        - {"ok": true} 表示正常
        - {"ok": false, "error": "..."} 表示插件执行失败（记录日志但不阻断主流程）
        """
        filename = data.get("filename")
        print(f"下载完成: {filename}")
        return {"ok": True}
```

### 3.7 外部命令插件接口

**执行约定**：

```bash
# C-Paper 调用外部命令时，传入 JSON 数据作为 stdin
# 外部命令从 stdout 返回 JSON 结果
echo '{"event":"on_download_complete",...}' | ./notify.sh
```

**`notify.sh` 示例**：

```bash
#!/bin/bash
read -r payload
filename=$(echo "$payload" | python3 -c "import sys,json; print(json.load(sys.stdin).get('filename',''))")
osascript -e "display notification \"$filename\" with title \"C-Paper 下载完成\""
echo '{"ok":true}'
```

### 3.8 插件管理器（Python）

```python
class PluginManager:
    def __init__(self, plugins_dir: str):
        self._plugins_dir = plugins_dir
        self._plugins: dict[str, Plugin] = {}
        self._load_all()

    def _load_all(self):
        """扫描插件目录，加载所有合法插件。加载失败记录日志但不阻断启动"""
        pass

    def dispatch(self, hook_name: str, data: dict):
        """
        分发事件到所有订阅了该 hook 的插件。
        每个插件在独立线程中执行，超时 10 秒，错误不影响其他插件和主流程。
        """
        pass

    def list_plugins(self) -> list[dict]:
        """返回所有插件的元数据（用于 UI 展示）"""
        pass

    def enable_plugin(self, plugin_id: str, enabled: bool):
        """启用/禁用插件"""
        pass
```

### 3.9 API 接口

```python
class API:
    # 新增方法
    def get_plugins(self) -> str:
        """返回所有插件列表及状态"""
        pass

    def toggle_plugin(self, plugin_id: str, enabled: bool) -> str:
        """启用/禁用指定插件"""
        pass

    def get_plugin_config(self, plugin_id: str) -> str:
        """获取插件配置"""
        pass

    def set_plugin_config(self, plugin_id: str, config_json: str) -> str:
        """设置插件配置"""
        pass

    def open_plugins_dir(self) -> str:
        """在文件管理器中打开插件目录"""
        pass
```

### 3.10 UI 设计

**设置面板新增"插件"区域**：

```
┌─────────────────────────────────────┐
│  设置                                │
│  ─────────────────────────────────  │
│  [常规] [代理] [插件]                │
│                                     │
│  已安装插件 (2)                      │
│  ┌─────────────────────────────────┐│
│  │ ☑ 下载完成通知                   ││
│  │    v1.0.0 by Example             ││
│  │    下载完成后发送系统通知         ││
│  │    [配置]                        ││
│  └─────────────────────────────────┘│
│  ┌─────────────────────────────────┐│
│  │ ☐ 自动上传网盘                   ││
│  │    v0.5.0 by User                ││
│  │    下载完成后自动上传到 OneDrive ││
│  │    [配置]                        ││
│  └─────────────────────────────────┘│
│                                     │
│  插件目录: ~/.cie_cache/plugins/    │
│  [打开插件目录]                      │
└─────────────────────────────────────┘
```

### 3.11 安全与隔离

| 措施 | 说明 |
|---|---|
| 超时控制 | 每个插件执行超时 10 秒，超时自动终止 |
| 异常隔离 | 单个插件崩溃不影响其他插件和主应用 |
| 路径限制 | Python 插件只能访问 `plugins_dir` 内文件 |
| 无网络权限 | 插件默认不继承主应用的网络 session（如需需自行实现） |
| 禁用机制 | 用户可随时在设置中禁用任何插件 |

### 3.12 错误处理

| 场景 | 行为 |
|---|---|
| `plugin.json` 格式错误 | 跳过该插件，记录 WARNING 日志 |
| Python 插件入口类不存在 | 跳过，记录 ERROR 日志 |
| 插件执行抛出异常 | 捕获异常，记录日志，不影响主流程 |
| 外部命令返回非 0 | 视为执行失败，记录 stderr |
| 插件超时 | 强制终止（外部命令用 `subprocess.TimeoutExpired`） |

---

## 四、与现有系统的集成

### 4.1 修改点清单

| 文件 | 修改内容 |
|---|---|
| `src/backend/const.py` | 新增 `PLUGINS_DIR`、`UPDATE_STATE_PATH` 常量；更新 `VERSION` |
| `src/backend/updater.py` | **新增**：自动更新检查逻辑 |
| `src/backend/plugin_manager.py` | **新增**：插件管理器核心实现 |
| `src/backend/api.py` | 新增 `check_update`、`skip_version`、`set_update_check`、`open_url`、`get_plugins`、`toggle_plugin`、`get_plugin_config`、`set_plugin_config`、`open_plugins_dir` 方法；初始化 PluginManager；在下载/搜索流程中插入 hook 调用 |
| `src/backend/parser.py` | `search()` 返回前分发 `on_search_result` |
| `src/ui_v2.html` | 新增更新提示 Toast 容器、插件设置区域 |
| `src/ui_v2.js` | 新增更新检查 + 插件管理 JS 逻辑；`doInit()` 中启动更新检查 + 加载插件 |
| `src/ui_v2.css` | 新增更新提示 Toast、插件卡片样式 |
| `version.json` | **新增**：仓库根目录版本信息文件 |

注：`engine.py` 不需要单独修改，hook 分发在 `api.py` 的 worker 层面完成，不侵入底层引擎。

### 4.2 启动流程变更

```
原流程：
  启动 → 加载科目 → 加载设置 → 显示主界面

新流程：
  启动 → 加载科目 → 加载设置 → 加载插件 → [异步]检查更新 → 显示主界面
       ↑
       插件加载失败不影响启动，记录日志即可
```

### 4.3 Hook 分发策略（关键设计决策）

为避免在每个 except 块中重复编写 hook 分发代码，在 `_create_download_worker` 中采用统一 return 后分发的策略：

```
worker(item):
  设置 status = "downloading"
  分发 on_download_start
  try:
    download_one(...)
    status = "done"
    return success=True
  except ... (各类异常):
    status = "failed", 设置 error/error_type
    return success=False
  finally:
    if success: 分发 on_download_complete
    else:       分发 on_download_failed
```

**`on_batch_complete`** 在 `_run_downloads` 方法的最末尾（所有重试完成后、设置 `phase="done"` 之前）统一分发一次：

```python
self.plugin_manager.dispatch("on_batch_complete", {
    "total": batch_total,
    "success": total_done,
    "failed": failed_count,
    "skipped": skipped_count,
    "retry_rounds": current_round,
})
```

---

## 五、测试策略

### 5.1 自动更新测试

| 场景 | 验证点 |
|---|---|
| GitHub API 正常返回 | 正确解析版本号，显示更新提示 |
| GitHub API 429 | 静默失败，不报错 |
| 网络不可用 | 静默失败，不报错 |
| 当前已是最新版 | 不显示提示 |
| 用户选择跳过版本 | 该版本不再提示 |
| 关闭自动检查 | 启动时不请求 API |

### 5.2 插件系统测试

| 场景 | 验证点 |
|---|---|
| 加载合法 Python 插件 | 正确初始化，事件触发时执行 |
| 加载合法命令插件 | 正确调用外部命令 |
| `plugin.json` 缺失字段 | 跳过加载，记录错误 |
| Python 插件抛出异常 | 主流程不受影响 |
| 外部命令超时 | 强制终止，记录超时错误 |
| 禁用插件 | 事件不再分发给该插件 |
| 并发事件 | 多个插件并行执行，互不干扰 |
| on_batch_complete 触发 | 下载全部完成后正确分发 |

---

## 六、发布 checklist

- [ ] 实现 `updater.py` 和 `plugin_manager.py`
- [ ] 修改 `api.py` 暴露新接口并集成 hook 分发
- [ ] 修改前端 UI（更新提示、插件设置面板）
- [ ] 在仓库根目录添加 `version.json`
- [ ] 编写插件开发文档（`docs/plugin-development.md`）
- [ ] 提供示例插件（Python + 外部命令各一个）
- [ ] 更新 `build.yml` 确保 `version.json` 被打包进 release
- [ ] 更新 README，说明新功能
- [ ] 打 tag `v5.2.0` 发布

---

## 七、附录

### 7.1 版本号规范

采用语义化版本 `MAJOR.MINOR.PATCH`：
- MAJOR：不兼容的 API 变更
- MINOR：向下兼容的功能新增
- PATCH：向下兼容的问题修复

### 7.2 插件 ID 规范

反向域名格式，如 `com.yourname.pluginname`，确保全局唯一。

### 7.3 相关文件引用

- 主入口：[src/main.py](/Users/yimingwu/Documents/C-Paper/src/main.py)
- API 层：[src/backend/api.py](/Users/yimingwu/Documents/C-Paper/src/backend/api.py)
- 下载引擎：[src/backend/engine.py](/Users/yimingwu/Documents/C-Paper/src/backend/engine.py)
- 搜索解析：[src/backend/parser.py](/Users/yimingwu/Documents/C-Paper/src/backend/parser.py)
- 缓存模块：[src/backend/cache.py](/Users/yimingwu/Documents/C-Paper/src/backend/cache.py)
- 常量定义：[src/backend/const.py](/Users/yimingwu/Documents/C-Paper/src/backend/const.py)
- 前端逻辑：[src/ui_v2.js](/Users/yimingwu/Documents/C-Paper/src/ui_v2.js)
- 前端样式：[src/ui_v2.css](/Users/yimingwu/Documents/C-Paper/src/ui_v2.css)
- 前端页面：[src/ui_v2.html](/Users/yimingwu/Documents/C-Paper/src/ui_v2.html)
- 构建配置：[.github/workflows/build.yml](/Users/yimingwu/Documents/C-Paper/.github/workflows/build.yml)
