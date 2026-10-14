import 'dart:typed_data';

import '../dola/dola_selectors.dart';
import '../dola/dola_session.dart';
import '../secure_store.dart';
import 'generation.dart';

/// Builds the image backend the studio talks to.
///
/// This is the only place in the app that names a concrete provider. The UI
/// depends on [ImageGenerator] alone, which is what reduced the Cloudinary
/// removal to deleting one file - and what makes swapping Dola for an
/// official API (Replicate, fal.ai, Gemini) a change to this function only.
Future<ImageGenerator> buildGenerator() async {
  final session = await DolaSessionStore.load();
  final selectors = await AppPrefs.selectors();
  return createDolaGenerator(session: session, selectors: selectors);
}

/// Hook for the Dola driver.
///
/// Returns a generator that refuses every request until the real driver is
/// wired in. Keeping the seam here means the rest of the app - every screen,
/// the batch runner, the export pipeline - compiles and runs today, and
/// enabling Dola is a single return statement.
ImageGenerator createDolaGenerator({
  required DolaSession session,
  required DolaSelectors selectors,
}) {
  return _UnconfiguredGenerator(session: session);
}

/// Stands in for a backend that has not been connected yet.
class _UnconfiguredGenerator implements ImageGenerator {
  _UnconfiguredGenerator({required this.session});

  final DolaSession session;

  @override
  String get displayName => 'Dola (not connected)';

  @override
  bool get supportsReferenceImages => false;

  @override
  Future<bool> get isReady async => false;

  @override
  Future<GenerationResult> generate({
    required String prompt,
    List<Uint8List> referenceImages = const [],
    void Function(GenerationStage stage)? onStage,
  }) async {
    throw const GenerationException(
      GenerationErrorKind.signedOut,
      'No image backend is connected yet. Open Settings to finish setting up '
      'image generation.',
    );
  }

  @override
  Future<void> dispose() async {}
}
