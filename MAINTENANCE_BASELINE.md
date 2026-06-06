# C-Paper 维护基线

本文档记录当前 native-first 维护基线。后续默认以 macOS 原生版为唯一主线，旧 Python/pywebview 实现只保留为 legacy 参考实现。

## 当前主线

当前主线由以下部分组成：

- 根 Swift 包：`Package.swift`
- `macos/`：SwiftUI / AppKit 原生客户端
- `macos/Tests/CPaperNativeTests/`：当前主线 Swift 测试
- Swift 原生 backend：位于 `macos/` 下的 backend 模块与服务
- `scripts/`：当前主线构建脚本
- `scripts/lib/`：当前主线 shell helper
- `assets/`、`docs/`：当前主线共享资源与内部文档

项目站点说明：

- 外部项目站点链接待补充；不要把 `site/` 视为当前仓库主线目录

## Legacy 边界

以下内容不是当前主线：

- `legacy/python-backend/`：归档的 Python bridge/backend/test suite
- `legacy/pywebview/`：归档的 Python + pywebview 前端壳
- `legacy/pywebview/packaging/`：legacy 打包脚本
- legacy Python 命令与测试：仅在明确维护 legacy 时使用

## 验证基线

每轮维护结束前至少运行：

```bash
swift test --jobs 1
```

active 维护默认以 Swift 测试和 `macos/` 主线边界校验为准；legacy 脚本与 Python 测试只在明确修改 legacy 时再单独验证。

## 当前判断

C-Paper 的当前任务不是同时维护两套桌面实现，而是稳定 native macOS 主线，并把归档的 Python/pywebview 代码明确隔离在 `legacy/` 下。
