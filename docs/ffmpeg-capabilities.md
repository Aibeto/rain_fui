# FFmpeg 原生编码能力表

本文描述 `third_party/ffmpeg`（n9.0.2）在当前构建配置下**实际可用的编码器与封装**，
供 `lib/src/media/capabilities_data.dart` 的静态能力表与 GUI 表单使用。
所有结论来自源码，不来自运行时探测。

## 1. 构建基线

配置命令（`scripts/ffmpeg/common.sh:118-124` 定义的共享基线，加上程序裁剪）：

```
--disable-autodetect --enable-gpl --enable-version3
--disable-doc --disable-debug --disable-shared --enable-static
--enable-pic --disable-ffplay --disable-ffprobe
```

没有任何 `--enable-lib*`。后果有两条：

1. **只有 FFmpeg 自带的 native 编码器**。凡是 `configure` 里带外部库依赖的编码器全部被关闭，
   例如 `libx264_encoder_deps="libx264"`（`configure:3890`）、`libx265_encoder_deps="libx265"`
   （`configure:3894`）、`libvpx_vp9_encoder_deps="libvpx"`（`configure:3885`）、
   `libaom_av1_encoder_deps="libaom"`（`configure:3818`）、`libsvtav1_encoder_deps="libsvtav1"`
   （`configure:3871`）、`libopus_encoder_deps="libopus"`（`configure:3862`）、
   `libmp3lame_encoder_deps="libmp3lame"`（`configure:3848`）、
   `libvorbis_encoder_deps="libvorbis libvorbisenc"`（`configure:3880`）、
   `libwebp_encoder_deps="libwebp"`（`configure:3887`）。
2. **硬件编码器也全部关闭**。`--disable-autodetect` 会关掉
   `HWACCEL_AUTODETECT_LIBRARY_LIST`（`configure:2165-2183`：amf / audiotoolbox / cuda / cuvid /
   d3d11va / d3d12va / dxva2 / ffnvcodec / libdrm / nvdec / nvenc / vaapi / vdpau / videotoolbox /
   vulkan / v4l2_m2m），且没有 `--enable-vaapi` 之类的显式开关。因此 `h264_vaapi`、`hevc_nvenc`、
   `h264_videotoolbox`、`*_qsv`、`*_mediacodec`、`*_mf`、`*_at` 一律不存在。

### zlib 例外（重要）
`zlib` 属于 `EXTERNAL_AUTODETECT_LIBRARY_LIST`（`configure:2007`），按字面基线会被
`--disable-autodetect` 关掉；而 `deflate_wrapper_deps="zlib"`（`configure:3081`）。
凡是 `_select="deflate_wrapper"` 的编码器都会因此被连带关闭。

但仓库的构建脚本会在目标 sysroot 提供 `zlib.h` 时补一个 `--enable-zlib`
（`scripts/ffmpeg/build-linux.sh:86-90`、`build-android.sh:192-197`、`build-windows.sh:123-127`），
所以 **png / apng / flashsv / flashsv2 / pdv / zmbv / zlib / exr 这 8 个编码器在多数构建里是可用的**。
下文用 `†` 标记它们，并在表后注明依赖。

### 如何判定"本构建有没有 X"
`avcodec_find_encoder_by_name()` 返回 NULL 即不存在（`libavcodec/allcodecs.c:996-1006`）。
注册表本身是 configure 生成的 `libavcodec/codec_list.c`（`allcodecs.c:938`）——源码树里没有这个文件，
它是构建产物，不要指望在 checkout 里读到。

## 2. 视频编码器

容器列说明：`mov` 指 `libavformat/isom_tags.c:29` 的 `ff_codec_movvideo_tags`，`mkv` 指
`libavformat/matroska.c:27` 的 `ff_mkv_codec_tags`，`avi` 指 `libavformat/riff.c:36` 的
`ff_codec_bmp_tags`，`image2` 指 `libavformat/img2.c:29-102` 的 `ff_img_tags`。
编码器不在这些标签表里时，写 `mp4/mov` 会在写头阶段报 "Could not find tag for codec"。
Matroska 默认拒绝没有原生 CodecID 的编码，必须显式 `-allow_raw_vfw 1` 才走 VFW 兼容模式
（`matroskaenc.c:3680`、`matroskaenc.c:2039-2043`），表中不重复标注。

| `-c:v` | 产出 | 像素格式 | 类型 | 可封装容器 |
| --- | --- | --- | --- | --- |
| `a64multi` | Commodore 64 多色字符 | `gray8` | 有损（最近色） | 无常规封装 |
| `a64multi5` | 同上，扩展第 5 色 | `gray8` | 有损 | 无常规封装 |
| `alias_pix` | Alias/Wavefront PIX 图像 | `bgr24`,`gray8` | 无损 | image2 |
| `amv` | AMV 视频 | `yuvj420p` | 有损 | `-f amv` |
| `apng`† | APNG 动图 | `rgb24`,`rgba`,`rgb48be`,`rgba64be`,`pal8`,`gray8`,`gray8a`,`gray16be`,`ya16be` | 无损 | `-f apng` |
| `asv1` | ASUS V1 | `yuv420p` | 有损 | avi |
| `asv2` | ASUS V2 | `yuv420p` | 有损 | avi |
| `avrp` | Avid 1:1 10-bit RGB | `gbrp10` | 无损 | mov |
| `avui` | Avid Meridien 未压缩 | `uyvy422` | 无损 | mov |
| `bitpacked` | 位打包 10-bit | `yuv422p10` | 无损 | 无常规封装 |
| `bmp` | Windows/OS2 位图 | `bgra`,`bgr24`,`rgb565`,`rgb555`,`rgb444`,`rgb8`,`bgr8`,`rgb4_byte`,`bgr4_byte`,`gray8`,`pal8`,`monoblack` | 无损 | image2 |
| `cfhd` | GoPro CineForm HD | `yuv422p10`,`gbrp12`,`gbrap12` | 有损 | mov, avi |
| `cinepak` | Cinepak | `rgb24`,`gray8` | 有损（VQ） | mov, avi |
| `cljr` | Cirrus Logic AccuPak | `yuv411p` | 无损 | avi |
| `dnxhd` | VC-3 / DNxHD | `yuv422p`,`yuv422p10`,`yuv444p10`,`gbrp10` | 有损 | mov, mxf |
| `dpx` | DPX 图像 | `gray8`,`rgb24`,`rgba`,`abgr`,8/10/12/16-bit 变体 | 无损 | image2, mov, avi |
| `dvvideo` | DV | `yuv411p`,`yuv422p`,`yuv420p` | 有损 | dv, mov, avi |
| `dxv` | Resolume DXV | `rgba` | 有损（DXT） | mov |
| `exr`† | OpenEXR 图像 | `grayf32`,`gbrpf32`,`gbrapf32` | 无损 | image2 |
| `ffv1` | FFmpeg video codec #1 | `yuv420p`…`yuv444p16`、`yuva*`、`gray8`…`gray16`、`gbrp9`…`gbrp16`、`gbrap*`、`0rgb32`,`rgb32`,`rgb48`,`rgba64`,`ya8`,`yaf16`,`grayf16`,`gbrpf16`,`gbrpf32`,`bayer_rggb16` | 无损 | mkv, avi |
| `ffvhuff` | Huffyuv FFmpeg 变体 | `yuv420p`…`yuv444p16`、`yuva*`、`gray8`,`gray16`、`gbrp`,`gbrap`,`gbrp9`…`gbrp16`,`rgb24`,`rgb32` | 无损 | avi |
| `fits` | FITS 图像 | `gbrap16be`,`gbrp16be`,`gbrp`,`gbrap`,`gray16be`,`gray8` | 无损 | 无常规封装 |
| `flashsv`† | Flash Screen Video | `bgr24` | 无损 | flv |
| `flashsv2`† | Flash Screen Video 2 | `bgr24` | 无损 | flv |
| `flv` | Sorenson Spark / FLV1 | `yuv420p` | 有损 | flv, avi, swf |
| `gif` | GIF | `rgb8`,`bgr8`,`rgb4_byte`,`bgr4_byte`,`gray8`,`pal8` | 有损（调色板量化） | `-f gif`, mov |
| `h261` | H.261 | `yuv420p` | 有损 | avi |
| `h263` | H.263 / H.263-1996 | `yuv420p` | 有损 | mov, avi, flv |
| `h263p` | H.263+ / H.263-1998 | `yuv420p` | 有损 | avi |
| `hdr` | Radiance RGBE | `gbrpf32`,`grayf32`,`gbrapf32` | 无损 | image2 |
| `huffyuv` | Huffyuv | `yuv422p`,`rgb24`,`rgb32` | 无损 | avi |
| `jpeg2000` | JPEG 2000 | `rgb24`,`rgb48`,`gbr24p`,`gbrp9`…`gbrp16`,`gray8`…`gray16`,`yuv420p`…`yuv444p16`,`yuva*`,`rgba`,`rgba64`,`gbrap*`,`pal8`,`ya8`,`ya16` | 可无损 | mov, mkv, avi, image2 |
| `jpegls` | JPEG-LS | `bgr24`,`rgb24`,`gray8`,`gray16` | 无损 | image2, avi |
| `ljpeg` | Lossless JPEG | `bgr24`,`bgra`,`bgr0`,`yuvj420p`,`yuvj422p`,`yuvj444p`,`yuv420p`,`yuv422p`,`yuv444p` | 无损 | image2, avi |
| `magicyuv` | MagicYUV | `gbrp`,`gbrap`,`yuv422p`,`yuv420p`,`yuv444p`,`yuva444p`,`gray8` | 无损 | mov, avi |
| `mjpeg` | Motion JPEG | `yuvj420p`,`yuvj422p`,`yuvj444p`,`yuv420p`,`yuv422p`,`yuv444p` | 有损 | mov, mkv, avi, image2, mpjpeg |
| `mpeg1video` | MPEG-1 | `yuv420p` | 有损 | `-f mpeg1video`, mpegts, mkv, avi, mov |
| `mpeg2video` | MPEG-2 | `yuv420p`,`yuv422p` | 有损 | `-f mpeg2video`, mpegts, mkv, avi, mov, mxf |
| `mpeg4` | MPEG-4 Part 2 | `yuv420p` | 有损 | mp4, mov, mkv, avi, mpegts, nut |
| `msmpeg4v2` | MS MPEG-4 v2 | `yuv420p` | 有损 | avi, asf |
| `msmpeg4v3` | MS MPEG-4 v3 | `yuv420p` | 有损 | avi, asf, mov, mkv |
| `msrle` | Microsoft RLE | `pal8` | 无损 | avi, mov |
| `msvideo1` | Microsoft Video 1 | `rgb555` | 有损 | avi |
| `pam` | PAM 图像 | `rgb24`,`rgba`,`rgb48be`,`rgba64be`,`gray8`,`gray8a`,`gray16be`,`ya16be`,`monoblack` | 无损 | image2 |
| `pbm` | PBM 图像 | `monowhite` | 无损 | image2 |
| `pcx` | PCX 图像 | `rgb24`,`rgb8`,`bgr8`,`rgb4_byte`,`bgr4_byte`,`gray8`,`pal8`,`monoblack` | 无损 | image2 |
| `pdv`† | PDV（PlayDate 视频） | `monoblack` | 无损 | `-f pdv` |
| `pfm` | PFM 图像 | `gbrpf32le`,`gbrpf32be`,`grayf32le`,`grayf32be` | 无损 | image2 |
| `pgm` | PGM 图像 | `gray8`,`gray16be` | 无损 | image2 |
| `pgmyuv` | PGMYUV 图像 | `yuv420p`,`yuv420p16be` | 无损 | image2 |
| `phm` | PHM 图像 | `gbrpf32`,`grayf32` | 无损 | image2 |
| `png`† | PNG 图像 | `rgb24`,`rgba`,`rgb48be`,`rgba64be`,`pal8`,`gray8`,`gray8a`,`gray16be`,`ya16be`,`monoblack` | 无损 | image2, mov, avi |
| `ppm` | PPM 图像 | `rgb24`,`rgb48be` | 无损 | image2 |
| `prores` | Apple ProRes（anatoliy） | `yuv422p10`,`yuv444p10`,`yuva444p10` | 有损 | mov, mkv |
| `prores_aw` | Apple ProRes（aw） | 同上 | 有损 | mov, mkv |
| `prores_ks` | Apple ProRes（Kostya） | 同上 | 有损 | mov, mkv |
| `qoi` | QOI 图像 | `rgba`,`rgb24` | 无损 | image2 |
| `qtrle` | QuickTime Animation | `rgb24`,`rgb555be`,`argb`,`gray8` | 无损 | mov |
| `r10k` | AJA Kona 10-bit RGB | `gbrp10` | 无损 | mov, avi |
| `r210` | 未压缩 RGB 10-bit | `gbrp10` | 无损 | mov, avi |
| `rawvideo` | 原始像素 | 任意（不限制） | 无损 | rawvideo, avi, mov, mkv, image2, nut |
| `roq` | id RoQ | `yuvj444p` | 有损（VQ） | `-f roq` |
| `rpza` | QuickTime RPZA | `rgb555` | 有损 | mov, avi |
| `rv10` | RealVideo 1.0 | `yuv420p` | 有损 | rm, mkv |
| `rv20` | RealVideo 2.0 | `yuv420p` | 有损 | rm, mkv |
| `s302m` | SMPTE 302M（音频装进视频帧） | 无像素格式 | 无损 | mxf |
| `sgi` | SGI 图像 | `rgb24`,`rgba`,`rgb48le/be`,`rgba64le/be`,`gray16le/be`,`gray8` | 无损 | image2, mov |
| `smc` | QuickTime SMC | `pal8` | 无损（调色板 RLE） | mov |
| `snow` | Snow | `yuv420p`,`yuv410p`,`yuv444p`,`gray8` | 有损 | mkv, avi, nut |
| `speedhq` | NewTek SpeedHQ | `yuv420p`,`yuv422p`,`yuv444p` | 有损 | avi |
| `sunrast` | Sun Rasterfile | `bgr24`,`pal8`,`gray8`,`monowhite` | 无损 | image2 |
| `svq1` | Sorenson Video 1 | `yuv410p` | 有损 | mov, avi |
| `targa` | Truevision Targa | `bgr24`,`bgra`,`rgb555le`,`gray8`,`pal8` | 无损 | image2, mov, avi |
| `tiff` | TIFF 图像 | `rgb24`,`rgb48le`,`rgba`,`rgba64le`,`gray8`,`gray8a`,`gray16le`,`ya16le`,`monoblack`,`monowhite`,`yuv420p`,`yuv422p`,`yuv440p`,`yuv444p`,`yuv410p`,`yuv411p` | 无损 | image2, mov |
| `utvideo` | Ut Video | `gbrp`,`gbrap`,`yuv422p`,`yuv420p`,`yuv444p` | 无损 | avi |
| `v210` | 未压缩 4:2:2 10-bit | `yuv422p10`,`yuv422p` | 无损 | mov, avi |
| `vbn` | Vizrt Binary Image | `rgba`,`rgb24` | 无损 | image2 |
| `vc2` | SMPTE VC-2（Dirac） | `yuv420p`…`yuv444p12` | 可无损 | mkv, mov, avi, mpegts |
| `wmv1` | Windows Media Video 7 | `yuv420p` | 有损 | avi, asf |
| `wmv2` | Windows Media Video 8 | `yuv420p` | 有损 | avi, asf |
| `xbm` | XBM 图像 | `monowhite` | 无损 | image2 |
| `xface` | X-face 图像 | `monowhite` | 无损 | image2 |
| `xwd` | X Window Dump | `bgra`,`rgba`,`argb`,`abgr`,`rgb24`,`bgr24`,`rgb565*`,`bgr565*`,`rgb555*`,`bgr555*`,`rgb8`,`bgr8`,`rgb4_byte`,`bgr4_byte`,`pal8`,`gray8`,`monowhite` | 无损 | image2 |
| `y41p` | 未压缩 YUV 4:1:1 | `yuv411p` | 无损 | mov, avi |
| `yuv4` | 未压缩 packed 4:2:0 | `yuv420p` | 无损 | mov, avi |
| `zlib`† | LCL ZLIB | `bgr24` | 无损 | 无常规封装 |
| `zmbv`† | Zip Motion Blocks | `pal8`,`rgb555le`,`rgb565le`,`bgr24`,`bgr0` | 无损 | avi |

合计 88 个视频编码器（其中 8 个标 `†`，依赖 zlib）。

说明：

- 另有 `wrapped_avframe`（AVFrame 透传，无像素格式），用于 `-f null` 与 `yuv4mpegpipe` 的默认流，
  不产生真正的编码数据，不建议出现在 GUI 的编码器下拉框里。
- 没有 H.264 / H.265 / VP8 / VP9 / AV1 / WebP 编码器。它们在本仓库里全部是 `libx264`、`libx265`、
  `libvpx`、`libaom`、`libsvtav1`、`libwebp` 或硬件实现，本构建一个都没有。
- 像素格式出处举例：`png` 见 `libavcodec/pngenc.c:1300-1305`，`gif` 见 `libavcodec/gif.c:565-566`，
  `ffv1` 见 `libavcodec/ffv1enc.c:2104-2135`，`prores`/`prores_ks` 见
  `libavcodec/proresenc_anatoliy.c:950-951` 与 `proresenc_kostya.c:1033`。

## 3. 音频编码器

| `-c:a` | 产出 | 采样格式 | 类型 | 可封装容器 |
| --- | --- | --- | --- | --- |
| `aac` | AAC（LC 为主） | `fltp` | 有损 | mp4, mov, m4a, mkv, adts, mpegts, flv, nut |
| `ac3` | AC-3 | `fltp` | 有损 | ac3, mp4, mov, mkv, mpegts, vob |
| `ac3_fixed` | AC-3（定点） | `s16` | 有损 | 同上 |
| `eac3` | E-AC-3 | `fltp` | 有损 | eac3, mp4, mov, mkv, mpegts |
| `mp2` | MPEG Layer II | `s16` | 有损 | mp2, mpegts, avi, mkv, mp4 |
| `mp2fixed` | MPEG Layer II（定点） | `s16` | 有损 | 同上 |
| `flac` | FLAC | `s16`,`s32` | 无损 | flac, mkv, ogg, mp4, mov, nut |
| `alac` | Apple Lossless | `s32p`,`s16p` | 无损 | mp4, mov, m4a, mkv |
| `opus` | Opus（**实验性**） | `fltp` | 有损 | opus, ogg, mkv, webm, mp4, mpegts |
| `vorbis` | Vorbis（**实验性**） | `fltp` | 有损 | ogg, mkv, webm, nut |
| `wmav1` | Windows Media Audio 1 | `fltp` | 有损 | asf, avi |
| `wmav2` | Windows Media Audio 2 | `fltp` | 有损 | asf, avi |
| `dca` | DTS Coherent Acoustics | `s16p`,`s32p` | 有损 | dts, mp4, mov, mkv, mpegts |
| `truehd` | TrueHD | `s16p`,`s32p` | 无损 | mkv, mp4, mpegts |
| `mlp` | MLP | `s16p`,`s32p` | 无损 | mkv |
| `tta` | TTA | `u8`,`s16`,`s32` | 无损 | mkv |
| `wavpack` | WavPack | `u8p`…`s32p` | 无损 | mkv |
| `aptx` | aptX（蓝牙） | `s16p`,`s32p` | 有损 | 无常规封装 |
| `aptx_hd` | aptX HD | `s16p`,`s32p` | 有损 | 无常规封装 |
| `sbc` | SBC（蓝牙） | `s16` | 有损 | 无常规封装 |
| `g723_1` | G.723.1 | `s16` | 有损 | 无常规封装 |
| `nellymoser` | Nellymoser Asao | `flt`/`s16` | 有损 | flv, mov |
| `ra_144` | RealAudio 1.0 | `s16` | 有损 | rm, mkv |
| `dfpwm` | DFPWM1a | `u8` | 有损 | 无常规封装 |
| `pcm_s16le` 等 31 个 | PCM（见下） | `s16`/`s24`/`s32`/`f32`/`u8` 等 | 无损 | wav, avi, mov, mkv, nut, mxf, dv |
| `adpcm_*` 等 16 个 | ADPCM（见下） | `s16` | 有损（4:1 压缩） | wav, avi, mov, mkv, flv, swf |

PCM 编码器（全部 native，无外部依赖）：

`pcm_alaw` `pcm_mulaw` `pcm_u8` `pcm_s8` `pcm_s8_planar` `pcm_s16le` `pcm_s16le_planar` `pcm_s16be`
`pcm_s16be_planar` `pcm_s24le` `pcm_s24le_planar` `pcm_s24be` `pcm_s24daud` `pcm_s32le` `pcm_s32le_planar`
`pcm_s32be` `pcm_s64le` `pcm_s64be` `pcm_f32le` `pcm_f32be` `pcm_f64le` `pcm_f64be` `pcm_u16le` `pcm_u16be`
`pcm_u24le` `pcm_u24be` `pcm_u32le` `pcm_u32be` `pcm_bluray` `pcm_dvd` `pcm_vidc`

ADPCM / DPCM 编码器：

`adpcm_adx` `adpcm_argo` `adpcm_g722` `adpcm_g726` `adpcm_g726le` `adpcm_ima_amv` `adpcm_ima_alp`
`adpcm_ima_apm` `adpcm_ima_qt` `adpcm_ima_ssi` `adpcm_ima_wav` `adpcm_ima_ws` `adpcm_ms` `adpcm_swf`
`adpcm_yamaha` `roq_dpcm`

合计 25 + 31 + 16 = 72 个音频编码器。

关键约束（源码可查）：

- `opus` 只接受 48000 Hz、单声道或立体声（`libavcodec/opus/enc.c:759-761`），且带
  `AV_CODEC_CAP_EXPERIMENTAL`（`opus/enc.c:751`），必须加 `-strict -2`。
- `vorbis` 同样是实验性（`libavcodec/vorbisenc.c:1312`），必须 `-strict -2`。
- `mp2` 只支持 44100 / 48000 / 32000 / 22050 / 24000 / 16000 Hz（`mpegaudioenc.c:806`）。
- `ac3` 比特率只能取 32/40/48/56/64/80/96/112/128/160/192/224/256/320/384/448/512/576/640 kbps
  （`libavcodec/ac3tab.c:99-102`），且 `-b:a` 默认被置为 0 表示由编码器按声道数决定
  （`ac3enc.c:137-140`）。

## 4. 封装格式

| muxer | 扩展名 | 可用视频编码器 | 可用音频编码器 | 说明 |
| --- | --- | --- | --- | --- |
| `mp4` | .mp4 | mpeg4, mpeg2video, mpeg1video, h263, mjpeg, png†, prores*, dnxhd, dvvideo, msmpeg4v3, rawvideo, vc2, jpeg2000, magicyuv, cinepak, svq1, qtrle, v210, y41p, yuv4, r210, r10k, avrp, avui, dxv, dpx, targa, sgi, gif, msrle, smc, rpza, cfhd | aac, ac3, eac3, mp2, flac, alac, opus, dca, truehd, nellymoser, pcm_* | 无 `libx264` 时 `video_codec` 默认退化为 `mpeg4`（`movenc.c:9395-9396`） |
| `mov` | .mov | 同 mp4 | 同 mp4 | 与 mp4 共用 `MOVMuxContext`，选项相同 |
| `ipod` | .m4v/.m4a/.m4b | 需显式指定，默认 `h264` 不存在 | aac, alac | 做 m4a 时用 `-c:a aac`，视频轨要显式 `-c:v mpeg4` |
| `matroska` | .mkv | ffv1, ffvhuff, mpeg1video, mpeg2video, mpeg4, mjpeg, prores*, rv10, rv20, snow, vc2, rawvideo, msmpeg4v3, jpeg2000 | aac, ac3, eac3, mp2, flac, opus, vorbis, alac, dca, truehd, mlp, tta, wavpack, pcm_*, ra_144 | 无 libvorbis 时默认音频是 `ac3`（`matroskaenc.c:3720-3721`） |
| `webm` | .webm | **无**（只允许 vp8/vp9/av1，`matroska.c:110-124`） | opus, vorbis（均需 `-strict -2`） | 视频编码在本构建不可用，只能做纯音频 |
| `avi` | .avi | mpeg4, mpeg2video, mpeg1video, h263, h263p, mjpeg, png†, ffv1, huffyuv, ffvhuff, utvideo, dvvideo, rawvideo, flv, wmv1, wmv2, msmpeg4v2/v3, h261, msvideo1, cinepak, svq1, jpeg2000, jpegls, ljpeg, dpx, targa, zmbv†, v210, speedhq, vc2, asv1, asv2, cljr, roq, rpza, msrle, cfhd, y41p, yuv4, r210, r10k | pcm_*, adpcm_*, mp2, ac3, wmav1/2, g723_1, dfpwm, vorbis | 经典 AVI，索引 4 GB 限制 |
| `mpegts` | .ts/.m2t/.m2ts/.mts | mpeg1video, mpeg2video, mpeg4, vc2 | mp2, aac, ac3, eac3, dca, truehd, opus | 流类型映射见 `mpegtsenc.c:355-457` |
| `flv` | .flv | flv, h263, mpeg4 | aac, adpcm_swf, mp3（无编码器）, nellymoser | 无 libmp3lame 时默认音频是 `adpcm_swf`（`flvenc.c:1547`） |
| `gif` | .gif | gif | 无 | 选项 `loop`、`final_delay` |
| `mp3` | .mp3 | 仅封面图 | **仅 mp3**（无编码器） | 本构建无法产出 MP3 音频，见 `mp3enc.c:591` |
| `flac` | .flac | 仅封面图（png/mjpeg） | flac | 无自有选项 |
| `wav` | .wav | 无 | pcm_*, adpcm_*, mp2 | 选项 `write_bext`、`rf64` |
| `ogg` | .ogg | 无（theora 不可用） | vorbis（`-strict -2`）, opus（`-strict -2`）, flac | 选项 `page_duration` |
| `opus` | .opus | 无 | opus | 只能装 Opus |
| `ac3` | .ac3 | 无 | ac3, ac3_fixed | 只能装 AC-3 |
| `adts` | .aac/.adts | 无 | aac | AAC 裸流 |
| `image2` | 按编码器决定 | 所有图像编码器（`img2.c:29-102`） | 无 | 文件名需含 `%d` |
| `apng` | .apng | apng† | 无 | 选项 `plays`、`final_delay` |
| `nut` | .nut | 大多数 | 大多数 | 选项 `syncpoints`、`write_index` |
| `asf` | .asf/.wmv/.wma | msmpeg4v3, wmv1, wmv2, mpeg4, mjpeg 等 | wmav1/2, pcm_*, mp2 | 走 BMP/WAV 标签表（`asfenc.c:241-243`） |
| `dv` | .dv | dvvideo | pcm_s16le | 固定 DV 规格 |
| `mxf` | .mxf | mpeg2video, dnxhd | pcm_s16le, s302m | 广播封装 |
| `rawvideo` | .rgb/.yuv | rawvideo | 无 | 无选项 |
| `yuv4mpegpipe` | .y4m | rawvideo | 无 | 默认 `wrapped_avframe` |
| `ivf` | .ivf | **无**（仅 vp8/vp9/av1） | 无 | 本构建不可用 |
| `smjpeg` | — | mjpeg | pcm_s16le | 逐帧 JPEG + PCM |
| `swf` | .swf | flv | mp3（无编码器） | 只能出无声视频 |
| `h264` / `hevc` | .h264/.hevc | **无**原生编码器 | 无 | 只能封装已有码流（本仓库不适用） |

`prores*` 指 `prores`、`prores_aw`、`prores_ks` 三个名字，码流相同。

### 常用封装选项
| 选项 | 属于 | 默认 | 含义 |
| --- | --- | --- | --- |
| `-movflags +faststart` | mp4/mov/ipod | 关 | 二次 pass 把 `moov` 挪到文件头，便于边下边播（`movenc.c:98`） |
| `-movflags +frag_keyframe` | mp4/mov | 关 | 每个关键帧切一个分片，配合 `empty_moov` 做流式输出（`movenc.c:102`） |
| `-movflags +empty_moov` | mp4/mov | 关 | 初始 `moov` 留空（`movenc.c:97`） |
| `-frag_duration` / `-min_frag_duration` | mp4/mov | 0 | 分片时长上下限，微秒（`movenc.c:85`,`:120`） |
| `-movie_timescale` / `-video_track_timescale` | mp4/mov | 0（自动） | 时间基（`movenc.c:119`,`:124`） |
| `-use_editlist` | mp4/mov | -1（自动） | 是否写 edit list（`movenc.c:122`） |
| `-brand` | mp4/mov | 空 | 覆盖 major brand（`movenc.c:79`） |
| `-cluster_time_limit` | matroska/webm | -1 | 单个 cluster 的最大毫秒数（`matroskaenc.c:3676`） |
| `-cluster_size_limit` | matroska/webm | -1 | 单个 cluster 的最大字节数（`matroskaenc.c:3675`） |
| `-reserve_index_space` | matroska/webm | 0 | 预留 cues 空间（`matroskaenc.c:3673`） |
| `-live` | matroska/webm | 0 | 按直播流写，不写时长/seekhead（`matroskaenc.c:3679`） |
| `-cues_to_front` | matroska/webm | 0 | 把索引搬到文件头（`matroskaenc.c:3674`） |
| `-write_crc32` | matroska/webm | 1 | 每个 Level 1 元素写 CRC32（`matroskaenc.c:3682`） |
| `-mpegts_flags +resend_headers` | mpegts | 关 | 周期性重发 PAT/PMT（`mpegtsenc.c:2372-2373`） |
| `-mpegts_flags +pat_pmt_at_frames` | mpegts | 关 | 每个视频帧重发 PAT/PMT（`mpegtsenc.c:2376-2377`） |
| `-muxrate` | mpegts | 1（自动） | CBR 复用码率（`mpegtsenc.c:2368`） |
| `-pes_payload_size` | mpegts | 2930 | PES 最小负载（`mpegtsenc.c:2369`） |
| `-flvflags +add_keyframe_index` | flv | 关 | 追加关键帧索引元数据（`flvenc.c:1529`） |
| `-loop` | gif | 0 | 0 无限循环，-1 不循环（`gif.c:186`） |
| `-final_delay` | gif / apng | -1 / 0 | 末帧停留时长（gif 单位厘秒） |
| `-plays` | apng | 1 | 0 无限循环，1 只播一次（`apngenc.c:289`） |
| `-start_number` / `-update` / `-strftime` | image2 | 1 / 0 / 0 | 序列起始号、覆盖单文件、时间戳命名（`img2enc.c:279-281`） |
| `-write_bext` / `-rf64` | wav | 0 / never | 广播扩展块、超 4 GB 用 RF64（`wavenc.c:501`,`:506`） |
| `-page_duration` | ogg | 1000000 | 页时长，微秒（`oggenc.c:93`） |
| `-id3v2_version` / `-write_xing` | mp3 | 4 / 1 | ID3v2 版本、Xing 头（`mp3enc.c:511-515`） |

## 5. 编码器参数

规则：本节只列 `AVOption`，即 `-c:v xxx -option value` 形式的私有选项。
`-b:v`、`-q:v`、`-g`、`-bf` 等属于 `AVCodecContext` 公共字段，见第 6 节。
`-crf` **在本构建完全不存在**：它只由 `libx264/libx265/libvpx/libaom/libsvtav1/libxeve` 定义
（`libavcodec/libx264.c:1505`、`libvpxenc.c:2009`、`libaomenc.c:1546` 等），这些文件都没有被编译。

### 5.1 MPEG-1/2/4、H.263、FLV、WMV 共用选项
`mpeg1video` / `mpeg2video` / `mpeg4` / `h263` / `h263p` 共用 `FF_MPV_COMMON_OPTS`
（`libavcodec/mpegvideoenc.h:339-373`）与 `FF_MPV_COMMON_MOTION_EST_OPTS`（同文件 380-389）；
`flv` / `wmv1` / `wmv2` / `h261` / `msmpeg4*` 通过 `ff_mpv_enc_class` 拿到同一组选项
（`libavcodec/mpegvideo_enc.c:96-107`）。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `mpv_flags` | flags | `skip_rd`,`strict_gop`,`qp_rd`,`cbp_rd`,`naq`,`mv0` | 0 | MPEG 系列公共开关 |
| `b_strategy` | int | 0-2 | 0 | B 帧决策策略 |
| `b_sensitivity` | int | 1..INT_MAX | 40 | `b_strategy=1` 时的灵敏度 |
| `luma_elim_threshold` | int | INT_MIN..INT_MAX | 0 | 亮度系数置零阈值（负值连 DC 一起判） |
| `chroma_elim_threshold` | int | INT_MIN..INT_MAX | 0 | 色度系数置零阈值 |
| `qsquish` | float | 0-99 | 0 | 量化器夹紧方式，0 硬夹，1 平滑 |
| `rc_eq` | string | — | `tex^qComp` | 码率控制方程（默认值见 `ratecontrol.c:544`） |
| `rc_init_cplx` | float | -FLT_MAX..FLT_MAX | 0 | 首帧初始复杂度 |
| `rc_buf_aggressivity` | float | -FLT_MAX..FLT_MAX | 1.0 | 缓冲激进程度 |
| `lmin` / `lmax` | int | 0..INT_MAX | 236 / 3658 | Lagrange 因子上下限（`FF_QP2LAMBDA`=118，`libavutil/avutil.h:226`） |
| `skip_threshold` | int | INT_MIN..INT_MAX | 0 | 跳帧阈值 |
| `skip_cmp` | int | `sad`,`sse`,`satd`,`dct`,`psnr`,`bit`,`rd`,`zero`,`vsad`,`vsse`,`nsse`,`dct264`,`dctmax`,`chroma`,`msad` | `dctmax` | 跳帧比较函数 |
| `noise_reduction` | int | INT_MIN..INT_MAX | 0 | 降噪强度 |
| `motion_est` | int | `zero`,`epzs`,`xone` | `epzs` | 运动估计算法 |
| `mepc` | int | INT_MIN..INT_MAX | 256 | 运动估计码率惩罚补偿，256 = 1.0 |
| `intra_penalty` | int | 0..INT_MAX/2 | 0 | 帧内块惩罚 |
| `sc_threshold` | int | INT_MIN..INT_MAX | 0 | 场景切换阈值 |

除 `mpeg2video` 外，`h263`/`h263p`/`flv`/`wmv2` 没有 `b_strategy`/`b_sensitivity`/`brd_scale`
（它们不含 `FF_MPV_COMMON_BFRAME_OPTS`）。

### 5.2 `mpeg4`
编码器定义见 `libavcodec/mpeg4videoenc.c:1359-1375`，选项表在 `1340-1350`。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `data_partitioning` | bool | 0/1 | 0 | 使用数据分区 |
| `alternate_scan` | bool | 0/1 | 0 | 交替扫描表 |
| `mpeg_quant` | int | 0/1 | 0 | 用 MPEG 量化器替代 H.263 量化器 |

通用字段：`-b:v` `-q:v` `-g` `-bf` `-profile:v`（`mpeg4_sp`/`mpeg4_core`/`mpeg4_main`/`mpeg4_asp`，
`libavcodec/profiles.h:42-46`）`-pix_fmt`（只接受 `yuv420p`）`-threads` `-mbd`。
**不认 `-crf`**；恒定质量用 `-q:v 1..31`（`-q:v` 会置 `AV_CODEC_FLAG_QSCALE` 并写 `frame->quality`，
`fftools/ffmpeg_mux_init.c:1456-1459`、`fftools/ffmpeg_enc.c:797`）。

### 5.3 `mpeg2video`
选项表 `libavcodec/mpeg12enc.c:1260-1290`。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `intra_dc_precision` | int | -1..3 | -1（自动） | DC 系数精度 |
| `intra_vlc` | bool | 0/1 | 0 | 使用 MPEG-2 帧内 VLC 表 |
| `non_linear_quant` | bool | 0/1 | 0 | 非线性量化 |
| `alternate_scan` | bool | 0/1 | 0 | 交替扫描表 |
| `a53cc` | bool | 0/1 | 1 | 写入 A53 隐藏字幕 |
| `seq_disp_ext` | int | `auto`(-1)/`never`(0)/`always`(1) | `auto` | 写 sequence_display_extension |
| `video_format` | int | `component`,`pal`,`ntsc`,`secam`,`mac`,`unspecified` | `unspecified` | SDE 中的信号源格式 |
| `drop_frame_timecode` | bool | 0/1 | 0 | 丢帧时间码 |
| `scan_offset` | bool | 0/1 | 0 | 为 SVCD 预留 scan offset |
| `timecode_frame_start` | int64 | -1..INT64_MAX | -1 | GOP 起始帧号 |

可选 profile：`422`/`high`/`ss`/`snr`/`main`/`simple`（`profiles.h:48-54`）。
通用字段：`-b:v` `-q:v` `-g` `-bf` `-profile:v` `-level` `-pix_fmt`（`yuv420p` 或 `yuv422p`）`-threads`。

### 5.4 `mpeg1video`
选项表 `libavcodec/mpeg12enc.c:1253-1257`，只有 5.1 的共用组。
通用字段：`-b:v` `-q:v` `-g` `-bf` `-pix_fmt`（仅 `yuv420p`）`-threads`。无 `-profile:v`。

### 5.5 `h263` / `h263p`
`h263` 选项表 `libavcodec/ituh263enc.c:899-905`；`h263p` 在 `930-938`。

| 选项 | 类型 | 范围 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `obmc` | bool | 0/1 | 0 | 重叠块运动补偿（两者都有） |
| `mb_info` | int | 0..INT_MAX | 0 | 输出宏块信息供 RFC 2190 打包，值为最大负载 |
| `umv` | bool | 0/1 | 0 | 无限制运动矢量（仅 `h263p`） |
| `aiv` | bool | 0/1 | 0 | 替代帧间 VLC（仅 `h263p`） |
| `structured_slices` | bool | 0/1 | 0 | 每个 GOB 头写 slice 起始位置（仅 `h263p`） |

通用字段：`-b:v` `-q:v` `-g` `-pix_fmt`（仅 `yuv420p`）。两者都没有 `-bf` 与 `-profile:v`。

### 5.6 `mjpeg`
选项表 `libavcodec/mjpegenc.c:648-653`。

| 选项 | 类型 | 枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `huffman` | int | `default`(0),`optimal`(1) | `optimal` | Huffman 表策略。代码默认是 `optimal`（`mjpegenc.h:84-85`），与 `doc/encoders.texi:1262-1263` 的文字描述不一致，以代码为准 |
| `force_duplicated_matrix` | bool | 0/1 | 0 | 总是写亮度与色度矩阵，便于 RTP 流 |

通用字段：`-q:v`（1 最好）`-pix_fmt`（`yuvj*` 或 `yuv*` 的 420/422/444）`-threads`。

### 5.7 `png`†
选项表 `libavcodec/pngenc.c:1269-1281`。

| 选项 | 类型 | 范围 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `dpi` | int | 0-65536 | 0 | 写 pHYs 的每英寸点数 |
| `dpm` | int | 0-65536 | 0 | 写 pHYs 的每米点数 |
| `pred` | int | `none`,`sub`,`up`,`avg`,`paeth`,`mixed` | `paeth` | 行预测滤波器 |

通用字段：`-compression_level 0..9`（zlib 压缩级别，`avctx->compression_level`）、`-pix_fmt`。
无损格式，`-b:v`/`-q:v` 无意义。

### 5.8 `gif`
选项表 `libavcodec/gif.c:539-546`。

| 选项 | 类型 | 枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `gifflags` | flags | `offsetting`,`transdiff` | 两者都开 | 帧偏移与帧间透明检测 |
| `gifimage` | bool | 0/1 | 0 | 每帧写成独立图像 |
| `global_palette` | bool | 0/1 | 1 | 尽可能写全局调色板 |

通用字段：`-pix_fmt`（`pal8` 最省事；给 `rgb24` 会自动量化）、`-r`（帧率决定延时）。

### 5.9 `ffv1`
选项表 `libavcodec/ffv1enc.c:2049-2086`。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `slicecrc` | int | -1/1/2 | -1 | 切片 CRC，-1 自动 |
| `coder` | int | `rice`,`range_def`,`range_tab` | `rice` | 熵编码器 |
| `context` | int | 0/1 | 0 | 上下文模型，0 小、1 大 |
| `qtable` | int | `default`,`8bit`,`greater8bit` | -1（自动） | 量化表 |
| `remap_mode` | int | `auto`,`off`,`dualrle`,`flipdualrle` | -1 | 颜色通道重映射 |
| `remap_optimizer` | int | 0-5 | 3 | 重映射优化强度 |

通用字段：`-level`（FFV1 版本）、`-g`（关键帧间隔）、`-slices`、`-threads`、`-pix_fmt`。
无 `-b:v`，无损编码器。

### 5.10 `huffyuv` / `ffvhuff`
选项表 `libavcodec/huffyuvenc.c:993-1004`。`ffvhuff` 用整表，`huffyuv` 用 `options + 1`
（跳过仅 ffvhuff 的 `context`，见 `huffyuvenc.c:1006-1012`）。

| 选项 | 类型 | 枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `context` | int | 0/1 | 0 | 每帧独立 Huffman 表（仅 `ffvhuff`） |
| `non_deterministic` | bool | 0/1 | 0 | 允许 `context=1` 时多线程，牺牲可复现性 |
| `pred` | int | `left`,`plane`,`median` | `left` | 预测方式 |

通用字段：`-pix_fmt`、`-threads`。无损，无码率参数。

### 5.11 `utvideo`
选项表 `libavcodec/utvideoenc.c:644-650`。

| 选项 | 类型 | 枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `pred` | int | `none`,`left`,`median` | `left` | 帧内预测方式 |

通用字段：`-pix_fmt`（`gbrp`/`gbrap`/`yuv420p`/`yuv422p`/`yuv444p`）。

### 5.12 `prores` / `prores_aw` / `prores_ks`
`prores` 与 `prores_aw` 共用 `libavcodec/proresenc_anatoliy.c:938-941`，只有 `vendor`。
`prores_ks` 选项表在 `libavcodec/proresenc_kostya.c:972-1014`。

| 选项 | 适用 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- | --- |
| `vendor` | 三者 | string | — | `fmpg`（aw）/`Lavc`（ks） | 写入 fourcc 的厂商标识 |
| `mbs_per_slice` | `prores_ks` | int | 1-MAX_MBS_PER_SLICE | 8 | 每个 slice 的宏块数 |
| `profile` | `prores_ks` | int | `auto`,`proxy`,`lt`,`standard`,`hq`,`4444`,`4444xq` | `auto` | 编码档位 |
| `bits_per_mb` | `prores_ks` | int | 0-8192 | 0（按 profile 定） | 每宏块目标比特 |
| `quant_mat` | `prores_ks` | int | `auto`,`proxy`,`lt`,`standard`,`hq`,`default` | -1 | 量化矩阵 |
| `alpha_bits` | `prores_ks` | int | 0-16 | 16 | alpha 平面位深 |

通用字段：`-profile:v`（`Proxy`/`LT`/`Standard`/`HQ`/`4444`/`XQ`，`profiles.c:175-183`）、
`-pix_fmt`（只能 `yuv422p10`/`yuv444p10`/`yuva444p10`）、`-threads`。

### 5.13 `dnxhd`
选项表 `libavcodec/dnxhdenc.c:50-66`，另有默认值表 `qmax=1024`（`dnxhdenc.c:1339-1342`）。

| 选项 | 类型 | 枚举/范围 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `nitris_compat` | bool | 0/1 | 0 | Avid Nitris 兼容模式 |
| `ibias` | int | INT_MIN..INT_MAX | 0 | 帧内量化偏置 |
| `profile` | int | `dnxhd`,`dnxhr_444`,`dnxhr_hqx`,`dnxhr_hq`,`dnxhr_sq`,`dnxhr_lb` | `dnxhd` | 档位 |
| `qmax` | int | — | 1024 | VC-3 允许的最大量化系数 |

通用字段：`-b:v`（DNxHD 的码率由 profile + 分辨率决定，不要乱给）、`-profile:v`、`-pix_fmt`、`-threads`。

### 5.14 `dvvideo`
选项表 `libavcodec/dvenc.c:1234-1237`。

| 选项 | 类型 | 范围 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `quant_deadzone` | int | 0-1024 | 7 | 量化死区 |

通用字段：`-s`（DV 只认 720x576 / 720x480 等固定尺寸）、`-pix_fmt`（`yuv420p` PAL 或 `yuv422p` NTSC）、
`-aspect`。DV 是固定码率，`-b:v` 无意义。

### 5.15 `rawvideo`
没有任何 AVOption（`libavcodec/rawenc.c:84-93`）。唯一有意义的是 `-pix_fmt` 与 `-s`，
它们决定字节布局。配 `-f rawvideo` 或 `-f image2`（`.y`/`.raw`）。

### 5.16 `flv` / `wmv2`
两者都用 `ff_mpv_enc_class`（`libavcodec/flvenc.c:75`、`wmv2enc.c:250`），即只有 5.1 节的共用选项组，
没有私有 AVOption。通用字段：`-b:v` `-q:v` `-g` `-pix_fmt`（仅 `yuv420p`）`-threads`。

### 5.17 `aac`
选项表 `libavcodec/aacenc.c:1278-1290`，默认值表 `b=0`（`aacenc.c:1298-1301`）。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `aac_coder` | int | `twoloop`,`fast` | `twoloop` | 量化搜索算法 |
| `aac_ms` | bool | -1/0/1 | -1（自动） | 强制中/侧立体声 |
| `aac_is` | bool | -1/0/1 | 1 | 强度立体声 |
| `aac_pns` | bool | -1/0/1 | 1 | 感知噪声替换 |
| `aac_tns` | bool | -1/0/1 | 1 | 时域噪声整形 |
| `aac_pce` | bool | -1/0/1 | 0 | 强制写 PCE |

`-profile:v` 可用 `aac_low`/`aac_main`/`aac_ssr`/`aac_ltp`/`aac_he`/`aac_he_v2`/`aac_ld`/`aac_eld`
（`profiles.h:30-40`），但 native 编码器实际只产出 LC；给 HE 只会写错 profile 标记。
通用字段：`-b:a` `-ar` `-ac` `-q:a`（映射到 `global_quality`，`aacenc.c:1037`）。

### 5.18 `ac3` / `eac3`
共用 `ff_ac3_enc_options`（`libavcodec/ac3enc.c:80-135`）；`eac3` 从第 3 项开始取（`eac3enc.c:38-42`，前两项只属于 AC-3）。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `center_mixlev` / `surround_mixlev` | float | 0.0-1.0 | -4.5 dB / -6 dB | 中置、环绕下混电平（仅 AC-3） |
| `mixing_level` | int | -1..111 | -1 | 混音电平 |
| `room_type` | int | `notindicated`,`large`,`small` | `notindicated` | 房间类型 |
| `dialnorm` | int | -31..-1 | -31 dB | 对白归一化电平 |
| `dsur_mode` | int | `notindicated`,`on`,`off` | `notindicated` | Dolby Surround 标记 |
| `dmix_mode` | int | `notindicated`,`ltrt`,`loro`,`dplii` | `notindicated` | 首选立体声下混 |
| `ltrt_cmixlev` / `ltrt_surmixlev` | float | -1.0..2.0 | -1 | Lt/Rt 下混电平 |
| `loro_cmixlev` / `loro_surmixlev` | float | -1.0..2.0 | -1 | Lo/Ro 下混电平 |
| `stereo_rematrixing` | bool | 0/1 | 1 | 立体声重矩阵 |
| `channel_coupling` | int | `auto`,-1..1 | `auto` | 声道耦合 |
| `cpl_start_band` | int | `auto`,-1..15 | `auto` | 耦合起始频带 |

通用字段：`-b:a`（只能取第 3 节列出的 19 档）、`-ar`（32000/44100/48000）、`-ac`（1-6）。

### 5.19 `mp2`
没有任何私有 AVOption（`libavcodec/mpegaudioenc.c` 无 AVOption 表）。
通用字段：`-b:a`（32-384 kbps）、`-ar`、`-ac`（1-2，见 `mpegaudioenc.c:807`）。

### 5.20 `flac`
选项表 `libavcodec/flacenc.c:1713-1736`（`options[]`）。

| 选项 | 类型 | 范围/枚举 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `lpc_coeff_precision` | int | 0-MAX_LPC_PRECISION | 15 | LPC 系数精度 |
| `lpc_type` | int | `none`,`fixed`,`levinson`,`cholesky` | 自动 | LPC 算法 |
| `lpc_passes` | int | 1..INT_MAX | 2 | Cholesky 分解迭代次数 |
| `min_partition_order` / `max_partition_order` | int | -1-MAX_PARTITION_ORDER | -1 | Rice 分区阶数 |
| `prediction_order_method` | int | `estimation`,`2level`,`4level`,`8level`,`search`,`log` | -1 | 预测阶数搜索方法 |
| `ch_mode` | int | `auto`,`indep`,`left_side`,`right_side`,`mid_side` | -1 | 立体声去相关 |
| `exact_rice_parameters` | bool | 0/1 | 0 | 精确计算 Rice 参数 |
| `multi_dim_quant` | bool | 0/1 | 0 | 多维量化 |
| `min_prediction_order` / `max_prediction_order` | int | -1-MAX_LPC_ORDER | -1 | 预测阶数范围 |

`-compression_level` 是通用字段，取值 0-12（默认 5，见 `flacenc.c:344-355`），会一次性决定
`block_time_ms`、`lpc_type`、`prediction_order_method` 等；手工再设单项会覆盖它。

### 5.21 `alac`
选项表 `libavcodec/alacenc.c:623-627`。

| 选项 | 类型 | 范围 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `min_prediction_order` | int | MIN_LPC_ORDER-ALAC_MAX_LPC_ORDER | 4 | 最小预测阶 |
| `max_prediction_order` | int | 同上 | 6 | 最大预测阶 |

通用字段：`-ar` `-ac`。无损，无码率参数。

### 5.22 `opus` / `vorbis`
`opus` 选项表 `libavcodec/opus/enc.c:726-730`，默认值表 `b=0`、`compression_level=10`（同文件 739-743）。

| 选项 | 类型 | 范围 | 默认 | 含义 |
| --- | --- | --- | --- | --- |
| `opus_delay` | float | 2.5-OPUS_MAX_LOOKAHEAD | OPUS_MAX_LOOKAHEAD | 最大算法延迟，毫秒 |
| `apply_phase_inv` | bool | 0/1 | 1 | 强度立体声相位反转 |

`vorbis` 没有任何私有 AVOption（`libavcodec/vorbisenc.c` 无 AVOption 表）。
两者都必须加 `-strict -2`，否则 `avcodec_open2` 直接拒绝。

### 5.23 `pcm_s16le`
没有任何 AVOption（`libavcodec/pcm.c` 无 AVOption 表）。只有 `-ar` 与 `-ac` 有意义。

## 6. 通用参数

| 参数 | 作用层 | 说明 |
| --- | --- | --- |
| `-r` | 流级 | 输出帧率，插帧/丢帧在编码前完成 |
| `-s` | 流级 | 输出分辨率，等价于 `-vf scale=w:h` 的简化写法 |
| `-aspect` | 流级 | 样本宽高比，写进码流（`doc/ffmpeg.texi:1534`） |
| `-pix_fmt` | 流级 | 编码器输入像素格式，必须在该编码器的 `pix_fmts` 列表里 |
| `-g` | 流级 | GOP 长度，关键帧间隔（`doc/codecs.texi:89`） |
| `-bf` | 流级 | B 帧数量（`doc/codecs.texi:135`）；只有 MPEG 系支持 |
| `-b:v` / `-b:a` | 流级 | 目标码率（`doc/codecs.texi:22`） |
| `-maxrate` / `-bufsize` | 流级 | 峰值码率与码率缓冲（`doc/codecs.texi:238`,`:245`） |
| `-q:v` | 流级 | 固定量化器，置 `AV_CODEC_FLAG_QSCALE` 并写 `frame->quality`；`-qscale`/`-qscale:v` 是同一选项的旧名（`fftools/ffmpeg_opt.c:1177-1179`） |
| `-q:a` | 流级 | 音频质量，映射到 `global_quality`（`doc/codecs.texi:603`） |
| `-crf` | — | **本构建不存在**，见第 5 节开头 |
| `-profile:v` | 流级 | 档位，取值随编码器；不接受则报 "Profile not supported" |
| `-level` | 流级 | 级别，主要对 `mpeg2video` 有意义 |
| `-threads` | 流级 | 编码线程数，`0` = 自动（`doc/codecs.texi:673`） |
| `-sn` / `-an` / `-vn` | 流级 | 丢弃字幕 / 音频 / 视频流（`doc/ffmpeg.texi:2155`,`:2107`,`:1593`） |
| `-ss` / `-t` / `-to` | 输入或输出级 | 放在 `-i` 前是输入端 seek，放在后是输出端截断（`doc/ffmpeg.texi:849`,`:825`,`:837`） |
| `-vf` / `-af` | 流级 | 视频 / 音频滤镜链（`doc/ffmpeg.texi:1624`,`:2121`） |
| `-map_metadata` | 全局 | 元数据复制策略，`-1` 表示清空（`doc/ffmpeg.texi:2307`） |
| `-movflags` | 容器级 | 只有 mov/mp4/ipod 系 muxer 认，放在输出选项位置 |
| `-f` | 容器级 | 选择 muxer，决定容器（`doc/ffmpeg.texi:781`） |

判断"流级"还是"容器级"的实用规则：选项定义在 `libavcodec` 的 `AVCodecContext`
（`doc/codecs.texi`）里就是流级，定义在 `libavformat` 的 muxer 私有类里就是容器级。
`-movflags` 定义在 `libavformat/movenc.c:91`，所以它对 `-f matroska` 无意义，反之亦然。

## 7. 实现提示

1. **先按容器过滤编码器，再让用户选**。`mpeg4`/`mjpeg`/`png` 能进 mp4，`ffv1`/`huffyuv`
   不能（`isom_tags.c` 没有对应 tag），只给"mp4 + ffv1"这种组合，写头时才会报
   "Could not find tag for codec ffv1"。把第 2 节的容器列直接做成二维能力矩阵最省事。

2. **`webm` 在本构建只能出音频**。它的 `query_codec` 只放行 VP8/VP9/AV1/Vorbis/Opus
   （`matroskaenc.c:3744-3751` + `matroska.c:110-124`），而前三者没有编码器。UI 里要么隐藏
   webm 视频选项，要么在选择时直接提示"本构建不含 VP8/VP9/AV1 编码器"。

3. **`mp3` 容器是陷阱**。muxer 只接受 `AV_CODEC_ID_MP3`（`mp3enc.c:591`），而 mp3 编码器只有
   `libmp3lame`。做"音频导出"时给 `aac`（配 `-f adts` 或 m4a）、`flac`、`opus`、`pcm_s16le`，
   不要给 mp3。

4. **`-pix_fmt` 必须先过滤**。`mpeg4`/`flv`/`wmv2`/`h263` 只吃 `yuv420p`，`mpeg2video` 多一个
   `yuv422p`，prores 只吃 10-bit 4:2:2/4:4:4，`ffv1`/`jpeg2000` 几乎全吃。GUI 应把
   `-pix_fmt` 做成"该编码器允许值"的下拉框而不是自由文本；给错值会在 `avcodec_open2` 阶段失败。

5. **实验性编码器要显式提示**。`opus` 与 `vorbis` 带 `AV_CODEC_CAP_EXPERIMENTAL`，不加
   `-strict -2` 一律打不开。GUI 要么自动附加该参数，要么在卡片上标注"实验性"。

6. **不要向用户承诺 H.264/H.265/VP9/AV1/WebP**。这些在本构建里 100% 不可用，且不是"配置错误"，
   是编译期就没有。文案建议写"当前构建仅包含 FFmpeg 原生编码器，不含 libx264/libx265/libvpx/libaom/libsvtav1/libwebp"，
   而不是"暂不支持"——后者会让用户以为是运行时开关没打开。

7. **`-profile:v` 与 `-level` 只在部分编码器上成立**。`mpeg4`/`mpeg2video`/`prores*`/`dnxhd`/`aac`
   有档位表，`h263`/`flv`/`wmv2`/`gif`/`png`/`pcm_*` 没有。给不支持的编码器传 `-profile:v`
   会直接失败，不是静默忽略。

8. **`-q:v` 不是 `-crf`**。本构建没有 `-crf`；恒定质量只能靠 `-q:v`（MPEG 系 1-31，越小越好）
   或 `-b:v`。GUI 的"质量"滑杆应映射到 `-q:v`，并为每个编码器配合适量程，而不是照搬
   "CRF 0-51"。

9. **封装选项不要跨容器复用**。`-movflags` 只在 mov/mp4/ipod 生效，`-cluster_time_limit` 只在
   matroska/webm 生效。切换容器时要把上一容器的选项清掉，否则会报 "Option xxx not found"。

10. **zlib 相关编码器要运行时判定**。`png`/`apng`/`flashsv`/`flashsv2`/`pdv`/`zmbv`/`zlib`/`exr`
    在不同目标上可能被编译掉（见第 1 节）。GUI 应在启动时用
    `avcodec_find_encoder_by_name("png") == NULL` 探测一次，而不是把"总是可用"写死。
