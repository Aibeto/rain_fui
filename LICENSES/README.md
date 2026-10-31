# LICENSES/

License texts for every third-party component that this project **redistributes** (not merely uses
as a build tool). The project itself is licensed under GPL-3.0-or-later; see `../LICENSE`.

## ffmpeg/

| File | Why it is here |
| --- | --- |
| `COPYING.GPLv3` | The license of the FFmpeg binaries we build and bundle (`--enable-gpl --enable-version3` → GPL v3 or later). |
| `COPYING.LGPLv2.1` | FFmpeg's default license (LGPL v2.1+). Kept so an LGPL build of the same submodule can be redistributed without hunting for the text. |
| `LICENSE.md` | FFmpeg's own overview of which parts are LGPL vs GPL vs MIT/BSD, and what `--enable-gpl` / `--enable-version3` change. |

These are verbatim copies from the vendored submodule (`third_party/ffmpeg`, tag `n9.0.2`). They are
copied into the repository — instead of being read from the submodule at distribution time — so a
release artifact stays compliant even when the submodule is not checked out.

## Adding a new third-party component

1. Put the license text in `LICENSES/<component>/`.
2. Register it in `NOTICE` (name, version, license, link to the text).
3. If it is a library that gets linked into a bundled binary, also add it as a git submodule and
   enable it explicitly in `scripts/ffmpeg/build-*.sh` (`--disable-autodetect` is on, so nothing is
   picked up implicitly).
