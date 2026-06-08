# RustDesk Windows 修复版 DLL

包含剪贴板崩溃修复 + Explorer 卡死修复 + 硬件编解码（H265/NVENC）支持。

> **当前版本**: v1.4.6-fix6 · **DLL SHA256**: `E911B90344FC4803E5BE1885698D3B990C5076EA330CEFF3ACDE3C26C2BF4CD0` · **DLL 大小**: 32.19 MB
>
> 修复剪贴板相关的 `0xc0000374` 堆损坏崩溃，解决复制文件导致 Explorer 卡死的问题，并启用 H265/NVENC 硬件编解码。
> 已知仍存在与 Flutter 引擎 + OpenGL 渲染路径相关的偶发崩溃（详见 [已知问题](#已知问题)）。

---

## 目录

- [问题现象](#问题现象)
- [根因分析](#根因分析)
- [修复内容](#修复内容)
- [修复方法](#修复方法)
- [版本历史](#版本历史)
- [适用版本](#适用版本)
- [安装方法](#安装方法)
  - [一键安装（推荐）](#一键安装推荐)
  - [快速安装（替换 DLL）](#快速安装替换-dll)
  - [完整构建（从源码编译）](#完整构建从源码编译)
- [验证修复](#验证修复)
- [已知问题](#已知问题)
- [相关链接](#相关链接)
- [许可](#许可)

---

## 问题现象

- RustDesk 不定时闪退，需要重新打开
- 在文件资源管理器中复制文件（Ctrl+C）会导致 explorer.exe 卡死 30-60 秒
- 事件查看器中看到错误：`0xc0000374`（HEAP_CORRUPTION），崩溃模块 `ntdll.dll`
- 日志中大量出现：`OSError(1460): 由于超时时间已过，该操作返回。`

## 根因分析

RustDesk 使用 `arboard` 库同步剪贴板时，在 Windows 上读取 `HTML` 格式会超时（OSError 1460），该超时在特定条件下触发堆内存损坏，导致 `0xc0000374` 异常崩溃。

此外，RustDesk 的 C 侧 cliprdr 线程通过 `AddClipboardFormatListener` 注册剪贴板通知，在 `WM_CLIPBOARDUPDATE` 窗口过程中同步调用 `OpenClipboard()`，阻塞 explorer.exe 的 `SendMessage`，导致复制文件时 explorer 卡死 30-60 秒（详见 [技术分析文档](技术分析-Explorer卡死根因与修复方案.md)）。

## 修复内容

### 1. 剪贴板崩溃修复（原）
跳过 Windows 上 `ClipboardFormat::Html` 格式读取，避免 `OSError 1460` 超时触发 `0xc0000374` 堆损坏。

### 2. C 回调 IsStopped 检查（新增）
在 `client_format_list` C 回调入口检查 `(*context).IsStopped`，已禁用则立即返回，防止 unsafe 指针操作破坏堆。

### 3. 销毁上下文而非仅设停止标志（新增）
调用 `ContextSend::enable(false)` 彻底销毁 C 剪贴板上下文，注销所有 C 回调，而非仅设 `IsStopped = TRUE`（回调仍然注册）。

### 4. stop 条件增加 disable_clipboard 检查（新增）
文件剪贴板处理路径缺少 `disable_clipboard` 选项检查，禁用剪贴板后文件格式消息仍在处理。

### 5. 日志参数顺序修正（v1.4.6-fix2 新增）
`io_loop.rs` 中 debug 日志参数与格式化字符串错位，误导排查。

### 6. 阻止 C 侧 cliprdr 线程启动（v1.4.6-fix6 新增）
在 `ContextSend::enable()` 和 `make_sure_enabled()` 中对 Windows 平台直接返回 `Ok(())`，不创建 cliprdr context。这样 C 侧 `init_cliprdr()` 永远不会被调用，`AddClipboardFormatListener` 永远不注册，从根本上消除了复制文件导致 Explorer 卡死的问题（详见 [技术分析](技术分析-Explorer卡死根因与修复方案.md)）。

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

## 版本历史

| 版本 | Commit | 日期 | 大小 | 说明 |
|------|--------|------|------|------|
| **v1.4.6-fix6** | — | 2026-06-06 | 32.19 MB | 新增 Explorer 卡死修复（方案 A：阻止 C 侧 cliprdr 线程启动） |
| v1.4.6-fix2 | `4404ec8` | 2026-05-28 | 32.24 MB | 5 项修复全部合入；启用 hwcodec + flutter 特性 |
| v1.4.6-fix1 | — | 2026-05-27 | ~33.8 MB | 初步修复（后被 fix2 覆盖） |

**fix2 → fix6 主要变化**：
- 在 `ContextSend::enable()` 和 `make_sure_enabled()` 中对 Windows 平台直接返回 `Ok(())`，阻止 C 侧 cliprdr 线程启动
- 从根本上消除了复制文件导致 Explorer 卡死的问题
- 文字剪贴板通过 arboard 正常工作，不受影响

**fix1 → fix2 主要变化**：
- 通过 `RUSTFLAGS=-Ctarget-feature=-crt-static` 解决静态/动态 CRT 链接冲突
- vcpkg triplet 从 `x64-windows-static` 切换到 `x64-windows`，依赖安装路径相应调整
- DLL 体积从 33.8 MB 降至 32.24 MB（更精简的依赖布局）

## 适用版本

| 项目 | 详情 |
|------|------|
| RustDesk | **1.4.6** (2026-05) |
| DLL 大小 | **32.19 MB** |
| 导出函数 | **352+** |
| 操作系统 | Windows 10 / Windows 11 64-bit |
| 编译特性 | `hwcodec` + `flutter` |
| CRT 链接 | 动态（通过 `-Ctarget-feature=-crt-static` 移除静态 CRT） |

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
3. 打开**管理员 PowerShell**，停止 RustDesk 服务：

```powershell
Stop-Service -Name "RustDesk" -Force
```

4. 复制 DLL 到 RustDesk 安装目录：

```powershell
Copy-Item -Path .\librustdesk.dll -Destination "C:\Program Files\RustDesk\librustdesk.dll" -Force
```

5. 启动 RustDesk 服务，托盘图标即会出现：

```powershell
Start-Service -Name "RustDesk"
```

> 💡 **要点**：替换 DLL 前必须先停止服务，否则文件被占用无法覆盖。替换后需启动服务，托盘图标才会出现。

### 完整构建（从源码编译）

如果你需要在其他版本上应用此修复，或者希望自己验证编译过程，请按以下步骤操作。本节详细记录了实际编译过程中容易遇到的坑和解决方案。

---

#### 环境准备

```batch
:: 1. 安装 Rust（MSVC 工具链）
rustup-init.exe -y --default-host x86_64-pc-windows-msvc

:: 2. 安装 Visual Studio 2022（Community / Professional / Enterprise 均可）
::    必须勾选"使用 C++ 的桌面开发"工作负载
::    下载: https://visualstudio.microsoft.com/zh-hans/downloads/
```

#### 克隆源码并检查修复

```batch
git clone --depth 1 --branch master https://github.com/rustdesk/rustdesk.git
cd rustdesk
```

进入源码后，先确认 `src/clipboard.rs` 中 Windows 的 `SUPPORTED_FORMATS` 是否已经移除了 `ClipboardFormat::Html`。最新源码可能已自带此修复；如果尚未修复，按[修复方法](#修复方法)一节手动修改。

#### 安装 flutter_rust_bridge 并生成桥接代码

```batch
cargo install flutter_rust_bridge_codegen --version 1.80.1
flutter_rust_bridge_codegen generate
```

#### 激活 VS 2022 开发者命令提示符

本步骤**必不可少**——编译需要 MSVC 工具链和 Windows SDK，必须通过 VS 的开发者命令提示符初始化环境变量。

```batch
call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
:: 或使用 VsDevCmd：
call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
```

同时设置 LLVM/Clang 相关环境变量（`flutter_rust_bridge` 代码生成依赖 libclang）：

```batch
set LIBCLANG_PATH=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\Llvm\x64\bin
set BINDGEN_EXTRA_CLANG_ARGS=-isystem "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.xx.xxxxx\include"
```

> 请将路径中的 `14.xx.xxxxx` 替换为你实际安装的 MSVC 版本号。

#### 配置 VCPKG 环境

RustDesk 依赖 vcpkg 管理的 FFmpeg 等 C/C++ 库。你需要设置 `VCPKG_ROOT` 指向正确的 vcpkg 路径：

```batch
set VCPKG_ROOT=C:\path\to\your\vcpkg
```

> 💡 **头文件提示**：如果编译时提示找不到 `vpx`、`aom`、`libyuv`、`opus` 等头文件，可能是因为这些库只安装在了 `x64-windows-static` triplet 下。你需要把它们复制到 `x64-windows` 目录：
>
> ```
> 从: %VCPKG_ROOT%\installed\x64-windows-static\include\
> 到:   %VCPKG_ROOT%\installed\x64-windows\include\
> ```
>
> 推荐参考 RustDesk 官方仓库中的 `build_release.bat` 脚本，它包含了完整的 vcpkg 安装和环境配置命令。

#### 解决 CRT 链接冲突（关键！）

这是整个编译过程中**最容易踩的坑**。RustDesk 的 `.cargo/config.toml` 默认配置了 `+crt-static`（静态链接 CRT），但 `hwcodec` 特性依赖的 FFmpeg 库使用的是 `/MD`（动态链接 CRT）。两者冲突会导致链接阶段出现大量 `LNK2019` 错误：

```
error LNK2019: unresolved external symbol __imp_InitializeCriticalSectionEx
error LNK2019: unresolved external symbol __imp_GetSystemInfo
...（数十个类似的 __imp_* 符号未解析错误）
```

**解决方法**：编译时通过环境变量覆盖 CRT 链接方式，改用动态 CRT：

```batch
set RUSTFLAGS=-Ctarget-feature=-crt-static
```

此设置必须在同一命令行会话中执行 `cargo build` 之前完成。

#### 正确的编译命令

编译命令**必须同时开启 `hwcodec` 和 `flutter` 两个特性**，否则生成的 DLL 会缺失导出函数或硬件编解码支持：

```batch
cargo build --release --features "hwcodec,flutter" --lib -p rustdesk
```

| 参数 | 说明 |
|------|------|
| `--release` | 发布模式（优化 + 体积较小） |
| `--features "hwcodec,flutter"` | **必须同时开启两个特性** |
| `--lib` | 只编译库目标（`librustdesk.dll`） |
| `-p rustdesk` | 指定包名 |

> ⚠️ 如果只开启 `--features flutter` 而缺少 `hwcodec`，编译虽然可能通过，但生成的 DLL 缺少硬件编解码功能，远程连接时可能无法正常显示画面。
>
> ⚠️ 如果只开启 `--features hwcodec` 而缺少 `flutter`，DLL 会缺少 `rustdesk_core_main_args` 等 Flutter 桥接导出函数，导致 RustDesk 主程序无法启动。

#### 完整编译流程汇总

将以上步骤整合为一个批处理脚本，方便一键编译：

```batch
@echo off
:: ============================================================
:: RustDesk librustdesk.dll 完整编译脚本
:: ============================================================

:: 1. 激活 VS 2022 环境
call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"

:: 2. LLVM / Clang 环境
set LIBCLANG_PATH=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\Llvm\x64\bin
:: 注意：请将 14.xx.xxxxx 替换为本地实际安装的 MSVC 版本号
set BINDGEN_EXTRA_CLANG_ARGS=-isystem "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.xx.xxxxx\include"

:: 3. VCPKG
set VCPKG_ROOT=D:\vcpkg

:: 4. 解决 CRT 冲突（重要！）
set RUSTFLAGS=-Ctarget-feature=-crt-static

:: 5. 生成桥接代码
cargo install flutter_rust_bridge_codegen --version 1.80.1
flutter_rust_bridge_codegen generate

:: 6. 编译
cargo build --release --features "hwcodec,flutter" --lib -p rustdesk

echo.
echo ============================================================
echo 编译完成！产物位置：target\release\librustdesk.dll
echo ============================================================
pause
```

#### 产物验证

编译成功后，产物位于 `target\release\librustdesk.dll`。

**文件大小**：约 **32.24 MB**（Release 模式）。

**导出函数验证**：使用 `dumpbin` 检查 DLL 导出表：

```batch
dumpbin /exports target\release\librustdesk.dll
```

正常情况下应有 **352+ 个导出函数**，必须包含以下关键函数：

| 函数名 | 说明 |
|--------|------|
| `rustdesk_core_main_args` | Flutter 桥接入口，RustDesk 启动必需 |
| `wire_*` 系列函数 | Flutter ↔ Rust 通信的 wire 函数，大量存在 |
| `store_dart_post_cobject` | Dart FFI 初始化 |

如果 `dumpbin` 输出中缺少 `rustdesk_core_main_args` 或 `wire_*` 函数，说明编译时可能遗漏了 `flutter` 特性，请检查 cargo 命令参数。

---

## 验证修复

1. 安装后检查日志是否还有 OSError 1460 错误：

```powershell
Get-Content "$env:APPDATA\RustDesk\log\rustdesk_rCURRENT.log" | Select-String "OSError"
```

如果无输出，说明修复生效。

2. 在文件资源管理器中复制文件（Ctrl+C），确认 explorer.exe 不再卡死。

## 已知问题

### Flutter 引擎 + OpenGL 渲染路径偶发崩溃（与本 DLL 无关）

经过对 `rustdesk.exe.15352.dmp`（2026-06-01 02:02:20 生成）的 WinDbg 分析，崩溃调用栈如下：

```
#00 ntdll.dll+0xff349       ← RtlpHeapCorruptionErrorHandler
#01 ntdll.dll+0xff313       ← RtlpReportHeapFailure
#02 ntdll.dll+0x14762c      ← RtlpHpHeapHandleDataException
#03 opengl32.dll+0xddbf0    ← OpenGL 调用
#04 ntdll.dll+0x247b1
#05 gdi32full.dll+0x574e3   ← GDI 渲染
#06 opengl32.dll+0x71d3
...
#14 flutter_windows.dll+0x4da8fc  ← Flutter 渲染引擎
...
#29 flutter_windows.dll+0x7cacec
```

**结论**：
- 崩溃路径 `flutter_windows.dll → opengl32.dll → gdi32full.dll → ntdll 堆检测`
- `librustdesk.dll` **不在**崩溃调用栈中
- 已加载模块中只有 `rustdesk.exe` 和几个 Flutter plugin DLL
- 涉及 NVIDIA 驱动 `nvwgf2umx.dll`，与 GPU 渲染路径相关

这是 **Flutter 引擎通过 OpenGL 后端进行 GPU 渲染时的内存管理 bug**（或 NVIDIA 驱动问题），触发堆损坏，被 ntdll 堆管理器检测到后抛出 `0xc0000374`。由于崩溃不在 `librustdesk.dll` 中，本仓库的代码修复无法消除此类崩溃。

**临时解决方法**：RustDesk → 设置 → 显示 → 关闭"GPU 纹理渲染"或"硬件解码"。

**根本解决方法**：等待 RustDesk 官方更新 Flutter 版本，或 NVIDIA 更新驱动。

### 其他偶发错误（可忽略）

日志中偶尔出现：
- `Failed to connect to 192.168.x.x:21118` — RustDesk ID 服务器连接失败
- `Failed to connect to <relay>:61115` — 中继服务器连接失败

这些是网络问题（防火墙、ISP 阻塞或服务器临时不可用），与本 DLL 无关。

## 相关链接

- [RustDesk GitHub](https://github.com/rustdesk/rustdesk)
- [技术分析：Explorer 卡死根因与修复方案](技术分析-Explorer卡死根因与修复方案.md)
- [Issue #9222 - timeout of copy past](https://github.com/rustdesk/rustdesk/issues/9222)
- [PR #7217 - Fix/arboard clipboard context timeout](https://github.com/rustdesk/rustdesk/pull/7217)

## 许可

MIT
