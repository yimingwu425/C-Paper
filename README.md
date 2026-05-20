# C-Paper v5.2.1

C-Paper 是一款桌面端 CIE（Cambridge International Education）试卷检索与下载工具，用于搜索、预览并批量下载历年 Question Papers 和 Mark Schemes。它面向需要整理 CIE 试卷资料的教师、学生和教研场景，重点放在稳定的桌面使用体验。

---

## 主要功能

- **试卷搜索**：按科目代码、年份和考试季节检索 CIE 试卷。
- **批量预览**：按年份范围、季节和 Paper 类型生成待下载列表。
- **批量下载**：支持 QP/MS 配对下载、并发下载、限速、自动重试和取消。
- **文件整理**：可按年份和 QP/MS 分类保存，也可合并到同一目录。
- **下载历史**：记录已下载文件，支持覆盖、跳过、仅下载缺失文件。
- **收藏科目**：保存常用科目代码，便于快速再次搜索。
- **基础设置**：支持保存目录、主题、并发数、请求速率和 HTTP 代理配置。

## 技术架构

| 层级 | 技术 | 说明 |
|------|------|------|
| 前端 UI | HTML5 + CSS3 + Vanilla JS | 三栏布局桌面界面 |
| 桌面容器 | pywebview | 将 Web 界面嵌入原生桌面窗口 |
| 后端 | Python 3 + requests | 搜索、解析、下载和本地持久化 |
| 并发下载 | ThreadPoolExecutor | 可配置下载线程数 |
| 限流控制 | TokenBucket | 控制请求速率 |
| 本地缓存 | JSON 文件 | 保存设置、收藏、历史和搜索缓存 |
| 打包分发 | PyInstaller | macOS DMG / Windows ZIP |

## 系统要求

- **macOS**：macOS 11.0 及以上
- **Windows**：Windows 10 v1803 及以上，需 Edge WebView2
- **开发环境**：Python 3.11 及以上建议

---

## 本地运行

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python src/main.py
```

Windows PowerShell：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python src\main.py
```

### Swift 原生预览版

```bash
./script/build_and_run.sh
```

Swift 原生路线使用 SwiftUI/AppKit 构建 macOS 前端，通过 `native/bridge/cpaper_bridge.py` 复用现有 Python 后端能力。当前 pywebview 版本仍是稳定主线，Swift 版本在 `codex/swift-native-ui` 分支迭代。

## 打包

macOS：

```bash
bash scripts/build_mac.sh
```

Windows：

```bat
scripts\build_win.bat
```

打包产物默认输出到 `dist/` 目录。

---

## 免责声明

### 数据来源

本应用搜索和下载的试卷数据来源于第三方公开网站 [cie.fraft.cn](https://cie.fraft.cn)。本应用开发者不拥有、不存储、不托管任何试卷文件，仅提供本地桌面检索与下载工具。

### 版权声明

所有 CIE（Cambridge International Education）试卷、评分标准及相关学术材料的著作权归 Cambridge Assessment International Education 所有。本应用不对试卷内容的合法性、准确性和完整性负责。

### 使用限制

本应用仅供个人学习、教学研究和学术交流使用。用户不得将下载的资料用于商业营利、倒卖、侵犯知识产权或违反所在国家/地区法律法规的行为。

### 责任限制

- 用户使用本应用产生的任何法律后果由用户自行承担。
- 因第三方数据源不可用、网络异常或本地环境问题导致的搜索和下载失败，开发者不承担责任。
- 如相关版权方认为本应用侵犯其合法权益，请联系开发者处理。

---

## 隐私说明

C-Paper 不上传、不收集、不分享用户个人数据。为实现桌面端功能，应用会在本地保存以下数据：

| 数据类型 | 存储位置 | 用途 |
|----------|----------|------|
| 用户设置 | `~/.cie_cache/settings.json` | 保存主题、目录、并发数、代理等设置 |
| 收藏科目 | `~/.cie_cache/favorites.json` | 保存常用科目代码 |
| 下载历史 | `~/.cie_cache/download_history.json` | 判断重复下载和下载记录 |
| 搜索缓存 | `~/.cie_cache/search/` | 加速重复搜索，减少网络请求 |
| 下载文件 | 用户选择的保存目录 | 保存试卷和评分标准 PDF |

网络请求仅用于用户主动执行的搜索、预览、下载、代理测试，以及应用内可选的版本检查。若用户配置 HTTP 代理，请求会经过该代理。

如需清除本地数据，可删除 `~/.cie_cache/` 目录和用户自定义的试卷保存目录。

---

## License

本项目使用 MIT License。

```
MIT License

Copyright (c) 2026 Ja-son-WU

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
