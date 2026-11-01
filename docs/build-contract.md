# FFmpeg 构建契约（Build Contract）

本文件是 `scripts/ffmpeg/**`、`.github/workflows/**`、平台工程（CMake / Gradle / web）与 Dart 运行时
之间的**唯一接口约定**。改动任何一端前先改这里。

## 1. 源码与版本

| 项 | 值 |
| --- | --- |
| 源码 | git submodule `third_party/ffmpeg` |
| 上游 | https://github.com/FFmpeg/FFmpeg.git |
| 锁定 | tag `n9.0.2`（`RELEASE` = `9.0.2`，libavutil 61.1.102） |
| 获取 | `git submodule update --init --recursive` |

**不允许**在 `third_party/ffmpeg` 内做任何本地修改（不打 patch）。所有定制通过 configure 参数和
`--extra-cflags/--extra-ldflags` 注入，保证 `git status` 在子模块内永远干净。

## 2. 许可证策略（硬约束）

本项目允许 FFmpeg **最严格的自由许可证** = GPL v3。因此所有目标平台的 configure 参数必须包含：

```
--enable-gpl --enable-version3
```

并且**永远禁止** `--enable-nonfree`（含任何 nonfree 组件）。产物许可证 = GPL-3.0-or-later，
与仓库根 `LICENSE` 一致。附加约束：

* 不得链接任何未在 `LICENSES/` 中登记的第三方库；当前构建只使用 FFmpeg 自带（in-tree）实现。
* 分发 FFmpeg 二进制时必须同时分发 `LICENSES/ffmpeg/` 下的许可证原文（CI 负责打包）。
* 构建脚本必须在 `configure` 后校验 `config.h`/`ffbuild/config.mak` 里 `CONFIG_GPL=yes` 且
  `CONFIG_NONFREE=no`，否则直接失败（防止参数被改坏）。

## 3. 优化策略：full LTO + 并行

| 编译器 | LTO 参数 | 说明 |
| --- | --- | --- |
| GCC ≥ 12 | `--enable-lto`（= `-flto`，full LTO） | 链接期额外追加 `-flto=auto`，让 LTO 走 make jobserver 并行 |
| Clang / LLVM | `--enable-lto=full`（= `-flto=full`） | 显式 full，禁止 thin |
| emcc（Emscripten） | `--enable-lto=full` | 默认开启；`FFMPEG_WEB_LTO=0` 可关闭 |

* `--enable-lto=<x>` 在 FFmpeg configure 中展开为 `-flto=<x>`（`configure:4720`），GCC 不接受
  `-flto=full`，所以 GCC 分支只能传裸 `--enable-lto`。
* 并行：编译用 `make -j$JOBS`（`JOBS` 默认 = `nproc` / `NUMBER_OF_PROCESSORS`），链接期的
  GCC LTO 通过 `-flto=auto` 使用同一个 jobserver。
* 提供 `FFMPEG_LTO=0` 逃生开关（仅调试用，CI 不允许关闭）。

## 4. 统一 configure 基线

所有目标共享（`scripts/ffmpeg/common.sh` 里的 `ffmpeg_base_flags`）：

```
--disable-doc --disable-debug --disable-shared --enable-static
--disable-autodetect --enable-gpl --enable-version3
--enable-pic --disable-ffplay            # ffplay 需要 SDL，不打包
```

* `--disable-autodetect` 保证构建可复现（不随宿主机装了哪些库而变）。需要外部库时必须作为
  submodule 显式加入并写入本文件。
* zlib：宿主/NDK sysroot 提供 `zlib.h` 时追加 `--enable-zlib`，否则跳过（不失败）。
* 每个目标都只构建 `ffmpeg`（+ `ffprobe`，如平台允许），不构建 `ffplay`。

## 5. 产物目录契约

一切构建中间物与产物都落在 **`build/ffmpeg/`**（已被 `.gitignore` 忽略）：

```
build/ffmpeg/ffbuild/<target>/        # 每个目标的 configure+make 中间目录
build/ffmpeg/dist/<target>/           # 最终产物（恰好这些文件）
build/ffmpeg/dist/<target>/version.txt
```

`<target>` 取值与产物文件名**必须**严格如下：

| target | 产物文件 | 备注 |
| --- | --- | --- |
| `linux-x64` | `ffmpeg`（`ffprobe` 可选） | x86_64 ELF，静态 |
| `windows-x64` | `ffmpeg.exe` | MinGW-w64 静态链接（`-static`） |
| `android-arm64-v8a` | `libffmpeg_exe.so` | 内容是可执行文件，改名以进入 `nativeLibraryDir` |
| `android-armeabi-v7a` | `libffmpeg_exe.so` | API 24，`-Wl,-z,max-page-size=16384` |
| `android-x86_64` | `libffmpeg_exe.so` | 同上 |
| `web` | `ffmpeg.js` + `ffmpeg.wasm` | Emscripten `MODULARIZE` 工厂，见 §7 |

`version.txt` 内容 = 产物 `-version` 输出的第一行（例：`ffmpeg version 9.0.2 Copyright (c) 2000-2025 the FFmpeg developers`）。
Android 无法在主机执行，写 `ffmpeg version <TAG> (cross-compiled for <target>)` 即可。

## 6. 脚本 CLI 契约

```
scripts/ffmpeg/common.sh                               # 共享函数，source 使用
scripts/ffmpeg/build.sh         [--targets LIST] [--all] [--jobs N] [--api N]
                                [--clean] [--no-install] [--dry-run] [-y]
                                                       # 交互选择目标后逐个调用 build-*.sh
scripts/ffmpeg/build-linux.sh   [--jobs N] [--clean] [--arch x86_64]
scripts/ffmpeg/build-android.sh [--jobs N] [--abis arm64-v8a,armeabi-v7a,x86_64] [--api 24]
scripts/ffmpeg/build-windows.sh [--jobs N]             # 在 MSYS2/Git-Bash 下运行
scripts/ffmpeg/build-web.sh     [--jobs N]             # 需要 emcc（emsdk）
scripts/ffmpeg/install-to-app.sh <target> [<target>…]  # 拷贝产物进平台工程目录
```

* 全部脚本 `set -euo pipefail`，可重复执行（幂等），失败返回非 0。
* `build.sh` 只是编排层：不带参数且 stdin 是终端时打印编号菜单并询问要构建哪些目标
  （支持 `1 4`、`2-4`、`linux`、`android`、`web`、`all`），选完后按顺序调用对应的
  `build-<target>.sh`，默认再调 `install-to-app.sh <target>`；CI 不依赖它，仍直接调用
  单目标脚本。
* 环境变量：`FFMPEG_SRC`（默认 `third_party/ffmpeg`）、`FFMPEG_DIST`（默认 `build/ffmpeg/dist`）、
  `JOBS`、`FFMPEG_LTO`（默认 1）。
* 脚本必须自检前提（`git submodule` 是否初始化、`nasm`/`emcc`/NDK 是否存在），给出可操作的报错。
* **脚本不得修改 `third_party/ffmpeg` 内的受版本控制文件**；out-of-tree 构建（`build/ffmpeg/ffbuild/...`）。

## 7. web 产物 ABI（Dart 通过 worker 调用的唯一约定）

FFmpeg 9 的 `ffmpeg` 程序在 configure 里声明 `ffmpeg_deps="avcodec avfilter avformat threads"`
（`configure:4377`），且 `fftools/ffmpeg_sched.c:415` 为每个 demux/decode/filter/encode/mux 任务
无条件调用 `pthread_create()`。单线程 wasm 里这必然失败（`pthread_create() failed: Not supported`），
只能做 `-version`/`-formats` 这类检查，**无法转码**——那不是“平台可调用”。所以 web 走线程化构建：

configure：`--enable-pthreads`（即不加 `--disable-pthreads`），其余与 §4 相同。
链接 ABI：

```
-pthread -sPROXY_TO_PTHREAD=1 -sPTHREAD_POOL_SIZE=8 -sPTHREAD_POOL_SIZE_STRICT=0
-sPTHREAD_POOL_DELAY_LOAD=1 -sEXIT_RUNTIME=1
-sMODULARIZE=1 -sEXPORT_NAME=createFFmpegCore -sINVOKE_RUN=0
-sENVIRONMENT=web,worker -sALLOW_MEMORY_GROWTH=1 -sFORCE_FILESYSTEM=1
-sEXPORTED_FUNCTIONS=_main,_malloc,_free
-sEXPORTED_RUNTIME_METHODS=FS,callMain,ccall,cwrap
-sSTACK_SIZE=5242880 -sASSERTIONS=0
-sINITIAL_MEMORY=67108864 -sMAXIMUM_MEMORY=2147483648
```

三条硬要求，任何一条不满足都会卡死或拿到假退出码：
1. `-sPROXY_TO_PTHREAD=1`：`main()` 必须跑在 pthread 上，否则主 worker 被 FFmpeg 阻塞，
   emscripten 的 proxied calls（`print`/`printErr`、线程引导）没人服务，`init`/`run` 直接死锁。
2. `-sEXIT_RUNTIME=1`：只有 `EXIT_RUNTIME` 才能通过 `Module.onExit(status)` 拿到退出码；
   PROXY 模式下 `callMain()` 立刻返回 `0`，**不能**当退出码用。
3. 调用方不得覆盖 `self.onmessage`（`ffmpeg.js` 用赋值式安装 own handler），必须用
   `addEventListener`，且把 URL 是 `web/ffmpeg/ffmpeg_worker.js` 的 pthread worker 识别为
   `self.name === 'em-pthread'` 只加载核心。

产物是 `ffmpeg.js` 和 `ffmpeg.wasm` 两个文件：Emscripten 6 不再生成独立的 pthread worker
脚本，它用加载自己的那个 URL（也就是 `web/ffmpeg/ffmpeg_worker.js`）去 `new Worker(...)`
起线程。

**运行前提：页面必须 cross-origin isolated**（`Cross-Origin-Opener-Policy: same-origin` +
`Cross-Origin-Embedder-Policy: require-corp`），否则没有 `SharedArrayBuffer`，wasm 无法初始化。
`web/ffmpeg/ffmpeg_bridge.js` 在 init 前检查 `globalThis.crossOriginIsolated`，为假时返回
`{ok:false, error:'cross-origin isolation required: send COOP/COEP headers'}`，
Dart 侧把它显示为 `unavailableReason`，而不是抛一个看不懂的 wasm 错误。

## 8. 平台落地位置（`install-to-app.sh` 的输出，均被 git 忽略）

| target | 落地路径（相对仓库根） | 运行时解析 |
| --- | --- | --- |
| `linux-x64` | `linux/ffmpeg/ffmpeg` | CMake `install(PROGRAMS …)` → `<bundle>/lib/ffmpeg`（这是**文件**，不是目录） |
| `windows-x64` | `windows/ffmpeg/ffmpeg.exe` | CMake `install(FILES …)` → 与 `rain_fui.exe` 同级 |
| `android-*` | `android/app/src/main/jniLibs/<abi>/libffmpeg_exe.so` | `nativeLibraryDir` === `android/app/src/main/jniLibs` 打包解压目录 |
| `web` | `web/ffmpeg/ffmpeg.js`、`web/ffmpeg/ffmpeg.wasm` | `web/ffmpeg/ffmpeg_worker.js` 内 `importScripts('ffmpeg.js')` |

Android 必须保持 `android:extractNativeLibs="true"` + `useLegacyPackaging = true`，否则
`libffmpeg_exe.so` 不会被解压成可执行文件。

## 9. 验收（CI 与本地一致）

1. `scripts/ffmpeg/build-<target>.sh` 退出码 0，产物齐全且 `version.txt` 非空。
2. `scripts/ffmpeg/install-to-app.sh <target>` 把文件放到 §8 的位置。
3. 宿主可执行的目标：`./build/ffmpeg/dist/<target>/ffmpeg -version` 必须打印 `9.0.2`。
4. Android：`flutter build apk --release --target-platform android-arm64` 后，APK 内
   `lib/arm64-v8a/libffmpeg_exe.so` 存在（CI 用 `unzip -l` 断言）。
5. web：`flutter build web --release` 后 `build/web/ffmpeg/{ffmpeg.js,ffmpeg.wasm}` 都存在，
   且在带 COOP/COEP 头的服务器上能真实转码一次（见 `docs/ffmpeg-build.md`）。
6. 桌面端集成测试：`REAL_FFMPEG=<built binary> flutter test test/real_binary_test.dart` 通过（未设置 `REAL_FFMPEG` 时自动 skip）。
