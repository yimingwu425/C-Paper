# C-Paper 维护基线

本文档记录当前 native-first 维护基线。后续默认以 macOS 原生版为唯一主线，旧 Python/pywebview 实现只保留为 legacy 参考实现。

## 主线边界

当前主线由以下部分组成：

- `macos/`：SwiftUI / AppKit 原生客户端
- Swift 原生 backend：位于 `macos/` 下的 backend 模块与服务
- `scripts/`、`assets/`、`docs/`：当前主线使用的构建脚本、共享资源与内部文档

以下内容不是当前主线：

- `legacy/python-backend/`：归档的 Python bridge/backend/test suite
- `legacy/pywebview/` 前端壳
- `legacy/pywebview/packaging/` 打包脚本
- 任何以 pywebview 为中心的发布流程
- 外部项目站点：仓库内链接待补充，不要把 `site/` 视为当前仓库主线目录

## 发布与构建基线

主发布线：

- 根 Swift 包：`Package.swift`
- 主构建脚本：`scripts/build_native_dmg.sh`
- 主 CI / Release workflow：`.github/workflows/build.yml`

发布前重点检查：

- `version.json` 与 native 构建脚本中的版本号保持一致
- native 构建和 DMG 发布只走一条 GitHub Actions 主线
- active 验证以 Swift 构建与 Swift tests 为主
- legacy Python 依赖与脚本仅保留在 `legacy/` 下

## Legacy 处理规则

`legacy/pywebview/` 的定位：

- 保留源码与旧打包脚本
- 不再作为默认运行入口
- 不再作为 GitHub 主发布线
- 仅在需要兼容、回溯或迁移参考时才修改

## 验证基线

每轮维护结束前至少运行：

```bash
swift test
bash -n scripts/build_native_dmg.sh
bash -n legacy/pywebview/packaging/build_mac.sh
git diff --check
```

如果改动涉及 GitHub Actions：

```bash
python3 - <<'PY'
from pathlib import Path
import yaml
yaml.safe_load(Path('.github/workflows/build.yml').read_text())
print('build.yml: ok')
PY
```

## 当前判断

C-Paper 的当前任务不是同时维护两套桌面实现，而是稳定 native macOS 主线，并把归档的 Python/pywebview 代码明确隔离在 `legacy/` 下。
