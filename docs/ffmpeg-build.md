# FFmpeg builds for rain_fui

All FFmpeg binaries used by the Flutter app are produced by the scripts in
`scripts/ffmpeg/`. The authoritative interface (artifact names, configure
baseline, web ABI, install locations) is [`docs/build-contract.md`](build-contract.md);
this document explains how to run the builds, what they need, and the measured
results on the development host.

The FFmpeg source lives in the `third_party/ffmpeg` submodule (tag `n9.0.2`,
RELEASE `9.0.2`, libavutil 61). The scripts never write inside the submodule:
every build is out-of-tree in `build/ffmpeg/ffbuild/<target>/`.

## Layout

| Path | Purpose |
| --- | --- |
| `third_party/ffmpeg/` | FFmpeg source (submodule, read-only for us) |
| `build/ffmpeg/ffbuild/<target>/` | configure + make tree per target |
| `build/ffmpeg/dist/<target>/` | final artifact(s) + `version.txt` |
| `scripts/ffmpeg/common.sh` | shared helpers (flags, LTO, license check) |
| `scripts/ffmpeg/build-*.sh` | one script per target |
| `scripts/ffmpeg/install-to-app.sh` | copy artifacts into the app trees |

Targets and artifacts:

| Target | Artifact | `file(1)` type |
| --- | --- | --- |
| `linux-x64` | `build/ffmpeg/dist/linux-x64/ffmpeg` | ELF 64-bit x86-64 executable |
| `windows-x64` | `build/ffmpeg/dist/windows-x64/ffmpeg.exe` | PE32+ x86-64 executable |
| `android-arm64-v8a` | `.../android-arm64-v8a/libffmpeg_exe.so` | ELF 64-bit AArch64 shared object |
| `android-armeabi-v7a` | `.../android-armeabi-v7a/libffmpeg_exe.so` | ELF 32-bit ARM shared object |
| `android-x86_64` | `.../android-x86_64/libffmpeg_exe.so` | ELF 64-bit x86-64 shared object |
| `web` | `.../web/ffmpeg.js` + `ffmpeg.wasm` | WebAssembly + JS loader |

Every dist directory also gets a `version.txt` whose first line is the FFmpeg
`-version` banner, e.g.

```
ffmpeg version n9.0.2 Copyright (c) 2000-2026 the FFmpeg developers
```

For cross-compiled targets that cannot be executed on the build host, the
scripts fall back to `ffmpeg version <tag> (cross-compiled for <target>)`, and
for web the banner is captured from the Node smoke test when it succeeds.

## Prerequisites

Common: `bash`, GNU `make`, a C compiler, and the submodule checked out
(`git submodule update --init third_party/ffmpeg`).

| Host / target | Packages / tools |
| --- | --- |
| Linux native | `gcc` (>= 12 for LTO + `-flto=auto`), `make`, `nasm`, `zlib` headers |
| Windows build from Linux | `mingw-w64-gcc` (`x86_64-w64-mingw32-gcc`, `ar`, `strip`), `nasm`, `wine` (optional, only to run the exe) |
| Windows build on Windows | MSYS2 / Git-Bash with `mingw-w64-x86_64-gcc`, `make`, `nasm`, `pkg-config` |
| Android | Android NDK r27+ (tested r28c `28.2.13676358`), `make`; no gradle needed |
| Web | Emscripten SDK at `~/emsdk` (`source ~/emsdk/emsdk_env.sh`), `node` (smoke test only) |

`nasm`/`yasm` are optional. If neither is on `PATH` (the scripts also probe
`$HOME/.local/bin`), the build adds `--disable-x86asm`; the result is correct
but x86 SIMD is slower. Keep `nasm` installed for release Linux/Windows builds.

The Android NDK is located in this order: `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`,
`~/Android/Sdk/ndk/28.2.13676358`, the newest `~/Android/Sdk/ndk/*`, then
`/opt/android-ndk`. Override with `ANDROID_NDK_HOME` when needed. The scripts
use API 24 (Flutter's `minSdk`) and the NDK's clang wrappers.

## Quick start

```bash
# Interactive: pick the targets (numbers, ranges, names, or "a" for all)
scripts/ffmpeg/build.sh

# Same selection without the prompt (CI-friendly); --dry-run just prints
scripts/ffmpeg/build.sh --targets 1,4 --dry-run
scripts/ffmpeg/build.sh --all

# Individual targets still work on their own:
# Linux (native, LTO)
scripts/ffmpeg/build-linux.sh --jobs "$(nproc)"

# Android, one ABI or several
scripts/ffmpeg/build-android.sh --abis arm64-v8a
scripts/ffmpeg/build-android.sh --abis arm64-v8a,armeabi-v7a,x86_64

# Windows: run on MSYS2/Git-Bash, or cross-compile from Linux
scripts/ffmpeg/build-windows.sh

# Web (sources ~/emsdk/emsdk_env.sh automatically when emcc is missing)
scripts/ffmpeg/build-web.sh

# Copy into the app trees expected by CMake / Gradle / the web loader
scripts/ffmpeg/install-to-app.sh all
```

All scripts accept `--jobs N`, are idempotent (a second run reuses the build
tree and re-links only what changed) and take `--clean` to delete that target's
build tree first. `bash -n` is enough to syntax-check them.

## Script reference

`scripts/ffmpeg/build-linux.sh [--jobs N] [--clean] [--arch x86_64]`
: native x86_64 build with the host compiler. `CC=clang` switches to Clang.
  Adds `--enable-zlib` when `zlib.h` is available, `--disable-x86asm` when nasm
  is missing, then verifies that the produced binary's version line carries
  `9.0.2`, `n9.0.2` or the submodule's short commit (a tag-less checkout only
  has the commit).

`scripts/ffmpeg/build.sh [--targets LIST] [--all] [--jobs N] [--api N] [--clean] [--no-install] [--dry-run] [-y]`
: the interactive front door: prints the target menu and asks which ones to
  build, then runs the matching `build-<target>.sh` and (unless `--no-install`)
  `install-to-app.sh` for each. Selection accepts menu numbers (`1 4`), ranges
  (`2-4`), names/aliases (`linux`, `android`, `web`, `all`) and is validated in
  the main shell so a typo fails fast. Non-interactive callers must pass
  `--targets`/`--all`; `--dry-run` prints the exact commands without running
  them. It is a convenience wrapper only — CI keeps calling the per-target
  scripts directly, so nothing in the pipeline depends on this file.

`scripts/ffmpeg/build-android.sh [--jobs N] [--abis a,b,c] [--api 24] [--clean]`
: one build per ABI with the NDK clang toolchain. Defaults to all three
  Flutter-supported ABIs (`arm64-v8a,armeabi-v7a,x86_64`). The ELF executable is
  renamed to `libffmpeg_exe.so` so Android packages it as a native library. Link
  flags include `-Wl,-z,max-page-size=16384` for 16 KB page-size devices. NEON
  `.S` assembly is kept for ARM; only x86 assembly can be disabled. `version.txt`
  uses the fallback banner because the binary cannot run on the build host.

  | ABI | Device / use | Notes |
  | --- | --- | --- |
  | `arm64-v8a` | almost all current real phones/tablets | primary target; build this in CI |
  | `armeabi-v7a` | older 32-bit ARM devices | slower, larger relative overhead; needed for `flutter build apk` defaults |
  | `x86_64` | Android emulators (and some Chromebooks) | fastest emulator ABI on x86 hosts |

  CI builds all three ABIs, one parallel job per ABI (`build-android` matrix in
  `.github/workflows/ci.yml`): the three cross-compiles are independent, so
  splitting them shortens the wall clock to the slowest ABI instead of summing
  them. Locally `build.sh --targets android` does the same thing sequentially.

`scripts/ffmpeg/build-windows.sh [--jobs N] [--clean] [--arch x86_64]`
: detects its host. On MSYS2/Git-Bash it builds natively; on Linux it
  cross-compiles with `--target-os=mingw32 --arch=x86_64
  --enable-cross-compile --cross-prefix=x86_64-w64-mingw32-`. Link flags add
  `-static` so the exe does not need libwinpthread/libgcc DLLs. When `wine` is
  available the exe is smoke-tested with `wine ffmpeg.exe -version`.

`scripts/ffmpeg/build-web.sh [--jobs N] [--clean] [--no-smoke]`
: builds the static libraries with `emconfigure`/`emmake`, then links the FFmpeg
  CLI frontend (`fftools/ffmpeg*.c`, `cmdutils.c`, `opt_common.c`, `graph/`,
  `textformat/`, the resource objects) into a single Emscripten module with the
  ABI from contract §7: `createFFmpegCore` `MODULARIZE` factory,
  `-sINVOKE_RUN=0`, `FS` + `callMain` exported. The build is **threaded**
  (`--enable-pthreads`, `-pthread`, `-sPTHREAD_POOL_SIZE=8`,
  `-sPTHREAD_POOL_SIZE_STRICT=0`) because FFmpeg 9's CLI scheduler needs real
  pthreads to transcode. Emscripten 6 does **not** emit a separate pthread
  worker script: it re-uses the URL it was loaded from, i.e.
  `web/ffmpeg/ffmpeg_worker.js`, so that file detects `self.name ===
  'em-pthread'` and only loads the core there. The page must be cross-origin
  isolated (COOP/COEP, see below). **`--disable-avdevice` must stay off**: the `lavfi` input device lives
  in libavdevice, so removing libavdevice makes every `-f lavfi ...` command
  fail with `Unknown input format: 'lavfi'`. The link step therefore includes
  `-lavdevice`, and the fftools objects are deleted and rebuilt on every run
  because they embed `CONFIG_AVDEVICE` from `config.h` (make does not track that
  dependency).

  The Node smoke test does two runs: `callMain(['-version'])` must print
  `9.0.2`, and a real pipeline
  `-f lavfi -i testsrc2=duration=0.2:size=64x64:rate=5 -f null -` must start
  and exit. A failing smoke test only warns by default (the `-version` case is
  the contract check); set `FFMPEG_WEB_STRICT_SMOKE=1` to make either failure
  fatal — recommended in CI once the threading question below is settled.

`scripts/ffmpeg/install-to-app.sh [--dry-run] <target>...`
: copies artifacts to the contract §8 locations, creating directories and
  preserving modes (executables `0755`, web files `0644`). Accepts individual
  targets plus the shorthands `linux`, `windows`, `android`, `all`. Idempotent;
  prints every source/destination pair and refuses to install a target without a
  non-empty `version.txt`.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `FFMPEG_SRC` | `<repo>/third_party/ffmpeg` | FFmpeg source tree |
| `FFMPEG_BUILD_ROOT` | `<repo>/build/ffmpeg` | build trees root |
| `FFMPEG_DIST` | `<repo>/build/ffmpeg/dist` | artifact root |
| `JOBS` | `nproc` / `NUMBER_OF_PROCESSORS` | parallel make jobs |
| `FFMPEG_LTO` | `1` | `0` disables LTO (debug only) |
| `FFMPEG_WITH_FFPROBE` | `0` | `1` also builds `ffprobe` |
| `FFMPEG_EXTERNAL_LIBS` | `0` | `1` links third-party codecs and hardware back ends |
| `FFMPEG_DEPS_PREFIX` | `build/ffmpeg/deps/<target>` | where `build-deps.sh` installs them |
| `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` | auto-detect | NDK location |
| `EMSDK` | `~/emsdk` | Emscripten SDK location |

## Optional third-party libraries

The default build is native-only: `--disable-autodetect` with no `--enable-lib*`,
so the encoders are the ones FFmpeg ships itself. That keeps the binary small and
the build reproducible, but it also means `libx264`, `libaom-av1`, `libsvtav1`,
`libopus` and the hardware encoders are absent.

`FFMPEG_EXTERNAL_LIBS=1` changes that. `scripts/ffmpeg/external-libs.sh` probes
what is actually installed and emits only flags whose dependency resolves:

| Library | Flag | Probe |
| --- | --- | --- |
| libopus | `--enable-libopus` | `pkg-config opus` |
| libvorbis | `--enable-libvorbis` | `pkg-config vorbisenc` |
| libvpx | `--enable-libvpx` | `pkg-config vpx` |
| x264 / x265 | `--enable-libx264` / `--enable-libx265` | `pkg-config x264` / `x265` |
| libaom | `--enable-libaom` | `pkg-config aom` |
| SVT-AV1 | `--enable-libsvtav1` | `pkg-config SvtAv1Enc` |
| LAME | `--enable-libmp3lame` | `pkg-config mp3lame` |
| libwebp | `--enable-libwebp` | `pkg-config libwebp` |
| NVENC | `--enable-ffnvcodec --enable-nvenc` | `ffnvcodec/nvEncodeAPI.h` in the prefix |
| VAAPI | `--enable-vaapi` | `pkg-config libva` |
| QSV | `--enable-libvpl` | `pkg-config vpl` |
| AMF | `--enable-amf` | AMF headers (Windows only) |
| MediaCodec | `--enable-jni --enable-mediacodec` | Android target only |

`--disable-autodetect` turns `ffnvcodec` off as well, which is why the NVENC
line names it explicitly; without it configure stops at
`nvenc requested, but not all dependencies are satisfied: ffnvcodec`.

zlib is built per target as well: mingw and emscripten do not ship it, and
without it png, apng, zmbv, exr, flashsv, flashsv2, pdv and the matching
decoders silently disappear from that platform's build.

Building only writes `build/ffmpeg/dist/`; the Flutter trees the app actually
loads (`linux/ffmpeg/`, `windows/ffmpeg/`, `android/app/src/main/jniLibs/`,
`web/ffmpeg/`) are updated by `scripts/ffmpeg/install-to-app.sh`. Skipping that
step is invisible at runtime: the app starts, the probe succeeds, and the codec
list is simply the previous binary's. `python3 tool/check_packaged.py` compares
the two sets by hash and fails when they diverge; every build script now prints
the install command when it finishes.

`python3 tool/check_parity.py` compares all five builds against the Linux one and
reports encoder or decoder names that differ, ignoring hardware back ends and
libraries the project does not build. It is the guard against a platform quietly
losing codecs; the current run reports `parity ok`.

Libraries the sysroot does not provide come from `scripts/ffmpeg/build-deps.sh`.
It builds the same recipes for a desktop target and for the cross targets, so a
platform is never stuck with fewer encoders just because its libraries happened
to be missing on the build machine:

```text
scripts/ffmpeg/build-deps.sh --only nvcodec,lame            # linux-x64 (default)
scripts/ffmpeg/build-deps.sh --target android-arm64-v8a \
    --only x264,lame,opus,ogg,vorbis,vpx,webp
scripts/ffmpeg/build-deps.sh --target windows-x64 \
    --only x264,lame,opus,ogg,vorbis,vpx,webp
FFMPEG_EXTERNAL_LIBS=1 scripts/ffmpeg/build-linux.sh
```

The dependency prefix is `build/ffmpeg/deps/<target>`, so a cross build needs its
own prefix (`android-arm64-v8a`, `windows-x64`, …) built with that target's `CC`,
`CFLAGS`, `LDFLAGS` and `HOST`.

Cross builds must not read the host's pkg-config: a host `libaom.pc` would add
`--enable-libaom` and then link x86-64 libraries into an Android binary. For any
target other than `linux`, the probe runs `pkg-config` with
`PKG_CONFIG_LIBDIR=<prefix>/lib/pkgconfig` and an empty `PKG_CONFIG_PATH`, so only
the target prefix counts; `build-android.sh` and `build-windows.sh` export the
same `PKG_CONFIG_LIBDIR` so FFmpeg's own configure sees the same view. Two
consequences worth knowing:

* Android with no dependencies installed ends up with exactly
  `--enable-jni --enable-mediacodec`, which is enough for MediaCodec.
* NVENC is enabled from headers alone on Linux, but a cross build needs a real
  `ffnvcodec.pc`; with headers only, configure fails its `LoadLibrary`
  dependency check. Windows therefore has no NVENC in the cross build: run
  `build-deps.sh` on Windows itself (MSYS2) so the `.pc` exists, or point
  `FFMPEG_DEPS_PREFIX` at a prefix that has one.

Three pkg-config details cost real time and are handled inside the script, kept
here because they look like FFmpeg bugs when they bite:

* `opus.pc` from a source archive has no git tag to read and reports version 0,
  which fails FFmpeg's `opus >= 1.1` check; the recipe rewrites the version.
* Static archives need their reference libraries on the `Libs:` line, not in
  `Libs.private`: `-lm` for opus/vorbis/vpx/webp, `-logg` for libvorbis,
  `-lvorbis` for libvorbisenc, `-lsharpyuv` for libwebp. bionic has no separate
  `libpthread`, so `-lpthread` is only added for non-Android targets.
* libvpx's `armv7-android-gcc` target hands `-march=armv7-a` to the host
  assembler under this NDK, so armeabi-v7a builds libvpx as `generic-gnu`
  (portable C, no NEON) instead of failing outright.

Builds verified on this machine (FFmpeg 9.0.2 source, `FFMPEG_EXTERNAL_LIBS=1`,
`FFMPEG_LTO=0`, NDK r28c for Android, mingw-w64 for Windows):

| target | artifact | size | software encoders |
|---|---|---|---|
| linux-x64 | `dist/linux-x64/ffmpeg` | 33 077 664 B | libx264/libx265/libvpx/libaom/libsvtav1/libopus/libvorbis/libmp3lame/libwebp + nvenc/qsv/vaapi |
| android-arm64-v8a | `dist/android-arm64-v8a/libffmpeg_exe.so` | 38 008 656 B | libx264/libx265/libvpx/libsvtav1/libopus/libvorbis/libmp3lame/libwebp + 11 MediaCodec |
| android-armeabi-v7a | `dist/android-armeabi-v7a/libffmpeg_exe.so` | 32 753 584 B | same software set (libvpx without NEON) + MediaCodec |
| android-x86_64 | `dist/android-x86_64/libffmpeg_exe.so` | 48 433 744 B | same software set + MediaCodec |
| windows-x64 | `dist/windows-x64/ffmpeg.exe` | 53 296 654 B | libx264/libx265/libvpx/libsvtav1/libopus/libvorbis/libmp3lame/libwebp |
| web | `dist/web/ffmpeg.wasm` | 32 901 039 B | libx264/libx265/libvpx/libaom/libsvtav1/libopus/libvorbis/libmp3lame/libwebp + zlib (wasm) |

The wasm target links its own copies of most of the same libraries. Emscripten needs a
few extra fixes, all handled in the scripts: x264 is configured with
`--disable-asm` and its generated `config.mak` loses the `-m64` that would pick
wasm64, x264's `sched_getaffinity` probe is routed to its Android fallback, and
the manual `emcc` link in `build-web.sh` appends `pkg-config --libs` for the
enabled libraries plus `-lmp3lame`, `-lwebpmux` and `-lwebpdemux` because those
archives carry no usable `.pc` entry. libaom comes from the Debian source
mirror because `aomedia.googlesource.com` is unreachable from this network; for
wasm it is configured with `-DAOM_TARGET_CPU=generic`, and x265's CMake needs
`EMSCRIPTEN` added to its "32-bit x86" branch or em++ rejects `-march=i686`.
Web therefore carries the same encoder set as the other targets, HEVC included.
Linking x265 makes binaryen's `wasm-opt` fail with "popping from empty stack",
and emcc 6 dropped `--no-wasm-opt`, so the web link runs with `-O0` (objects are
still compiled `-O3`); the module is larger, and `WEB_LINK_OPT` overrides the
link level if a future emsdk fixes the optimiser.

## LTO and parallelism

The contract requires LTO for release builds. `common.sh` selects the right
spelling per compiler:

* GCC: `--enable-lto` at configure time and `-flto=auto` in `--extra-ldflags`
  (uses the make jobserver, so the LTO link is parallel too; requires GCC >= 12).
* Clang and Emscripten: `--enable-lto=full` (FFmpeg expands it to `-flto=full`).

`FFMPEG_LTO=0 scripts/ffmpeg/build-linux.sh` is the debugging escape hatch: no
LTO flags, faster iteration, slower binary.

Compiles scale with `--jobs`, but the final LTO link is memory-hungry: peak RSS
grows with the number of partitions and can exceed the machine's RAM when
`--jobs` is set to the core count on a 15 GB box. The measured builds below use
20 jobs for native Linux; if a link is killed by the OOM killer, re-run with
`--jobs 4..8` (the compile objects are reused, only the link re-runs).

## License compliance

Every target is configured with `--enable-gpl --enable-version3` and never with
`--enable-nonfree`. After configure, `common.sh` asserts that
`CONFIG_GPL=yes`, `CONFIG_VERSION3=yes` and `CONFIG_NONFREE` is not `yes` (it
inspects both `ffbuild/config.mak` and `config.h`), aborting otherwise. The
resulting binaries are GPLv3-or-later; the app must ship the corresponding
source (the `third_party/ffmpeg` submodule at the recorded tag plus the
configure line stored in `configure.args` in each build tree). External
libraries are limited to zlib (zlib license, GPL-compatible) when the sysroot
provides it; `--disable-autodetect` prevents accidentally picking up anything
else.

`--disable-ffplay` is always on; the CLI programs built are `ffmpeg` and,
optionally, `ffprobe`.

## Measured results

Host: Arch/CachyOS, 20 cores, 15 GB RAM, gcc 16.2.1, clang 23.1.4, nasm 2.16.03,
NDK r30, Emscripten 6.0.13. Times are wall-clock for a clean build tree.

| Target | Command | Jobs | Wall time | Artifact | Size |
| --- | --- | --- | --- | --- | --- |
| `linux-x64` | `build-linux.sh` | 20 | 8m44s | `dist/linux-x64/ffmpeg` | 34,152,880 B |
| `android-arm64-v8a` | `build-android.sh --abis arm64-v8a` | 12 | 15m45s | `dist/android-arm64-v8a/libffmpeg_exe.so` | 23,958,408 B |
| `android-armeabi-v7a` | `build-android.sh --abis armeabi-v7a` | 8 | 11m40s | `dist/android-armeabi-v7a/libffmpeg_exe.so` | 21,814,220 B |
| `android-x86_64` | `build-android.sh --abis x86_64` | 8 | 13m12s | `dist/android-x86_64/libffmpeg_exe.so` | 29,476,064 B |
| `windows-x64` | `build-windows.sh` (mingw cross) | 8 | 13m45s | `dist/windows-x64/ffmpeg.exe` | 32,986,638 B |
| `web` | `build-web.sh` | 14 | 7m38s | `dist/web/ffmpeg.js` + `ffmpeg.wasm` | 70,827 B + 18,900,829 B |

The Android and Windows builds ran concurrently on the same 20-core host, so
each wall time includes some contention (v7a and x86_64 ran together with the
web rebuild in the last round). Android spends roughly half of its time in the
single `ld.lld` LTO-full link. The Android builds used NDK r30
(`30.0.16248370`, clang 21) because `ANDROID_NDK_HOME`/`ANDROID_NDK_ROOT` were
set to `/opt/android-ndk`; NDK r28c works identically when selected explicitly.
The web time includes the first-run generation of Emscripten's LTO system
libraries (`libc.a`, compiler-rt, ...) — later runs reuse that cache and link
faster.

Verification for the native build:

```
$ build/ffmpeg/dist/linux-x64/ffmpeg -version | head -1
ffmpeg version n9.0.2 Copyright (c) 2000-2026 the FFmpeg developers
$ file build/ffmpeg/dist/linux-x64/ffmpeg
ELF 64-bit LSB pie executable, x86-64, ..., stripped
```

Android (`file` + 16 KB page check):

```
$ file build/ffmpeg/dist/android-arm64-v8a/libffmpeg_exe.so
ELF 64-bit LSB pie executable, ARM aarch64, ..., for Android 24, built by NDK r30, stripped
$ llvm-readelf -l .../libffmpeg_exe.so | grep LOAD
  LOAD ... R E 0x4000
  LOAD ... RW  0x4000
```

Windows (static, no mingw runtime DLLs; wine smoke test):

```
$ file build/ffmpeg/dist/windows-x64/ffmpeg.exe
PE32+ executable for MS Windows 5.02 (console), x86-64, 12 sections
$ x86_64-w64-mingw32-objdump -p .../ffmpeg.exe | grep 'DLL Name'
  bcrypt.dll, GDI32.dll, KERNEL32.dll, api-ms-win-crt-*.dll   # UCRT, Windows 10+
$ wine build/ffmpeg/dist/windows-x64/ffmpeg.exe -version | head -1
ffmpeg version n9.0.2 Copyright (c) 2000-2026 the FFmpeg developers
```

The mingw build uses the UCRT by default (gcc 16 toolchain); it runs on
Windows 10/11. For Windows 7/8 support, build with a MSVCRT-targeted mingw
toolchain and re-run `build-windows.sh`.

GCC 16 emits `-Wstringop-overflow` warnings while LTO-compiling a few
FFmpeg sources (`avstring.c`, `mjpegenc.c`, `rv60dec.c`, `aacsbr_template.c`,
...). They are GCC false positives from cross-TU inlining and do not fail the
build.

## macOS: universal binary, ad-hoc signing, sandbox

**Bash 4 or newer is required** (Homebrew's `bash`, not `/bin/bash` 3.2). The
scripts use `mapfile` and expand arrays that may be empty, which bash 3.2 rejects
under `set -u` — with 3.2 the very first dependency build fails with
`cross[@]: unbound variable`. `common.sh` now checks the version up front, and the
CI leg installs Homebrew bash and puts it first on `PATH`.

The **x86_64 slice needs `nasm`** (FFmpeg's configure refuses x86 without it, and
aom/libvpx assemble with it); `build-macos.sh` and `build-deps.sh --target
macos-x64` both check for it up front instead of failing deep inside a recipe.
`--arch arm64` builds the native slice alone.

Some of the pinned dependency sources predate the current toolchains, which is
why the recipes patch them rather than patching clang:

* LAME 3.100 rewrites `memcpy` to `bcopy` when its configure finds `bcopy`; macOS
  no longer declares it, so the recipe passes `ac_cv_func_bcopy=no`.
* libvorbis 1.3.7 hard-codes `-force_cpusubtype_ALL` in its `*-*-darwin*` CFLAGS
  and modern `ld` rejects it, so the recipe strips the flag from `configure`.
* x265's `.pc` names the C++ runtime; on macOS that is `libc++`, not libstdc++.
* libvpx must be configured with a **versioned** darwin target
  (`arm64-darwin20-gcc`, `x86_64-darwin20-gcc`). The unversioned
  `arm64-darwin-gcc` is libvpx's legacy iOS spelling: its `arm*` code path
  replaces `CC`/`CXX` with `xcrun --sdk iphoneos` compilers and pushes the
  iPhoneOS `-isysroot` and `-miphoneos-version-min` into the flags, which then
  fight the macOS ones we pass in and kill the toolchain probe. The unversioned
  `x86_64-darwin-gcc` is worse: it is not in 1.15's `all_platforms` at all, so
  configure dies with `Unrecognized toolchain`. `darwin20` is macOS 11, matching
  the default `MACOSX_DEPLOYMENT_TARGET`; the `*-darwin2[0-3]-*` branch only
  contributes `-arch`.

macOS is the only target whose artifact is signed by the build itself. On Apple
Silicon an unsigned (or wrongly signed) executable does not launch, and every
universal build carries an arm64 slice, so `build-macos.sh` always ends with
`codesign --force --sign -`, and the app build re-signs the copy it embeds.

```bash
scripts/ffmpeg/build-deps.sh --target macos-arm64     # dependency prefix per arch
scripts/ffmpeg/build-deps.sh --target macos-x64
scripts/ffmpeg/build-macos.sh --jobs 8                # both arches → lipo → dist/macos/ffmpeg
scripts/ffmpeg/install-to-app.sh macos                # → macos/ffmpeg/ffmpeg
flutter build macos --release                         # Runner's "Embed ffmpeg" phase copies + signs
```

Each architecture gets its own tree (`build/ffmpeg/ffbuild/macos-arm64`,
`…/macos-x64`) and its own dependency prefix (`build/ffmpeg/deps/macos-*`).
Both are always configured with `--enable-cross-compile --sysroot`, even when
the arch matches the host: configure must not probe the target by running it.

What the macOS build adds on top of the shared flags:

* `--enable-videotoolbox --enable-audiotoolbox`. `--disable-autodetect` turns
  both off, and then `h264_videotoolbox`, `hevc_videotoolbox` and
  `prores_videotoolbox` simply do not exist.
* No `nvenc`, `vaapi`, `libvpl`, `amf` or `mediacodec`. Only `linux`/`windows`
  can emit those, so a Homebrew `libva` in the prefix cannot leak in.

### Sandbox and drag-and-drop

`macos/Runner/*.entitlements` deliberately does **not** enable App Sandbox. A
sandboxed app cannot `exec` the bundled helper (the child process inherits the
sandbox, and the file access extensions the drop/pickers grant are not
transferable), so the feature set that makes this app useful — run the bundled
`ffmpeg`, read the file the user dragged in, write to `~/Downloads/rain_fui` —
needs either no sandbox or a signed helper with `com.apple.security.inherit`.

What the entitlements do keep:

* `com.apple.security.files.user-selected.read-write` — the open panels and the
  `desktop_drop` drag events both hand over user-selected files;
* `com.apple.security.files.downloads.read-write` — the default output directory;
* `com.apple.security.cs.allow-jit` / `network.server` in the debug profile only,
  because the Flutter debug shell needs them.

Dropping files on the window is wired through `desktop_drop` (it has a macOS
implementation) and the drop affordance in the UI is gated on
`supportsDropTarget`, which is true on macOS.

## Web target: ABI and limitations

> The web entry points are currently commented out (see `docs/ci.md` §2 and
> `scripts/ffmpeg/build-web.sh`): no artifact is produced, but the recipe, the
> worker bridge and this section are kept verbatim for when web comes back.

The web artifacts follow contract §7 exactly: `ffmpeg.js` + `ffmpeg.wasm`, a
`createFFmpegCore` `MODULARIZE` factory, `-sINVOKE_RUN=0`, `FS`/`callMain`/
`ccall`/`cwrap` exported, `-sENVIRONMENT=web,worker`, no SharedArrayBuffer and
no COOP/COEP requirement. Verified with Node 26:

```
$ WEB_SMOKE_ARGS='["-version"]' node smoke-test.cjs
ffmpeg version n9.0.2 Copyright (c) 2000-2026 the FFmpeg developers
built with emcc (Emscripten ...) 6.0.13
```

What the build **can** do (verified): print the banner, list formats/codecs/
filters, parse `-f lavfi` input (libavdevice is linked, so `Input #0, lavfi ...`
works), and evaluate filter graphs up to the point where the job scheduler
starts.

What it **cannot** do with a single-threaded wasm build: actually transcode.
FFmpeg 9's `fftools/ffmpeg_sched.c` starts one pthread per demuxer/decoder/
filter/encoder/muxer task (`task_start()` → `pthread_create()` unconditionally,
no `HAVE_THREADS` guard). Emscripten's non-pthread libc links an ENOSYS stub, so
a real pipeline stops with:

```
[vost#0:0/wrapped_avframe @ ...] pthread_create() failed: Not supported
Conversion failed!
```

(exit status `-28`). This is a structural property of FFmpeg 9's CLI, not a flag
mistake: upstream `configure` even encodes it — `ffmpeg_deps` includes
`threads`, so the `ffmpeg` program is normally not buildable without a thread
backend. Our web build bypasses that guard by configuring
`--disable-programs` and linking the CLI frontend manually, which is what lets
`-version` work at all.

Options if browser-side transcoding becomes a requirement:

1. **Threaded wasm (real fix, contract change).** Configure FFmpeg with
   pthreads and link with Emscripten pthreads (`-pthread`,
   `-sPTHREAD_POOL_SIZE=...`), serving with `Cross-Origin-Opener-Policy:
   same-origin` + `Cross-Origin-Embedder-Policy: require-corp` so
   `SharedArrayBuffer` is available. This changes the §7 ABI (needs a worker
   bootstrap and COOP/COEP headers) and roughly doubles wasm size; it must be
   agreed in `docs/build-contract.md` first.
2. **Different web engine.** Drive libavcodec/libavfilter from a small custom
   wasm entry point instead of the `ffmpeg` CLI (the CLI's scheduler is the
   blocker, not the libraries).
3. **Older FFmpeg for web only.** FFmpeg 6.x fftools does not require the new
   scheduler; this violates the "one version everywhere" rule and loses 9.0
   codecs.
4. **Keep as-is** if the web target is for inspection/metadata only; set
   `FFMPEG_WEB_STRICT_SMOKE=0` (default) so the lavfi smoke case is a warning.

Web-specific data handling: the build has **no network support**
(`--disable-network`), so it cannot open URLs; it also cannot read local files
by path — the caller must `FS.writeFile()` bytes into the in-memory filesystem
first, and any output must be read back with `FS.readFile()`. There is no
persistent storage (MEMFS only); `-y` overwrites inside that in-memory FS.

## Troubleshooting

* **`nasm not found`** — the build continues with `--disable-x86asm`; install
  `nasm` (or build it into `~/.local/bin`) for full x86 SIMD.
* **LTO link OOM / killed** — lower `--jobs` and re-run; objects are cached.
* **`emcc: command not found`** — the script sources `$EMSDK/emsdk_env.sh`
  automatically; set `EMSDK` if the SDK is not at `~/emsdk`.
* **NDK not found** — set `ANDROID_NDK_HOME` to the NDK root.
* **`version.txt` says `n9.0.2` or `946fcce`** — FFmpeg's `version.sh` uses
  `git describe` inside the submodule, so the banner carries the tag name, and a
  checkout without tags (CI's submodule) carries the bare commit instead. Both
  satisfy the contract: the assertions accept tag, `n`-prefixed tag or short
  commit.
* **A dependency fails with no output** — `build-deps.sh` writes every recipe's
  configure/make output to `build/ffmpeg/deps/logs/<target>/<dep>.log` and, when
  a step fails, prints the last 120 lines of that log before exiting. Before
  this, a failure surfaced as a bare `Error: Process completed with exit code 1`
  in CI: the recipes silence their output, and libvpx's configure prints its
  `die` messages to **stdout**, so the diagnosis was thrown away with the log.
* **Android 16 KB pages** — the link flags already set
  `-Wl,-z,max-page-size=16384`; verify with
  `llvm-readelf -l libffmpeg_exe.so | grep LOAD` (alignment `0x4000`).
* **Web module cannot find the wasm** — the shipped `ffmpeg.js` is built for
  `-sENVIRONMENT=web,worker`; serve `ffmpeg.js` and `ffmpeg.wasm` from the same
  directory. The module is threaded, so the page **must** be cross-origin
  isolated (`Cross-Origin-Opener-Policy: same-origin` +
  `Cross-Origin-Embedder-Policy: require-corp`) or `SharedArrayBuffer` is
  missing and `init()` refuses early with a cross-origin-isolation hint.

## CI notes

The scripts are the CI interface: no Gradle/CMake flags are needed to produce
the artifacts, and `install-to-app.sh` is the only step that writes into
`linux/`, `windows/`, `android/` or `web/`. Typical job:

```bash
scripts/ffmpeg/build-linux.sh
scripts/ffmpeg/build-android.sh --abis arm64-v8a   # one CI leg per ABI
scripts/ffmpeg/build-web.sh
scripts/ffmpeg/install-to-app.sh linux android web
```

`configure.args` next to each build tree records the exact configure line for
reproducibility and license auditing.

CI always builds with the third-party libraries, so every leg runs:

```bash
scripts/ffmpeg/build-deps.sh --target <deps>          # cached dependency prefix
FFMPEG_EXTERNAL_LIBS=1 FFMPEG_DEPS_TARGET=<deps> \
  scripts/ffmpeg/build-<platform>.sh
```

`<deps>` is `linux-x64`, `windows-x64`, `web-wasm` (the dist directory is still
`web`), or `android-<abi>`. The three Android ABIs are three separate parallel
jobs and never share a dependency prefix.

Two CI-specific details:

* `FFMPEG_LTO=0`. LTO only lengthens the link on a throwaway runner.
* The web link option follows the link list: `-O0` once x265 is linked (binaryen's
  `wasm-opt` cannot parse that module and emcc 6 dropped `--no-wasm-opt`), `-O3`
  otherwise. `WEB_LINK_OPT` is an escape hatch, not something CI sets.

A build is only accepted when the encoders are really inside it, which is what
`python3 tool/check_expected_encoders.py --target <t> --expect …` asserts; and
`python3 tool/check_packaged.py --only <t>` asserts the app tree got that exact
binary (a build without `install-to-app.sh` leaves the old one in place and is
otherwise invisible).

### Toolchain assumptions the scripts no longer make

Three assumptions were baked in and each one broke a CI leg, so they are now
probed instead:

* **A native build has no `--host`.** `build_x264` used to pass
  `--host "$HOST"`, which aborts under `set -u` when `HOST` is unset; configure
  guesses the host by itself for `linux-*`.
* **MSYS2 may ship binutils without the triple prefix.** `windows-x64` picks
  `x86_64-w64-mingw32-ar` when it exists and falls back to plain `ar`/`ranlib`/
  `windres`; the same choice decides x264's `--cross-prefix` (empty prefix means
  "use the tools on `PATH`").
* **nvenc only exists where a CUDA driver can exist.** `--enable-nvenc` and
  `--enable-ffnvcodec` are emitted for `linux` and `windows` only, and
  `build-deps.sh` skips nv-codec-headers for `android-*`/`web-wasm`; on wasm a
  stray `ffnvcodec.pc` in the prefix used to abort configure with
  "nvenc requested, but not all dependencies are satisfied".
