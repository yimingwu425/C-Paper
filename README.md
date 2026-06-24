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
- 当前正式 GitHub Release 只由 `v*` tag-only release flow 发布；手动 `workflow_dispatch` 只用于验证和打包 DMG artifact，不会发布 release。

本地开发运行：

```bash
swift run CPaperNative
```

## 当前版本

当前 native 主线版本：`6.0.6`

当前版本重点：

- 新增完整中文 macOS 菜单栏：`C-Paper`、`文件`、`编辑`、`显示`、`窗口`、`帮助`
- 菜单动作已接入设置、检查更新、搜索/批量/下载切换、诊断复制和支持目录打开
- 原生启动阶段会在窗口出现前安装主菜单，并保证重复启动路径下只安装一次
- 下载目录检查新增统一 helper，无法使用的路径会给出明确中文提示
- 保留 Swift 原生 backend、多源 fallback、批量下载、预览、下载历史和设置能力

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
├── macos/                        # active SwiftUI/AppKit app、Swift backend、Swift tests
├── scripts/                      # active native 构建脚本
├── scripts/lib/                  # active shell helpers for native scripts
├── assets/                       # 应用图标和共享图片资产
├── docs/                         # 项目索引、工作日志和内部文档
└── legacy/                       # archived legacy implementations
```

项目站点为外部托管内容，当前状态是 external-link pending；不要把 `site/` 视为当前仓库中的 active 实现目录。

当前贡献入口可以直接按下面理解：

- active source：根 `Package.swift` + `macos/`
- active tests：`macos/Tests/CPaperNativeTests/`
- active scripts/assets/docs：`scripts/`、`scripts/lib/`、`assets/`、`docs/`
- legacy archives：`legacy/python-backend/`、`legacy/pywebview/`

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

构建脚本位置：

```bash
bash scripts/build_native_dmg.sh
```

## 发布与验证

当前 native GitHub Actions workflow 位于 `.github/workflows/build.yml`，按 `validate/package/release` 分段：

- `validate`：在 native 相关 pull request、main push、tag push 和手动 `workflow_dispatch` 上运行，检查 shell 语法、`version.json`、workflow YAML、版本漂移、仓库卫生、Swift 质量门和 `swift test --jobs 1`。
- `package`：依赖 `validate`，只在 `workflow_dispatch` 或 `push` 事件上运行；它构建 native DMG、执行 `bash scripts/verify_native_dmg.sh` 做 `hdiutil verify` / 挂载 / app / symlink / background / mounted-app codesign 检查，然后上传 30 天 artifact。
- `release`：依赖 `package`，只在 `push` 的 `v*` tag 上发布 GitHub Release；main 分支 push 和 `workflow_dispatch` 都不会发布 release。

本地做 release package 自检时，可先运行：

```bash
CONFIGURATION=release bash scripts/build_native_dmg.sh
bash scripts/verify_native_dmg.sh
```

如果想把当前 native release 候选常用 gate 一次性跑完，可用：

```bash
bash scripts/run_native_release_audit.sh
```

需要把可选 package / live source 也纳入同一轮审计时，可加：

```bash
bash scripts/run_native_release_audit.sh --with-package --with-live-sources
```

如果你想明确跑“更强的 RC 审计”而不是自己记参数组合，可直接用：

```bash
bash scripts/run_native_release_audit.sh --release-candidate
```

release notes 由 tag release job 根据 `version.json` 的 `release_notes` 和固定 native release 模板生成。`.github/release-notes/` 中保留的说明用于记录既有发布线，legacy 说明只面向最终归档版本。

## 签名与公证

默认本地和 CI 构建都使用 ad hoc 签名；没有 Apple 凭据时，`bash scripts/build_native_dmg.sh` 仍然可用。ad hoc DMG 首次打开时，macOS 可能提示无法验证开发者，此时可右键 `CPaperNative.app` 选择“打开”。

可选 Developer ID/notary 路径：

- 如需本地走 Developer ID 路径，可导出 `CPAPER_CODESIGN_IDENTITY`；再额外导出 `CPAPER_NOTARY_KEYCHAIN_PROFILE` 后，脚本会在生成最终 DMG 后执行 `xcrun notarytool submit --wait`，成功后再 `xcrun stapler staple`。
- GitHub Actions 预留的可选 secrets 名称为：`CPAPER_DEVELOPER_ID_CERT_P12_BASE64`、`CPAPER_DEVELOPER_ID_CERT_PASSWORD`、`CPAPER_CODESIGN_IDENTITY`、`CPAPER_NOTARY_KEYCHAIN_PROFILE`、`CPAPER_NOTARY_APPLE_ID`、`CPAPER_NOTARY_TEAM_ID`、`CPAPER_NOTARY_APP_PASSWORD`。只有这些 secrets 全部存在时，workflow 才会导入证书、配置 `notarytool` profile，并启用 Developer ID 签名与公证；否则继续保持 ad hoc 打包。

## Legacy 说明

以下内容不再是主维护实现：

- `legacy/python-backend/`
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

默认应用数据目录为 `~/Library/Application Support/C-Paper/`。首次启动 6.x 时，应用会从旧 `~/.cie_cache/` 复制可迁移的设置、收藏和下载历史。下载文件保存在用户选择的目录中。

## 数据源可靠性

C-Paper 的搜索、预览和下载结果依赖第三方公开数据源的当前可用性。自动模式下，FrankCIE 优先，EasyPaper 是主要备用源，PastPapers 是 best-effort 备用源；PapaCambridge 遇到 Cloudflare challenge 时会报告不可用，不会尝试绕过挑战。手动数据源模式下，所选源失败时不会自动切换到其他源。

这也是项目的 privacy/disclaimer/data source reliability 边界：C-Paper 不控制第三方站点的结构、稳定性、完整性或版权状态，只把可访问的公开链接整理给本机用户使用。

## 免责声明

本项目是本地桌面检索与下载工具，不拥有、不存储、不托管任何 CIE 试卷文件。应用搜索和下载的资料来自第三方公开网站，包括 [cie.fraft.cn](https://cie.fraft.cn)、[PapaCambridge](https://papacambridge.com/)、[PastPapers.co](https://pastpapers.co/) 和 [EasyPaper](https://easy-paper.com/paperview)。第三方数据源的可用性、准确性和完整性不由本项目保证。

所有 CIE（Cambridge International Education）试卷、评分标准及相关资料的著作权归 Cambridge Assessment International Education 或相应权利方所有。本项目仅供个人学习、教学研究和学术交流使用。用户不得将下载资料用于商业营利、倒卖、侵犯知识产权或违反所在国家/地区法律法规的行为。

## License

本项目使用 [MIT License](LICENSE)。
