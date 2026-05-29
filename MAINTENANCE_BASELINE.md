# C-Paper 维护基线

本文档记录当前 native-first 维护基线。后续默认以 macOS 原生版为唯一主线，旧 pywebview 前端只保留为 legacy 参考实现。

## 主线边界

当前主线由三部分组成：

- `macos/`：SwiftUI / AppKit 原生客户端
- `bridge/`：native 调用的 Python bridge
- `backend/`：共享 Python backend

以下内容不是当前主线：

- `legacy/pywebview/` 前端壳
- `legacy/pywebview/packaging/` 打包脚本
- 任何以 pywebview 为中心的发布流程

## 发布与构建基线

主发布线：

- 根 Swift 包：`Package.swift`
- 主构建脚本：`scripts/build_native_dmg.sh`
- 主 CI / Release workflow：`.github/workflows/build.yml`

发布前重点检查：

- `version.json`、`backend/const.py`、`scripts/build_native_dmg.sh` 中的版本号保持一致
- native 构建和 DMG 发布只走一条 GitHub Actions 主线
- bridge 路径解析优先指向 `bridge/cpaper_bridge.py`
- 根目录 `requirements.txt` 只保留 active backend/test 依赖
- `legacy/pywebview/requirements.txt` 单独承载 pywebview 依赖

## 共享 Python Backend 基线

虽然 pywebview 前端已归档，但 Python backend 仍是当前主线的一部分，因为 native app 仍通过 bridge 依赖它。

维护要求：

- 保持 `backend/` 可被 `bridge/cpaper_bridge.py` 直接导入
- 不要把 `backend/` 误归档到 legacy
- Python tests 继续作为 active regression suite 保留

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
pytest
python -m py_compile bridge/cpaper_bridge.py backend/*.py legacy/pywebview/main.py
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

C-Paper 的当前任务不是同时维护两套桌面实现，而是稳定 native macOS 主线，并把 bridge + shared backend 作为明确、可理解的支撑层。
