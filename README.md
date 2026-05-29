# C-Paper

> C-Paper 当前的主维护版本是 macOS 原生版。仓库中的 Swift/macOS 客户端、Python bridge 和共享 Python backend 共同构成当前主线；旧的 Python + pywebview 桌面壳已归档到 `legacy/pywebview/`。

[![Build](https://github.com/yimingwu425/C-Paper/actions/workflows/build.yml/badge.svg)](https://github.com/yimingwu425/C-Paper/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 当前维护方向

- 主产品：macOS 原生 SwiftUI/AppKit 客户端
- 主入口：仓库根目录 `Package.swift`
- 运行时依赖：
  - `macos/`：原生桌面客户端
  - `bridge/`：native 调用的 Python bridge
  - `backend/`：共享 Python backend
- 归档实现：`legacy/pywebview/`

## 快速开始

### 运行主线 macOS 版本

```bash
swift run CPaperNative
```

### 运行测试

```bash
swift test
pytest
```

### 构建 macOS DMG

```bash
bash scripts/build_native_dmg.sh
```

## 项目结构

```text
C-Paper/
├── Package.swift                 # Swift package root entrypoint
├── macos/                        # Active macOS app source and tests
├── bridge/                       # Active Python bridge used by the macOS app
├── backend/                      # Active shared Python backend
├── tests/                        # Python backend tests
├── legacy/pywebview/             # Archived Python + pywebview frontend
├── scripts/                      # Active native build/release scripts
├── site/                         # Static project site
├── assets/                       # Icons and image assets
└── docs/                         # Project memory and internal docs
```

## 依赖说明

根目录 `requirements.txt` 只保留当前主线所需的 Python 依赖：

- `requests`
- `urllib3`
- `pytest`

归档 pywebview 前端需要的依赖在：

- `legacy/pywebview/requirements.txt`

## Legacy 说明

以下内容不再是主维护实现：

- `legacy/pywebview/main.py`
- `legacy/pywebview/ui_v2.html`
- `legacy/pywebview/ui_v2.css`
- `legacy/pywebview/ui_v2.js`
- `legacy/pywebview/packaging/`

这些代码会保留以便参考、回溯和必要维护，但不再代表当前产品方向，也不再是 GitHub 主发布线。

## 数据与隐私

C-Paper 不上传、不收集、不分享用户个人数据。应用会在本地保存必要状态，例如设置、收藏、下载历史和搜索缓存。清理本地数据时，可删除 `~/.cie_cache/` 和用户选择的下载目录。

## 构建与发布

- GitHub Actions 主 workflow：`.github/workflows/build.yml`
- 主发布线：native macOS DMG
- 旧 pywebview 的 Windows / macOS 打包脚本仅保留在 `legacy/pywebview/packaging/`，不再作为主线自动发布流程

## 免责声明

本项目是本地桌面检索与下载工具，不拥有、不存储、不托管任何 CIE 试卷文件。应用搜索和下载的资料来自第三方公开网站 [cie.fraft.cn](https://cie.fraft.cn)，第三方数据源的可用性、准确性和完整性不由本项目保证。

所有 CIE（Cambridge International Education）试卷、评分标准及相关资料的著作权归 Cambridge Assessment International Education 或相应权利方所有。本项目仅供个人学习、教学研究和学术交流使用。用户不得将下载资料用于商业营利、倒卖、侵犯知识产权或违反所在国家/地区法律法规的行为。

## License

本项目使用 [MIT License](LICENSE)。
