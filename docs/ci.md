# CI 流水线（GitHub Actions）

唯一实现文件：`.github/workflows/ci.yml`。本文件是它的说明书——改 workflow 前先读这里。

流水线的每一步都直接对应 `docs/build-contract.md`（下称“契约”）：

```
scripts/ffmpeg/build-<target>.sh   →   scripts/ffmpeg/install-to-app.sh <target>
    →   flutter build <...>        →   断言产物里真有 FFmpeg（unzip -l / ls）
    →   actions/upload-artifact    →   （tag v*）GitHub Release
```

---

## 1. 触发条件

| 事件 | 条件 | 结果 |
| --- | --- | --- |
| `push` | 分支 `master` / `main` | analyze + test，4 平台构建，上传 artifact |
| `push` | tag `v*`（如 `v0.1.0`） | 同上 + `release` job 打 GitHub Release |
| `pull_request` | 任意 PR | analyze + test，4 平台构建（不发 release） |
| `workflow_dispatch` | 手动，任意分支 | 同 `push` |

并发策略：

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

PR 上新提交会取消同一 PR 的旧运行；`master` / tag 的运行**不会**被取消（发布不能被打断）。

---

## 2. 支持矩阵

| 平台 | 构建产物 | 状态 | 说明 |
| --- | --- | --- | --- |
| `android` | `rain_fui-android-arm64-v8a.apk` | ✅ 构建 | 只做 `arm64-v8a`（见 §8 限制） |
| `windows` | `rain_fui-windows-x64.zip` | ✅ 构建 | FFmpeg 在 MSYS2 MinGW64 里编 |
| `linux` | `rain_fui-linux-x64.tar.gz` | ✅ 构建 | 静态 FFmpeg，Ubuntu 24.04 构建 |
| `web` | `rain_fui-web.zip` | ✅ 构建 | Emscripten 版 `ffmpeg.wasm` |
| `ios` | — | ⏭ 跳过（可见） | 未 vendor iOS 版 FFmpeg，无签名凭据 |
| `macos` | — | ⏭ 跳过（可见） | 未 vendor macOS 版 FFmpeg，无公证凭据 |

**为什么正好是这 4 个目标**：契约 §5 只定义这 4 套 FFmpeg 产物（`linux-x64`、
`windows-x64`、`android-*`、`web`），仓库也没有 Apple 的签名 / 公证材料；这 4 个目标的
“构建 → 落地 → 打包 → 断言”链路能在没有 secrets 的情况下完整跑通。

### 为什么 iOS / macOS 是独立 job，而不是矩阵里的 `if: ${{ !matrix.skip }}`

用户最初的设想是：矩阵 6 条，iOS/macOS 带 `skip: true`，job 上加 `if: ${{ !matrix.skip }}`。
**这在 GitHub Actions 里不成立**：`jobs.<job_id>.if` 在矩阵展开**之前**求值，可用的 context
只有 `github` / `needs` / `vars` / `inputs`（[官方 Contexts 表](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts)），
引用 `matrix` 会让整个 workflow 直接被判无效：

```
Unrecognized named-value: 'matrix' in job if conditional
```

（`actionlint` 也会报 `context "matrix" is not allowed here`，见 §10 验证记录。）

因此改用等价实现，**跳过依然可见**：

```yaml
build:                     # 矩阵：android / windows / linux / web
  ...
build-unsupported:         # 矩阵：ios / macos，job 级 if 恒为假
  if: ${{ vars.BUILD_UNSUPPORTED_PLATFORMS == 'true' }}
```

- 仓库变量 `BUILD_UNSUPPORTED_PLATFORMS` 默认不存在 → job 恒跳过，UI 里
  `build (ios) — 未支持，跳过`、`build (macos) — 未支持，跳过` 两条灰显为 **skipped**，
  不会像“没配 CI”那样凭空消失。
- 把变量设为 `true` 后这两个 job 会真的启动，并**故意失败**，错误信息里写明缺什么
  （签名的东西、iOS/macOS 的 FFmpeg 产物）。这样“启用”不会得到一条欺骗性的绿灯。
- 矩阵条目里仍然保留了 `skip: true` 字段，语义自解释。

> 如果想改成“跳过 = 绿灯空跑”，只把 `if` 换成矩阵里的 `skip` 判断放在**步骤**级即可——
> 但那样 iOS 会显示成功，容易误读，所以没有这么做。

---

## 3. Secrets

**不需要任何 secret。** 具体地：

- 公开仓库 + GITHUB_TOKEN（Actions 自动注入，权限收紧到 `contents: read`；
  只有 `release` job 提升为 `contents: write`，用于创建 Release）。
- Android release 包使用**模板自带的 debug 签名**
  （`android/app/build.gradle.kts` 里 `signingConfig = signingConfigs.getByName("debug")`），
  所以能装、能跑，但**不能上架 Google Play**，也不能覆盖安装正式签名的包。
- Windows / Linux / web 产物未签名（Windows 首次运行会有 SmartScreen 提示）。
- 不使用任何第三方凭据（无 Play Store / Apple 证书 / 公证 API key）。

将来要发正式版，需要新增 secret（keystore + `key.properties`、Apple 证书、公证的
`APPLE_ID` 等）——**那是仓库 owner 的决定，本流水线不假设它们存在**。

---

## 4. 产物（artifact）

`actions/upload-artifact@v4`，保留 14 天，`if-no-files-found: error`：

| artifact 名 | 文件 | 内容 |
| --- | --- | --- |
| `rain_fui-android-arm64-v8a` | `rain_fui-android-arm64-v8a.apk` + `…-ffmpeg-version.txt` | split APK（arm64-v8a） |
| `rain_fui-windows-x64` | `rain_fui-windows-x64.zip` | `rain_fui/` 目录：`rain_fui.exe` + DLL + `ffmpeg.exe` + `LICENSES/` + `FFMPEG-VERSION.txt` |
| `rain_fui-linux-x64` | `rain_fui-linux-x64.tar.gz` | `rain_fui/` 目录：`rain_fui` + `lib/ffmpeg` + `LICENSES/` + `FFMPEG-VERSION.txt` |
| `rain_fui-web` | `rain_fui-web.zip` | `rain_fui-web/`：`index.html` + `ffmpeg/ffmpeg.{js,wasm}` + `LICENSES/` |

tag `v*` 时，`release` job 把上面 4 个包**原样**挂到 Release（不重新打包），并额外生成
`rain_fui-ffmpeg-licenses-<tag>.tar.gz`——契约 §2 要求分发二进制时同时分发
`LICENSES/ffmpeg/` 的许可证原文。若 `LICENSES/ffmpeg/` 不存在，会输出 `::warning::`
而不是让发布失败（APK 里塞不进许可证，只能以附加文件形式分发）。

---

## 5. 每个 job 做了什么

### `analyze-and-test`（ubuntu-latest，20 min）

```
checkout(fetch-depth:1, 无子模块) → flutter(stable) → cache pub → flutter pub get
→ flutter analyze → flutter test --reporter expanded
```

故意**不**拉 FFmpeg 子模块：这一步只关心 Dart。`test/` 里的集成测试在没有
`build/ffmpeg/dist/**` 时自己 skip（契约 §9.6），所以这里不需要二进制。

`flutter analyze` 默认 `--fatal-warnings`、不 `--fatal-infos`，即 warning 会红、info 不会。

### `build (<platform>)`（矩阵，`needs: analyze-and-test`）

公共步骤：

1. `actions/checkout@v4` + `submodules: recursive`（FFmpeg 源码 = submodule）
2. `subosito/flutter-action@v2`（`channel: stable`，`cache: true`）
3. `actions/cache@v4` → `${{ env.PUB_CACHE }}`（`PUB_CACHE` 被钉在 workspace 内，
   三套 OS 路径一致，键含 `hashFiles('pubspec.lock')`）
4. `flutter pub get`
5. **FFmpeg 构建缓存**（见 §6）
6. 平台工具链（见下）
7. `chmod +x scripts/ffmpeg/*.sh` + 打印 `ls -l`
8. `scripts/ffmpeg/build-<target>.sh`（缓存命中则跳过）
9. 校验 `build/ffmpeg/dist/<target>/version.txt` 存在、非空、含 `9.0.2`（契约 §9.1/§9.3）
10. 宿主可执行的目标再跑一次 `-version`（linux 额外做一次 `testsrc → null` 编码冒烟）
11. `scripts/ffmpeg/install-to-app.sh <target>`（契约 §8 的落地路径）
12. `flutter build ...`
13. **断言 FFmpeg 真在产物里**（见 §7）
14. 打包到 `build/release-artifacts/` → `actions/upload-artifact@v4`

平台工具链：

| 平台 | 工具链 |
| --- | --- |
| android | `actions/setup-java@v4`(temurin 17) + `android-actions/setup-android@v3` + `sdkmanager` 装 `ndk;28.2.13676358`、`cmake;3.22.1`；`ANDROID_NDK_HOME`/`ANDROID_NDK_ROOT`/`ANDROID_NDK` 写入 `$GITHUB_ENV`；`~/.gradle/caches`、`~/.gradle/wrapper` 缓存 |
| windows | `msys2/setup-msys2@v2`（`msystem: MINGW64`，`mingw-w64-x86_64-gcc`、`nasm`、`pkgconf`、`make`、`git`）；FFmpeg 的两步用 `shell: msys2 {0}` 跑，Flutter 构建用默认 `pwsh` |
| linux | apt: `build-essential nasm yasm pkg-config patch clang cmake ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev zip unzip file`；`flutter config --enable-linux-desktop` |
| web | `mymindstorm/setup-emsdk@v14`（`version: 6.0.13`，`actions-cache-folder`），并打印 `emcc --version` |

`NDK 28.2.13676358` 不是随手写的数字：它就是 Flutter 3.47.x 的默认 `ndkVersion`
（`flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:42`），
而 `android/app/build.gradle.kts` 用的是 `ndkVersion = flutter.ndkVersion`。


### `release`（仅 tag `v*`，ubuntu-latest，15 min）

`needs: [analyze-and-test, build]`，条件：

```yaml
if: ${{ !cancelled() && needs.build.result == 'success' && startsWith(github.ref, 'refs/tags/v') }}
```

`download-artifact@v4`（`merge-multiple: true`）→ 打许可证包 → `softprops/action-gh-release@v2`
（`files: artifacts/*`、`generate_release_notes: true`、`fail_on_unmatched_files: true`、
tag 里带 `-` 时自动标 prerelease）。

`checkout` 在这里用 `fetch-depth: 0`（生成 release notes 需要 tag 历史），不需要子模块。

---

## 6. 缓存策略

| 缓存 | 路径 | key | 何时失效 |
| --- | --- | --- | --- |
| Flutter SDK | 由 `subosito/flutter-action` 管理 | action 内部 | stable 通道更新 |
| pub | `${{ env.PUB_CACHE }}`（= `<repo>/.pub-cache`） | `pub-<os>-<hash(pubspec.lock)>` | `pubspec.lock` 变化 |
| Gradle | `~/.gradle/caches`、`~/.gradle/wrapper` | `gradle-<os>-<hash(android/**/*.gradle*, gradle-wrapper.properties)>` | Gradle/AGP 依赖变化 |
| Emscripten | `emsdk-cache`（action 管理） | setup-emsdk 内部（含 version） | emsdk 版本变化 |
| FFmpeg 构建 | `build/ffmpeg/dist`、`build/ffmpeg/ffbuild` | `ffmpeg-<EPOCH>-<os>-<target>-<submodule sha>-<hash(scripts/ffmpeg/**)>` | 子模块 commit 变 / 脚本改 / 手动 bump `FFMPEG_CACHE_EPOCH` |

FFmpeg 缓存的三条硬规则：

1. **只在精确命中时复用**，没有 `restore-keys`（部分命中的旧产物是最容易“毒化”结果的）；
2. **永不跨 OS 共享**——key 里带 `runner.os` 和 target，Linux 的 ELF 不可能被 Windows 复用；
3. `actions/cache` 默认 `post-if: success()`，**构建失败不会写缓存**，所以不会缓存半成品。

升级 emsdk / NDK / 编译器后如果缓存里的产物已经不可信，把 workflow 顶部的
`FFMPEG_CACHE_EPOCH` 从 `v1` 改成 `v2`，所有 FFmpeg 缓存一次性失效。

---

## 7. 构建后断言（“FFmpeg 真的进包了吗”）

| 平台 | 断言 |
| --- | --- |
| android | `unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 里必须有 `lib/arm64-v8a/libffmpeg_exe.so`；否则把 APK 里所有 `.so` 打出来再失败。另外对 `android:extractNativeLibs="true"` / `useLegacyPackaging` 只发 `::warning::`（那是 Lead 的 android/** 范围） |
| windows | `build/windows/x64/runner/Release/ffmpeg.exe` 存在（且 `rain_fui.exe` 也在） |
| linux | `build/linux/x64/release/bundle/lib/ffmpeg` 存在、**有可执行位**、`file` 显示 ELF、`-version` 能跑 |
| web | `build/web/ffmpeg/ffmpeg.wasm` 与 `ffmpeg.js` 存在、`build/web/index.html` 存在 |

这些路径来自契约 §8 的“落地路径 → 运行时解析”；路径变了就是契约变了，先把契约和
`install-to-app.sh` / 平台 CMake 对齐，再改这里。

**产物进入 bundle 依赖平台接线（`linux/**`、`windows/**`，Lead 维护）**：
`install-to-app.sh` 只负责把二进制放进 `linux/ffmpeg/ffmpeg` / `windows/ffmpeg/ffmpeg.exe`，
真正把它们复制进 `build/.../bundle` 的是平台 CMake（契约 §8：`install(PROGRAMS …)` /
`install(FILES …)`）。**接线没做时这两条断言会红**——这是刻意的：宁可红，也不要一个
“构建成功但包里没有 ffmpeg”的绿灯。改 assert 之前先确认契约是否变了。

`install-to-app.sh` 还支持 `--dry-run` 与别名（`linux` / `windows` / `android` / `all`），
本地想一次装全平台用 `./scripts/ffmpeg/install-to-app.sh all`。

---

## 8. 已知限制

1. **iOS / macOS 不构建**（见 §2）。没有 Apple 签名/公证材料，也没有 iOS/macOS 版 FFmpeg 产物。
2. **Android 只出 `arm64-v8a`**。契约 §5 定义了 3 个 ABI，但 FFmpeg 每个 ABI 都要独立编一遍
   （LTO 下 arm64 单 ABI 就要 ~20 min），CI 成本 ×3。arm64 覆盖绝大多数真机；
   `build-android.sh --abis arm64-v8a,armeabi-v7a,x86_64` + `install-to-app.sh android-arm64-v8a android-armeabi-v7a android-x86_64`
   + 去掉 `--split-per-abi` 的 `--target-platform` 过滤即可扩到全 ABI（同时把对应 leg 的
   `timeout` 抬到 300+ 分钟，或拆成 3 个 leg）。
3. **没有端到端转码测试**。CI 只验证二进制能跑（`-version`，linux 上再加一次
   `testsrc → null` 的编码冒烟）和它能进包；真正的转码回归要靠 `test/` 里的集成测试。
4. **Android release 用 debug 签名**，不能上架，不能覆盖已发布的正式签名包。
5. **Windows / macOS 未签名**，SmartScreen 会提示；没有安装器（只有 zip 便携包）。
6. **web 包没开 COOP/COEP**：契约 §7 明确单线程（`--disable-pthreads`），所以不需要这两个头；
   但如果将来启用 pthreads，托管它的服务器必须加头，否则 `SharedArrayBuffer` 不可用。
7. **emsdk 版本钉在 `3.1.64`**。`scripts/ffmpeg/build-web.sh` 只要求 `emcc em++ emar emranlib emnm`
   在 PATH 上（不校验版本），所以版本选错不会在脚本里报错，而是晚到 `configure`/链接阶段才炸；
   第一次跑 web leg 时请重点看这一步，必要时改 `setup-emsdk` 的 `version` 并 bump `FFMPEG_CACHE_EPOCH`。
8. **`flutter channel: stable` 不钉小版本**。本地是 3.47.8，但 CI 跟 stable 走；
   stable 升级可能改变默认 NDK / AGP 兼容区间（见 §9 的核对清单）。
9. **没有动态选择平台**：`workflow_dispatch` 没有 `inputs` 让用户只跑某个 leg；
   要么本地复现（§11），要么临时注释矩阵条目。
10. **`release` 依赖 `needs.build.result == 'success'`**：如果以后把某个 leg 改成“允许失败”
    （`continue-on-error`），发布会被静默挡掉——那时需要同步改这个条件。

---

## 9. 维护清单（升级时改哪里）

| 改动 | 要动的地方 |
| --- | --- |
| Flutter stable 升级 | 一般不用改；若默认 NDK 变了 → 改 `ANDROID_NDK_VERSION`（核对 `FlutterExtension.kt`） |
| NDK / AGP / Gradle 升级 | `ANDROID_NDK_VERSION`、`cmake;3.22.1`、`FFMPEG_CACHE_EPOCH` |
| emsdk 升级 | `setup-emsdk` 的 `version` + `FFMPEG_CACHE_EPOCH` |
| FFmpeg 子模块换 tag | 不用改（key 里的 sha 会自动变）；`FFMPEG_VERSION` 环境变量要跟着改 |
| 新增 ABI | 见 §8 第 2 条 |
| 启用 iOS / macOS | 见 §2：写真正的步骤，删掉占位 job 的 `if`/失败步骤 |
| 换 release 打包方式 | `build` job 末尾的 `Package *` 步骤 + `release` job |

---

## 10. 本地验证 workflow（不跑 Actions）

```bash
# 1) YAML 能不能解析（顺带用结构断言防止漏 job / 漏矩阵项）
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/ci.yml')); print(list(d['jobs']))"

# 2) 语义 + 表达式 + shell 检查（actionlint 会顺便调 shellcheck）
#    macOS: brew install actionlint shellcheck
#    Linux: 从 https://github.com/rhysd/actionlint/releases 下二进制
actionlint -shellcheck shellcheck .github/workflows/ci.yml
```

2026-11 实测结果（`actionlint 1.7.7` + `shellcheck 0.10.0`）：两者均 0 error / 0 warning。

> 注：`python3 -c "import yaml; yaml.safe_load(...)"` 用 YAML 1.1 解析器，会把裸 `on:`
> 解析成布尔 `True` —— 这是解析器的老毛病，不影响 GitHub（它用 YAML 1.2）。所以脚本里
> 取键时要 `'on' if 'on' in d else True`。

---

## 11. 本地复现某个 job

前置：`git submodule update --init --recursive`、Flutter stable（本地 3.47.8）。

```bash
# ---------- analyze & test ----------
flutter pub get && flutter analyze && flutter test

# ---------- linux ----------
sudo apt-get install -y build-essential nasm yasm pkg-config patch clang cmake \
     ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev zip unzip file
./scripts/ffmpeg/build-linux.sh --jobs "$(nproc)" --arch x86_64
./scripts/ffmpeg/install-to-app.sh linux-x64
flutter config --enable-linux-desktop
flutter build linux --release
test -x build/linux/x64/release/bundle/lib/ffmpeg \
  && build/linux/x64/release/bundle/lib/ffmpeg -version | head -1
tar -czf /tmp/rain_fui-linux-x64.tar.gz -C build/linux/x64/release bundle

# ---------- windows（MSYS2 MinGW64 shell 里跑前两步，pwsh 跑 flutter）----------
./scripts/ffmpeg/build-windows.sh --jobs "$(nproc)"
./scripts/ffmpeg/install-to-app.sh windows-x64
flutter build windows --release
test -f build/windows/x64/runner/Release/ffmpeg.exe

# ---------- android ----------
sdkmanager --install "ndk;28.2.13676358" "cmake;3.22.1"
export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/28.2.13676358"
./scripts/ffmpeg/build-android.sh --jobs "$(nproc)" --abis arm64-v8a --api 24
./scripts/ffmpeg/install-to-app.sh android-arm64-v8a
flutter build apk --release --target-platform android-arm64 --split-per-abi
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep libffmpeg_exe.so

# ---------- web ----------
#   需要 emsdk：source <emsdk>/emsdk_env.sh
./scripts/ffmpeg/build-web.sh --jobs "$(nproc)"
./scripts/ffmpeg/install-to-app.sh web
flutter build web --release
ls -l build/web/ffmpeg/ffmpeg.wasm
```

（本地 `install-to-app.sh` / `flutter build` 的输出目录与 CI 完全相同，因为契约 §5 把
中间物固定在 `build/ffmpeg/`，Flutter 的输出目录是标准位置。）

---

## 12. 时间预估（GitHub 托管 runner，4 vCPU）

| job | 冷缓存（无 FFmpeg 缓存） | 热缓存（FFmpeg 缓存命中） |
| --- | --- | --- |
| analyze & test | ~3 min | ~2 min |
| build (linux) | ~25 min | ~5 min |
| build (android) | ~32 min | ~8 min |
| build (windows) | ~40 min | ~10 min |
| build (web) | ~25 min | ~4 min |
| release | — | ~1 min |

一次 tag 发布总墙钟 ≈ `3 + max(各平台) ≈ 45 min`（冷）/ ≈ 12 min（热）。
超时设置：android 150、windows 180、linux 120、web 90 分钟——都比冷缓存实测留了
3～4 倍余量，避免偶发慢 runner 被打断。

> 数字是按“LTO full + 4 核”的 FFmpeg 全量编译估的（单个 ABI 的 FFmpeg configure+make
> 在 4 核上通常 15～30 min）。第一次真跑之后请用实际耗时回来修正这张表。
