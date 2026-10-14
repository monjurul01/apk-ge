import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

import 'generation.dart';

/// Pulls finished images that were produced outside the app into the
/// session gallery.
///
/// This is the manual half of the "Dola tab + Import" flow: the user
/// generates in the embedded browser exactly as they would in Chrome, saves
/// the result with the site's own download button, and then imports the
/// file here. Nothing is scraped and no request is forged - the app only
/// reads files the user chose.
///
/// Imported images join the same [GenerationResult] pipeline as generated
/// ones, so export presets, metadata writing, ZIP export and upload all
/// work on them without a special case.
class ImportedImages {
  ImportedImages._();

  /// Formats the `image` package can decode for us.
  static const extensions = ['png', 'jpg', 'jpeg', 'webp'];

  /// Opens the OS file picker and decodes everything the user selected.
  ///
  /// Returns an empty list when the picker was cancelled. Files that cannot
  /// be decoded are reported in [failures] rather than thrown, so one bad
  /// file never discards a good selection.
  static Future<ImportOutcome> pick({String prompt = ''}) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );
    } catch (e) {
      return ImportOutcome(const [], ['Could not open the file picker: $e']);
    }
    if (picked == null || picked.files.isEmpty) {
      return const ImportOutcome([], []);
    }

    final results = <GenerationResult>[];
    final failures = <String>[];

    for (final f in picked.files) {
      final name = f.name;
      try {
        var bytes = f.bytes;
        // Desktop pickers often hand back a path instead of bytes.
        if (bytes == null && f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        }
        if (bytes == null) {
          failures.add('$name: no readable bytes');
          continue;
        }
        final r = fromBytes(bytes, fileName: name, prompt: prompt);
        if (r == null) {
          failures.add('$name: not a readable PNG, JPEG or WebP');
          continue;
        }
        results.add(r);
      } catch (e) {
        failures.add('$name: $e');
      }
    }
    return ImportOutcome(results, failures);
  }

  /// Decodes [bytes] into a [GenerationResult], or null when the bytes are
  /// not a supported image.
  static GenerationResult? fromBytes(
    Uint8List bytes, {
    required String fileName,
    String prompt = '',
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final stamp = DateTime.now();
    return GenerationResult(
      // Provenance, not a fetchable URL: these bytes came off the disk.
      imageUrl: 'file:$fileName',
      data: bytes,
      width: decoded.width,
      height: decoded.height,
      format: _formatOf(bytes, fileName),
      modelId: 'imported',
      prompt: prompt.trim().isEmpty ? _promptFromName(fileName) : prompt.trim(),
      requestId: 'import-${stamp.microsecondsSinceEpoch}',
      createdAt: stamp,
    );
  }

  /// Sniffs the container from the magic bytes, falling back to the
  /// extension. The extension lies often enough that bytes come first.
  static String _formatOf(Uint8List b, String name) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'jpeg';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'webp';
    }
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpeg',
    };
  }

  /// A readable stand-in prompt so imported images still get sensible file
  /// names and metadata input when the user did not type one.
  static String _promptFromName(String fileName) {
    var stem = fileName;
    final dot = stem.lastIndexOf('.');
    if (dot > 0) stem = stem.substring(0, dot);
    stem = stem.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return stem.isEmpty ? 'Imported image' : stem;
  }
}

/// What one import run produced.
class ImportOutcome {
  final List<GenerationResult> images;

  /// Human-readable reasons for the files that were skipped.
  final List<String> failures;

  const ImportOutcome(this.images, this.failures);

  bool get isEmpty => images.isEmpty && failures.isEmpty;
}
