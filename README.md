# C-Paper

> C-Paper 是面向 macOS 的 Cambridge International Education past paper 桌面工具，用来搜索、预览和批量下载试卷与 mark scheme。当前主线是原生 SwiftUI/AppKit 版本，适合学生、教师和需要批量整理 CIE 资料的学习场景。

[![Build Native macOS](https://github.com/yimingwu425/C-Paper/actions/workflows/build.yml/badge.svg)](https://github.com/yimingwu425/C-Paper/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/yimingwu425/C-Paper?label=release)](https://github.com/yimingwu425/C-Paper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 30 秒上手

下载安装：

- 前往 [Releases](https://github.com/yimingwu425/C-Paper/releases) 下载最新的 `C-Paper-Native-*-standalone-*.dmg`
- 打开 DMG 后把 `CPaperNative.app` 拖入 `Applications`
- 首次运行如遇到 macOS 安全提示，右键应用图标，选择“打开”，再确认打开

本地开发运行：

```bash
swift run CPaperNative
```

## 当前版本

当前 native 主线版本：`6.0.0`

6.0.0 重点：

- 后端改为 Swift 原生实现，active app 不再依赖 Python bridge
- 搜索、解析、缓存、下载、设置和数据源逻辑拆成模块化 Swift 后端
- 自动数据源 fallback：Frankcie、PapaCambridge、PastPapers、EasyPaper
- 设置页支持手动选择数据源，手动模式失败时不自动切换
- 本地数据迁移到 macOS Application Support，并兼容迁移旧 `~/.cie_cache/` 设置、收藏和下载历史

## 主要能力

- 搜索试卷：按科目、年份、考季检索 CIE past papers
- 结果分组：自动把 Question Paper、Mark Scheme 和相关组件组织在一起
- PDF 预览：选择结果后在应用内缓存并预览 PDF，也可直接用浏览器打开
- 批量下载：按年份范围、考季和 Paper 编号生成下载清单
- 下载队列：集中查看下载进度、完成数、失败状态和取消状态
- 收藏科目：把常用科目固定到侧边栏，减少重复选择
- 本地设置：保存下载目录、代理、数据源、并发、速率和重复文件处理策略

## 架构现状

C-Paper 现在只维护 native macOS 主线。旧的 Python + pywebview 桌面壳已经归档，仅保留历史参考和必要维护。

```text
C-Paper/
├── Package.swift                 # Swift Package Manager 入口
├── macos/                        # active native macOS app source and Swift tests
├── scripts/                      # native DMG 构建与发布脚本
├── assets/                       # 应用图标和共享图片资产
├── docs/                         # 项目索引、工作日志和内部文档
├── site/                         # 静态项目站点
└── legacy/                       # archived legacy implementations
```

运行关系：

```text
CPaperNative.app
  -> SwiftUI/AppKit UI
    -> NativeBackendService
      -> source registry / parser / cache / download manager / persistence
```

## 开发环境

需要：

- macOS
- Xcode command line tools / Swift Package Manager

运行 native app：

```bash
swift run CPaperNative
```

运行测试：

```bash
swift test --jobs 1
```

构建 native DMG：

```bash
bash scripts/build_native_dmg.sh
```

如需 release 配置构建：

```bash
CONFIGURATION=release bash scripts/build_native_dmg.sh
```

## 发布流程

主发布线是 native macOS DMG，由 GitHub Actions 的 [Build Native macOS](https://github.com/yimingwu425/C-Paper/actions/workflows/build.yml) workflow 负责。

常规发布步骤：

```bash
git tag v6.0.0
git push origin main
git push origin v6.0.0
```

tag 触发后，workflow 会：

- 构建 native macOS app
- 打包 standalone DMG
- 挂载并校验 DMG 内容
- 上传 Actions artifact
- 创建 GitHub Release
- 附带详细 release notes

## Legacy 说明

以下内容不再是主维护实现：

- `legacy/python-backend/bridge/`
- `legacy/python-backend/backend/`
- `legacy/python-backend/tests/`
- `legacy/pywebview/main.py`
- `legacy/pywebview/ui_v2.html`
- `legacy/pywebview/ui_v2.css`
- `legacy/pywebview/ui_v2.js`
- `legacy/pywebview/packaging/`

legacy 5.2.1 是旧 pywebview 线路的最终归档 release。后续功能、修复和发布默认都进入 native macOS 主线。

## 数据与隐私

C-Paper 不上传、不收集、不分享用户个人数据。应用只在本机保存必要状态，例如：

- 设置
- 收藏科目
- 下载历史
- 搜索缓存

默认应用数据目录为 `~/Library/Application Support/C-Paper/`。首次启动 6.0.0 时，应用会从旧 `~/.cie_cache/` 复制可迁移的设置、收藏和下载历史。下载文件保存在用户选择的目录中。

## 免责声明

本项目是本地桌面检索与下载工具，不拥有、不存储、不托管任何 CIE 试卷文件。应用搜索和下载的资料来自第三方公开网站，包括 [cie.fraft.cn](https://cie.fraft.cn)、[PapaCambridge](https://papacambridge.com/)、[PastPapers.co](https://pastpapers.co/) 和 [EasyPaper](https://easy-paper.com/paperview)。第三方数据源的可用性、准确性和完整性不由本项目保证。

所有 CIE（Cambridge International Education）试卷、评分标准及相关资料的著作权归 Cambridge Assessment International Education 或相应权利方所有。本项目仅供个人学习、教学研究和学术交流使用。用户不得将下载资料用于商业营利、倒卖、侵犯知识产权或违反所在国家/地区法律法规的行为。

## License

本项目使用 [MIT License](LICENSE)。
