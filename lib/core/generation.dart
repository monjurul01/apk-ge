import 'dart:typed_data';

/// How far along a single generation is. Surfaced to the UI so the
/// studio can show a meaningful line instead of a bare spinner.
enum GenerationStage {
  /// Restoring the saved session into the embedded browser.
  connecting,

  /// Waiting for the Dola composer to become interactive.
  preparing,

  /// Prompt handed to the page, waiting for the model to start.
  submitted,

  /// Dola is rendering.
  drawing,

  /// Pulling the finished image down.
  downloading,

  done,
}

extension GenerationStageLabel on GenerationStage {
  String get label => switch (this) {
        GenerationStage.connecting => 'Restoring your Dola session...',
        GenerationStage.preparing => 'Opening the Dola composer...',
        GenerationStage.submitted => 'Prompt sent, waiting for Dola...',
        GenerationStage.drawing => 'Dola is drawing...',
        GenerationStage.downloading => 'Downloading the image...',
        GenerationStage.done => 'Done',
      };
}

/// A finished generation. Deliberately provider-agnostic: nothing here
/// mirrors any single backend's response envelope, so a second provider
/// can be added without touching the UI.
class GenerationResult {
  /// Remote URL the image was served from. Dola CDN URLs are signed and
  /// expire, so [data] is the durable copy - treat this as provenance.
  final String imageUrl;

  /// The decoded image bytes. Always populated on success.
  final Uint8List data;

  final int width;
  final int height;

  /// Lowercase container format: `png`, `jpeg` or `webp`.
  final String format;

  /// Informational model label reported by the provider ('' when unknown).
  final String modelId;

  /// The prompt exactly as submitted.
  final String prompt;

  /// Correlation id for logs / error reports.
  final String requestId;

  final DateTime createdAt;

  const GenerationResult({
    required this.imageUrl,
    required this.data,
    required this.width,
    required this.height,
    required this.format,
    required this.modelId,
    required this.prompt,
    required this.requestId,
    required this.createdAt,
  });

  int get byteSize => data.lengthInBytes;

  bool get isSquare => width > 0 && width == height;

  bool get isPortrait => height > width;

  /// `1.2 MB`, `840 KB`.
  String get prettySize {
    final kb = byteSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  /// `1024 x 1536`.
  String get prettyDimensions =>
      width > 0 && height > 0 ? '$width x $height' : 'unknown size';

  GenerationResult copyWith({
    Uint8List? data,
    int? width,
    int? height,
    String? format,
  }) {
    return GenerationResult(
      imageUrl: imageUrl,
      data: data ?? this.data,
      width: width ?? this.width,
      height: height ?? this.height,
      format: format ?? this.format,
      modelId: modelId,
      prompt: prompt,
      requestId: requestId,
      createdAt: createdAt,
    );
  }
}

/// Why a generation failed. The UI branches on this to decide whether to
/// offer "sign in again", "retry", or just show the message.
enum GenerationErrorKind {
  /// No saved session, or the saved cookies no longer authenticate.
  signedOut,

  /// Dola refused because the account hit its free-tier ceiling.
  quotaExhausted,

  /// Throttled; retrying after a pause may work.
  rateLimited,

  /// The embedded page loaded but the expected controls were not found -
  /// almost always means Dola shipped a frontend change.
  pageChanged,

  /// Network / timeout.
  network,

  /// Dola serves a "not available in this country or region" wall. No
  /// amount of retrying fixes this from the current network.
  regionBlocked,

  /// Dola accepted the prompt and then refused it (content policy).
  rejected,

  unknown,
}

class GenerationException implements Exception {
  final GenerationErrorKind kind;
  final String message;

  /// Optional detail for the diagnostics sheet (selector that missed, raw
  /// error text, etc.). Never shown on the main surface.
  final String? detail;

  const GenerationException(this.kind, this.message, {this.detail});

  bool get isRateLimited => kind == GenerationErrorKind.rateLimited;

  bool get isSignedOut => kind == GenerationErrorKind.signedOut;

  /// Worth a second attempt without user intervention.
  bool get isRetryable =>
      kind == GenerationErrorKind.rateLimited ||
      kind == GenerationErrorKind.network;

  /// Short headline for the error banner.
  String get title => switch (kind) {
        GenerationErrorKind.signedOut => 'Dola session expired',
        GenerationErrorKind.quotaExhausted => 'Daily limit reached',
        GenerationErrorKind.rateLimited => 'Slow down',
        GenerationErrorKind.pageChanged => 'Dola changed its layout',
        GenerationErrorKind.network => 'Connection problem',
        GenerationErrorKind.regionBlocked => 'Dola is region-locked here',
        GenerationErrorKind.rejected => 'Prompt refused',
        GenerationErrorKind.unknown => 'Generation failed',
      };

  @override
  String toString() => message;
}

/// Everything the studio needs from an image backend. Dola is the only
/// implementation today; keeping the surface this small is what made the
/// Cloudinary removal a one-file change.
abstract class ImageGenerator {
  /// Human-readable backend name, shown in the status strip.
  String get displayName;

  /// False when there is no usable session yet, so the UI can route the
  /// user to sign-in before wasting a request.
  Future<bool> get isReady;

  /// Render [prompt]. [referenceImages] are optional source images for
  /// image-to-image; providers that cannot edit should ignore them and
  /// report that through [supportsReferenceImages].
  Future<GenerationResult> generate({
    required String prompt,
    List<Uint8List> referenceImages = const [],
    void Function(GenerationStage stage)? onStage,
  });

  bool get supportsReferenceImages;

  /// Release any embedded browser / socket owned by the generator.
  Future<void> dispose();
}
