# C-Paper 维护基线

本文档记录 v5.2.1 清仓收口后的维护方向。后续迭代不再沿用 v6 扩张计划，而是把 C-Paper 稳定在一个清晰、可长期维护的桌面工具边界内。

## 产品边界

C-Paper 的主线是桌面端 CIE 试卷工具：

- 搜索 Question Papers 和 Mark Schemes
- 预览待下载文件
- 批量下载和整理文件
- 管理下载历史、收藏科目和基础设置
- 支持必要的代理、更新检查和维护入口

后续不再把 AI、OCR、全文检索、协作服务、浏览器扩展、独立服务端等方向作为当前目标。这些方向已经从 v5.2.1 基线中移出。

## 下一阶段目标

下一阶段不是新增大功能，而是做维护硬化，让项目成为一个干净、稳定、容易发布的基线。

### 1. 变更分组和提交准备

把当前改动整理成清楚的几类：

- 清仓删除：旧归档脚本、浏览器扩展、Go 服务端、v6 文档、AI/OCR/FTS/协作相关模块
- 可靠性修复：下载取消、重试、原子写入、缓存坏文件处理、更新检查版本解析
- UX 收口：重复下载模式、批量预览计数、设置页高级维护折叠、PDF 预览退路
- 构建链路：macOS/Windows 打包入口、CI 产物名称、版本号和 release notes
- 测试补齐：覆盖缓存、下载取消、下载写入、插件派发、更新检查

目标是让最终提交能被快速理解，而不是变成一坨无法审阅的混合改动。

### 2. 发布前审计

发布前重点检查：

- `version.json`、`src/backend/const.py`、`src/main.py`、构建脚本中的版本号一致
- GitHub Actions、AppVeyor、macOS/Windows 本地打包脚本使用同一个入口：`src/main.py`
- 产物命名统一为 `C-Paper`
- `requirements.txt` 只保留桌面主线需要的依赖
- 仓库内没有 `__pycache__`、`.pyc`、旧 zip 或打包残留
- 残留扫描不再出现旧模块运行时引用

### 3. 插件系统最终决策

插件系统目前只作为“高级维护”入口保留，不再作为 README 主功能宣传。

短期策略：

- 保留插件列表、启用/禁用、打开插件目录
- 保留 Python hook 和 command hook 的现有能力
- 对无效插件类型做显式拒绝
- 确保懒加载不会丢失首次 hook 事件

后续如果继续精简，应成组删除：

- UI 中的插件高级维护区
- `src/backend/plugin_manager.py`
- `API` 中的插件相关方法
- `PLUGINS_DIR`
- 插件测试

不要只删一半，避免留下断裂入口。

### 4. 下载体验硬化

下载相关维护优先级高于新功能。

重点场景：

- 取消下载后 pending/downloading 状态必须及时变成 cancelled
- 自动重试等待期间可以快速取消
- `overwrite`、`skip`、`missing` 三种重复处理语义稳定
- 下载写入使用临时文件和原子替换，失败不破坏旧文件
- 下载列表的失败原因、重试按钮、完成统计保持一致

这一阶段的目标是“可预测”，不是“更多按钮”。

### 5. UI 小修，不做大改版

界面维护只做贴近主线的小修：

- 保持搜索、批量、下载三个工作区清楚
- 设置页默认展示基础项，高级维护折叠
- 批量预览显示 QP/MS/总数
- PDF 内嵌预览失败或加载慢时提供浏览器打开和复制链接
- 避免旧 UI 文件、概念稿和未使用页面继续留在 `src/`

除非有明确需求，不做新的视觉系统或大规模布局重构。

## 验证基线

每轮维护结束前至少运行：

```bash
PYTHONDONTWRITEBYTECODE=1 pytest -q tests
PYTHONPYCACHEPREFIX=/tmp/cpaper-pycache python3 -m py_compile src/main.py src/backend/*.py
node --check src/ui_v2.js
bash -n scripts/build_mac.sh
git diff --check
```

如果改动涉及 CI 或 YAML：

```bash
python3 - <<'PY'
from pathlib import Path
import yaml
for p in [Path('.github/workflows/build.yml'), Path('scripts/appveyor.yml')]:
    yaml.safe_load(p.read_text())
    print(f'{p}: ok')
PY
```

如果改动涉及清仓删除，还要做残留扫描：

```bash
rg -n "claude_engine|collab_client|dedup_engine|fts_engine|ocr_engine|pywebview\\.api\\.(collab_|ai_|fts_|ocr_)|cie_downloader_v5\\.py|v6|Claude|DeepSeek|OCR|FTS|dedup|collab|协作|浏览器插件|CIE下载器|CIE 下载器|ui\\.html|preview\\.html|claude-haha" README.md docs src scripts tests .github requirements.txt version.json
```

允许的无害命中：

- `version.json` 的 release note 中说明清理 v6
- SVG path 中偶然出现的 `v6`

## 当前判断

v5.2.1 之后，C-Paper 最需要的是一个干净、稳定、能发布的维护基线。只有这个基线站稳，后续 v5.3 才适合继续做小步迭代。

