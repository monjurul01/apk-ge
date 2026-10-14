import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'export_presets.dart';
import 'generation.dart';

/// Saving and sharing finished images.
///
/// Previously the app handed Cloudinary delivery URLs to the OS share sheet.
/// Dola URLs are short-lived signed CDN links, so everything here works from
/// the downloaded bytes instead - which also means saving works offline.
class ImageIo {
  ImageIo._();

  /// `AI Image Studio` inside the platform documents directory.
  static Future<Directory> saveDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}AI Image Studio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Filesystem-safe stem derived from the prompt.
  static String slug(String s, [int max = 48]) {
    final cleaned = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty) return 'image';
    return cleaned.length <= max ? cleaned : cleaned.substring(0, max);
  }

  static String fileNameFor(GenerationResult r, int presetIndex) {
    final stamp = r.createdAt
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final ext = ExportPresets.at(presetIndex).extensionFor(r);
    return '${slug(r.prompt)}-$stamp.$ext';
  }

  /// Writes [r] to the save directory under the given export preset.
  static Future<File> save(GenerationResult r, int presetIndex) async {
    final bytes = ExportPresets.apply(r, presetIndex);
    final dir = await saveDir();
    final file = File('${dir.path}${Platform.pathSeparator}'
        '${fileNameFor(r, presetIndex)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Hands the image to the OS share sheet via a temp file.
  static Future<void> share(GenerationResult r, int presetIndex) async {
    final bytes = ExportPresets.apply(r, presetIndex);
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}${Platform.pathSeparator}'
        '${fileNameFor(r, presetIndex)}');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: r.prompt);
  }

  /// Raw bytes under a preset, for the zip exporter and uploader.
  static Uint8List bytesFor(GenerationResult r, int presetIndex) =>
      ExportPresets.apply(r, presetIndex);
}
