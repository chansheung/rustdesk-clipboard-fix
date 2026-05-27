# RustDesk Clipboard Crash Fix (Windows)

修复 RustDesk Windows 客户端因剪贴板 HTML 格式读取超时导致闪退的问题（`0xc0000374` 堆损坏）。

## 问题现象

- RustDesk 不定时闪退，需要重新打开
- 事件查看器中看到错误：`0xc0000374` (HEAP_CORRUPTION)，崩溃模块 `ntdll.dll`
- 日志中大量出现：`OSError(1460): 由于超时时间已过，该操作返回。`

## 根因

RustDesk 使用 `arboard` 库同步剪贴板时，在 Windows 上读取 `HTML` 格式会超时（OSError 1460），
该超时在特定条件下触发堆内存损坏，导致 `0xc0000374` 异常崩溃。

官方 PR [#7217](https://github.com/rustdesk/rustdesk/pull/7217) 只修复了 Linux/X11 平台，
Windows 平台问题至今未修复（[Issue #9222](https://github.com/rustdesk/rustdesk/issues/9222)）。

## 修复方法

修改 `src/clipboard.rs`，在 Windows 上跳过 `ClipboardFormat::Html` 格式读取：

```rust
#[cfg(all(not(target_os = "android"), target_os = "windows"))]
const SUPPORTED_FORMATS: &[ClipboardFormat] = &[
    ClipboardFormat::Text,
    // Windows 上跳过 HTML 格式，避免 OSError 1460 超时崩溃
    // ClipboardFormat::Html,
    ClipboardFormat::Rtf,
    ClipboardFormat::ImageRgba,
    ClipboardFormat::ImagePng,
    ClipboardFormat::ImageSvg,
    ClipboardFormat::Special(CLIPBOARD_FORMAT_EXCEL_XML_SPREADSHEET),
    ClipboardFormat::Special(RUSTDESK_CLIPBOARD_OWNER_FORMAT),
];
```

文字、RTF、图片复制粘贴完全正常，仅跳过极少使用的 HTML 格式。

## 适用版本

| 项目 | 版本 |
|------|------|
| RustDesk | **1.4.6** (2026-03-05) |
| 操作系统 | Windows 10/11 64-bit |

> ⚠️ 如果未来 RustDesk 版本更新，此 DLL 可能不兼容。需要在新版本源码上重新编译。

## 安装方法

### 一键安装（推荐）

仓库中的 `install.bat` 提供了自动化安装：

1. 下载 `install.bat` 和 `librustdesk.dll` 到同一目录
2. 右键 `install.bat` → **以管理员身份运行**
3. 脚本会自动关闭 RustDesk、备份原 DLL、安装修复版

### 快速安装（替换 DLL）

1. 退出 RustDesk（右键托盘图标 → 退出）
2. 下载本仓库 [Releases](https://github.com/chansheung/rustdesk-clipboard-fix/releases) 中的 `librustdesk.dll`
3. 复制到 RustDesk 安装目录：

```batch
copy /y librustdesk.dll "C:\Program Files\RustDesk\librustdesk.dll"
```

4. 重新启动 RustDesk

### 完整构建（从源码编译）

如果你需要在其他版本上应用此修复：

```batch
:: 1. 安装 Rust
rustup-init.exe -y --default-host x86_64-pc-windows-msvc

:: 2. 安装 Visual Studio 2022 Build Tools（C++ 工作负载）
:: 下载: https://aka.ms/vs/17/release/vs_buildtools.exe
vs_buildtools.exe --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended

:: 3. 克隆源码并修改
git clone --depth 1 --branch master https://github.com/rustdesk/rustdesk.git
cd rustdesk
:: 修改 src/clipboard.rs: Windows 上移除 ClipboardFormat::Html

:: 4. 安装 flutter_rust_bridge_codegen 并生成桥接代码
cargo install flutter_rust_bridge_codegen --version 1.80.1
flutter_rust_bridge_codegen generate

:: 5. 编译
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
cargo build --release --lib -p rustdesk --features flutter

:: 6. 产物位置
:: target\release\librustdesk.dll
```

## 验证修复

安装后检查日志是否还有 OSError 1460 错误：

```powershell
Get-Content "$env:APPDATA\RustDesk\log\rustdesk_rCURRENT.log" | Select-String "OSError"
```

如果无输出，说明修复生效。

## 相关链接

- [RustDesk GitHub](https://github.com/rustdesk/rustdesk)
- [Issue #9222 - timeout of copy past](https://github.com/rustdesk/rustdesk/issues/9222)
- [PR #7217 - Fix/arboard clipboard context timeout](https://github.com/rustdesk/rustdesk/pull/7217)

## 许可

MIT
