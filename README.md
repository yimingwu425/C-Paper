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

当前 native 主线版本：`5.2.3`

5.2.3 重点：

- 修复非最大化窗口下 PDF 预览挤压与溢出
- 改进 PDF 预览在窗口缩放后的自动适配
- 下载队列和批量下载页在最小窗口高度下可滚动查看完整内容
- 继续使用 Swift/macOS 客户端、Python bridge 和共享 Python backend 的主线架构

## 主要能力

- 搜索试卷：按科目、年份、考季检索 CIE past papers
- 结果分组：自动把 Question Paper、Mark Scheme 和相关组件组织在一起
- PDF 预览：选择结果后在应用内缓存并预览 PDF，也可直接用浏览器打开
- 批量下载：按年份范围、考季和 Paper 编号生成下载清单
- 下载队列：集中查看下载进度、完成数、失败状态和取消状态
- 收藏科目：把常用科目固定到侧边栏，减少重复选择
- 本地设置：保存下载目录、代理、并发、速率和重复文件处理策略

## 架构现状

C-Paper 现在只维护 native macOS 主线。旧的 Python + pywebview 桌面壳已经归档，仅保留历史参考和必要维护。

```text
C-Paper/
├── Package.swift                 # Swift Package Manager 入口
├── macos/                        # active native macOS app source and Swift tests
├── bridge/                       # native app 调用的 Python JSON-lines bridge
├── backend/                      # 搜索、解析、下载、缓存、插件等共享 Python backend
├── tests/                        # Python backend pytest 测试
├── scripts/                      # native DMG 构建与发布脚本
├── assets/                       # 应用图标和共享图片资产
├── docs/                         # 项目索引、工作日志和内部文档
├── site/                         # 静态项目站点
└── legacy/pywebview/             # archived legacy desktop shell
```

运行关系：

```text
CPaperNative.app
  -> bridge/cpaper_bridge.py
    -> backend/api.py
      -> parser / engine / cache / updater / plugin manager
```

## 开发环境

需要：

- macOS
- Xcode command line tools / Swift Package Manager
- Python 3
- `requests`、`urllib3`、`pytest`

安装 Python 依赖：

```bash
python3 -m pip install -r requirements.txt
```

运行 native app：

```bash
swift run CPaperNative
```

运行测试：

```bash
swift test --jobs 1
pytest
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
git tag v5.2.3
git push origin main
git push origin v5.2.3
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
- 插件配置

默认缓存目录为 `~/.cie_cache/`。下载文件保存在用户选择的目录中。

## 免责声明

本项目是本地桌面检索与下载工具，不拥有、不存储、不托管任何 CIE 试卷文件。应用搜索和下载的资料来自第三方公开网站 [cie.fraft.cn](https://cie.fraft.cn)，第三方数据源的可用性、准确性和完整性不由本项目保证。

所有 CIE（Cambridge International Education）试卷、评分标准及相关资料的著作权归 Cambridge Assessment International Education 或相应权利方所有。本项目仅供个人学习、教学研究和学术交流使用。用户不得将下载资料用于商业营利、倒卖、侵犯知识产权或违反所在国家/地区法律法规的行为。

## License

本项目使用 [MIT License](LICENSE)。
