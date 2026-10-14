import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'generation.dart';

/// How a finished image is written to disk.
///
/// Cloudinary used to do this server-side by splicing a transformation into
/// the delivery URL (`w_1620,h_2880,c_fill/f_jpg,q_100`). Dola returns a
/// plain CDN file with no transformation layer, so the same crop now runs
/// locally through the `image` package - which also means exports work
/// offline and no longer depend on a URL staying alive.
class ExportPreset {
  final String label;

  /// Target size, or null to keep the generated pixels untouched.
  final int? width;
  final int? height;

  /// Re-encode as JPEG at [quality] instead of keeping the source format.
  final bool asJpg;
  final int quality;

  const ExportPreset(
    this.label, {
    this.width,
    this.height,
    this.asJpg = false,
    this.quality = 100,
  });

  bool get isPassthrough => width == null && height == null && !asJpg;

  String extensionFor(GenerationResult r) {
    if (asJpg) return 'jpg';
    return switch (r.format) {
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpg',
    };
  }
}

class ExportPresets {
  ExportPresets._();

  static const List<ExportPreset> all = [
    ExportPreset('Original'),
    // The wallpaper master size carried over from the previous pipeline.
    ExportPreset('1620x2880 JPG',
        width: 1620, height: 2880, asJpg: true, quality: 100),
    ExportPreset('2000x2000 JPG',
        width: 2000, height: 2000, asJpg: true, quality: 100),
  ];

  static ExportPreset at(int index) =>
      all[index.clamp(0, all.length - 1)];

  /// Applies the preset at [index] to [result], returning the bytes to
  /// write. Falls back to the original bytes if decoding fails, so a codec
  /// edge case degrades to "saved unchanged" rather than losing the image.
  static Uint8List apply(GenerationResult result, int index) {
    final preset = at(index);
    if (preset.isPassthrough) return result.data;

    final decoded = img.decodeImage(result.data);
    if (decoded == null) return result.data;

    var out = decoded;
    final w = preset.width;
    final h = preset.height;
    if (w != null && h != null && (decoded.width != w || decoded.height != h)) {
      // Cover-fit: fill the frame and crop the overflow, matching what
      // Cloudinary's `c_fill` did, so existing exports stay consistent.
      out = _coverFit(decoded, w, h);
    }

    if (preset.asJpg) {
      return Uint8List.fromList(img.encodeJpg(out, quality: preset.quality));
    }
    return switch (result.format) {
      'png' => Uint8List.fromList(img.encodePng(out)),
      _ => Uint8List.fromList(img.encodeJpg(out, quality: preset.quality)),
    };
  }

  /// Scales [src] so it fully covers [w]x[h], then centre-crops.
  static img.Image _coverFit(img.Image src, int w, int h) {
    final scale = (w / src.width) > (h / src.height)
        ? w / src.width
        : h / src.height;
    final resized = img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
    final x = ((resized.width - w) / 2).round().clamp(0, resized.width);
    final y = ((resized.height - h) / 2).round().clamp(0, resized.height);
    return img.copyCrop(
      resized,
      x: x,
      y: y,
      width: w.clamp(1, resized.width),
      height: h.clamp(1, resized.height),
    );
  }
}
