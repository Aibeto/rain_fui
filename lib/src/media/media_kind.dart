/// Which part of FFmpeg a file exercises.
///
/// The encode form uses this to decide which pickers apply: a video file gets a
/// video encoder, an audio encoder and a container; an audio-only file gets no
/// video encoder at all; an image gets a video encoder plus a still-image
/// container.
library;

/// Broad media category derived from the file name.
enum MediaKind {
  /// Moving pictures, possibly with sound.
  video,

  /// Sound only.
  audio,

  /// A single still frame.
  image,

  /// Extension not recognised; the form falls back to the video layout.
  unknown,
}

/// Extension to [MediaKind], keyed without the dot and in lower case.
const Map<String, MediaKind> kExtensionKinds = <String, MediaKind>{
  // Video containers.
  'mp4': MediaKind.video,
  'm4v': MediaKind.video,
  'mkv': MediaKind.video,
  'webm': MediaKind.video,
  'mov': MediaKind.video,
  'avi': MediaKind.video,
  'flv': MediaKind.video,
  'wmv': MediaKind.video,
  'mpg': MediaKind.video,
  'mpeg': MediaKind.video,
  'm2v': MediaKind.video,
  'ts': MediaKind.video,
  'm2ts': MediaKind.video,
  'mts': MediaKind.video,
  '3gp': MediaKind.video,
  'ogv': MediaKind.video,
  'rmvb': MediaKind.video,
  'vob': MediaKind.video,
  'mxf': MediaKind.video,
  'gif': MediaKind.video,
  'y4m': MediaKind.video,
  // Audio containers and raw streams.
  'mp3': MediaKind.audio,
  'aac': MediaKind.audio,
  'm4a': MediaKind.audio,
  'flac': MediaKind.audio,
  'wav': MediaKind.audio,
  'ogg': MediaKind.audio,
  'oga': MediaKind.audio,
  'opus': MediaKind.audio,
  'wma': MediaKind.audio,
  'ac3': MediaKind.audio,
  'eac3': MediaKind.audio,
  'dts': MediaKind.audio,
  'aiff': MediaKind.audio,
  'aif': MediaKind.audio,
  'alac': MediaKind.audio,
  'ape': MediaKind.audio,
  'amr': MediaKind.audio,
  'mka': MediaKind.audio,
  'wv': MediaKind.audio,
  // Still images.
  'png': MediaKind.image,
  'jpg': MediaKind.image,
  'jpeg': MediaKind.image,
  'webp': MediaKind.image,
  'bmp': MediaKind.image,
  'tif': MediaKind.image,
  'tiff': MediaKind.image,
  'tga': MediaKind.image,
  'dpx': MediaKind.image,
  'exr': MediaKind.image,
  'ico': MediaKind.image,
  'pnm': MediaKind.image,
  'pgm': MediaKind.image,
  'ppm': MediaKind.image,
};

/// Lower-case extension of [fileName] without the dot, or an empty string.
String extensionOf(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).toLowerCase();
}

/// Guess the [MediaKind] of [fileName] from its extension.
MediaKind detectMediaKind(String fileName) =>
    kExtensionKinds[extensionOf(fileName)] ?? MediaKind.unknown;
