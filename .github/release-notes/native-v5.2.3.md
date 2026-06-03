# C-Paper Native 5.2.3

C-Paper Native 5.2.3 is the current maintained macOS release of C-Paper. The active product line is now the native SwiftUI/AppKit app, backed by the Python JSON-lines bridge and shared Python backend.

## Download

| Platform | File | Notes |
| --- | --- | --- |
| macOS | `C-Paper-Native-5.2.3-standalone-*.dmg` | Open the DMG and drag `CPaperNative.app` into `Applications`. |

## What changed in 5.2.3

- 修复非最大化窗口下 PDF 预览挤压与溢出
- 改进 PDF 预览在窗口缩放后的自动适配
- 下载队列和批量下载页在最小窗口高度下可滚动查看完整内容

## Main features

- Search Cambridge International Education past papers by subject, year, and season.
- Preview PDFs inside the app, with local cache reuse when files already exist.
- Group question papers and mark schemes together for easier review.
- Build batch download queues across years, seasons, and paper numbers.
- Track download progress, completed items, failed items, and cancellation state.
- Save local settings such as download directory, proxy URL, rate, concurrency, duplicate-file handling, and favorite subjects.

## Install notes

macOS may show a developer verification warning on first launch. If that happens, right-click `CPaperNative.app`, choose **Open**, and confirm.

## Architecture note

This release is for the native macOS line:

- `macos/`: SwiftUI/AppKit desktop client
- `bridge/`: Python bridge used by the native app
- `backend/`: shared Python backend for search, parsing, caching, downloads, and updates

The old Python + pywebview implementation remains archived under `legacy/pywebview/` and is not the active product line.

## Verification

The release workflow builds the native app, packages a standalone DMG, verifies the DMG, mounts it, checks the app bundle and Applications symlink, and then publishes this GitHub Release.

## Disclaimer

C-Paper is a local desktop search and download helper. It does not own, host, or redistribute Cambridge International Education papers. Data availability depends on the third-party source used by the app.
