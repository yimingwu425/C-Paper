# C-Paper v5.1

---

## 一、项目声明

**C-Paper** 是一款跨平台桌面应用程序，旨在帮助教师和学生便捷地搜索、浏览和批量下载 CIE（Cambridge International Education）历年考试真题（Question Papers）和评分标准（Mark Schemes）。

### 主要功能

- 🔍 **智能搜索** —— 按科目代码、年份、季节批量检索试卷，支持多年度、多季节并发预览
- 📥 **批量下载** —— 多线程并发下载，支持限速、断点续传、自动重试与失败重试
- 📂 **自动分组** —— 自动将试卷（QP）与评分标准（MS）配对，按年份和类别生成目录结构
- ⭐ **收藏管理** —— 收藏常用科目代码，一键快速搜索
- 🗂️ **历史记录** —— 自动记录已下载文件，支持覆盖、跳过、仅缺失三种去重模式
- 🌙 **明暗主题** —— 支持浅色/深色双主题切换，保护视力
- ⚙️ **灵活配置** —— 可自定义保存目录、并发线程数、请求速率限制、代理等

### 技术架构

| 层级 | 技术 | 说明 |
|------|------|------|
| 前端 UI | HTML5 + CSS3 + Vanilla JS | 三栏布局桌面界面，Google Fonts 字体 |
| 桌面容器 | pywebview | 将 Web 界面嵌入原生桌面窗口（macOS WebKit / Windows Edge WebView2） |
| 后端 | Python 3 | 纯 Python，无框架依赖 |
| 并发下载 | concurrent.futures.ThreadPoolExecutor | 多线程下载，可配置 1-16 线程 |
| 限流控制 | 令牌桶算法（TokenBucket） | 可配置 1-20 次/秒 |
| 故障隔离 | 断路器模式（CircuitBreaker） | 连续失败 ≥5 次后熔断 30 秒，自动恢复 |
| 缓存 | 本地 JSON 文件 | 搜索缓存 TTL 24 小时，最多 200 个文件 |
| 分发 | PyInstaller + GitHub Actions | macOS → DMG，Windows → EXE/ZIP |

### 系统要求

- **macOS**：macOS 11.0 及以上
- **Windows**：Windows 10 v1803 及以上（需内置 Edge WebView2）

---

## 二、免责声明

### 数据来源声明

本应用所搜索和下载的试卷数据均来源于第三方公开网站 [cie.fraft.cn](https://cie.fraft.cn)。**本应用开发者不拥有、不存储、不托管任何试卷文件**，仅提供便捷的搜索与下载工具功能。

### 版权声明

所有 CIE（Cambridge International Education）试卷、评分标准及相关学术材料的著作权归 **Cambridge Assessment International Education**（剑桥大学国际考评部）所有。本应用仅为学术资源的检索与下载工具，不对任何试卷内容的合法性、准确性、完整性负责。

### 使用目的限制

本应用**仅供个人学习、教学研究和学术交流使用**。用户严禁将下载的试卷用于以下用途：

- 商业营利、倒卖或任何形式的商业行为
- 侵犯 Cambridge Assessment International Education 或其授权方知识产权的行为
- 违反所在国家/地区法律法规的行为

### 责任限制

- 用户使用本应用所产生的任何法律后果，由用户自行承担
- 本应用开发者不对因使用本应用而导致的任何直接或间接损失承担责任
- 如相关版权方认为本应用侵犯了其合法权益，请联系开发者，开发者将积极配合处理
- 本应用不保证服务的持续性、及时性和安全性，因第三方数据源（cie.fraft.cn）不可用导致的下载失败，开发者不承担责任

---

## 三、开源许可证声明（MIT License）

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

---

## 四、隐私声明

### 数据收集

本应用**不上传、不收集、不分享**任何用户个人数据至远程服务器。

### 本地数据存储

为实现应用功能，本应用会在用户本地设备上存储以下数据：

| 数据类型 | 存储位置 | 用途 | 是否含个人信息 |
|----------|----------|------|:---:|
| 用户设置（主题、并发数、保存目录等） | `~/.cie_cache/settings.json` | 持久化用户偏好配置 | 否 |
| 收藏的科目代码 | `~/.cie_cache/favorites.json` | 收藏管理 | 否 |
| 下载历史记录 | `~/.cie_cache/download_history.json` | 去重、防止重复下载 | 否 |
| 搜索缓存 | `~/.cie_cache/search/` | 加速重复搜索，减少网络请求 | 否 |
| 下载的试卷文件 | 用户自定义目录 | 保存下载结果 | 否 |

### 网络请求

- 本应用仅在用户主动执行搜索或下载操作时向 **cie.fraft.cn** 发起网络请求
- 请求中包含标准的 HTTP User-Agent 标识 `C-Paper/5.1 (Desktop)`
- 不向任何其他服务器发送数据
- 如果用户配置了 HTTP 代理，网络请求将经过该代理

### 数据清理

卸载本应用后，如需彻底清除所有数据，请手动删除 `~/.cie_cache/` 目录及保存试卷的目录。本应用不会在卸载程序之外保留任何数据。

---

> **C-Paper** — 让 CIE 试卷搜索更简单。
