import 'dart:convert';

/// CSS selectors and host patterns the Dola driver uses to find controls in
/// the embedded page.
///
/// Dola is a consumer product with no public API and no stability contract:
/// a frontend deploy can rename every class overnight. Everything the driver
/// depends on therefore lives in this one overridable object, persisted in
/// preferences and editable from Settings, so a breakage is a text edit
/// rather than a new build.
///
/// Each field is a *comma-free list* of candidate selectors tried in order,
/// because Dola ships different markup to desktop and mobile layouts.
class DolaSelectors {
  /// Where the image composer lives.
  final String chatUrl;

  /// The prompt input. Dola uses a contenteditable div on desktop and a
  /// plain textarea in its mobile layout, so both shapes are covered.
  final List<String> composer;

  /// The submit control.
  final List<String> sendButton;

  /// Container that holds generated images in the transcript.
  final List<String> resultImage;

  /// Elements whose appearance means "this prompt was refused".
  final List<String> refusal;

  /// Anything that only renders for a signed-out visitor.
  final List<String> loginWall;

  /// Hostname fragments that identify a real generated-image URL, used to
  /// ignore avatars, icons and sprite sheets in the transcript.
  final List<String> imageHostHints;

  const DolaSelectors({
    this.chatUrl = 'https://www.dola.com/chat/create-image',
    this.composer = const [
      'textarea[data-testid="chat_input_input"]',
      'div[contenteditable="true"][role="textbox"]',
      'textarea[placeholder]',
      'div[contenteditable="true"]',
    ],
    this.sendButton = const [
      'button[data-testid="chat_input_send_button"]',
      'button[type="submit"]',
      'button[aria-label*="end" i]',
      'div[data-testid*="send" i][role="button"]',
    ],
    this.resultImage = const [
      'img[data-testid*="image" i]',
      '[class*="message" i] img',
      'main img',
    ],
    this.refusal = const [
      '[class*="refus" i]',
      '[class*="violation" i]',
    ],
    this.loginWall = const [
      'button[data-testid="login_button"]',
      '[class*="login-guide" i]',
    ],
    this.imageHostHints = const [
      'byteimg.com',
      'ciciai.com',
      'bytetos.com',
      'ibytedtos.com',
      'bytepluscdn.com',
      'dola.com',
    ],
  });

  static const defaults = DolaSelectors();

  /// How long to wait for the model to produce an image before giving up.
  /// Generous: Dola queues free-tier requests behind paid ones.
  static const generationTimeout = Duration(minutes: 4);

  /// How long to wait for the composer to become interactive.
  static const readyTimeout = Duration(seconds: 45);

  DolaSelectors copyWith({
    String? chatUrl,
    List<String>? composer,
    List<String>? sendButton,
    List<String>? resultImage,
    List<String>? refusal,
    List<String>? loginWall,
    List<String>? imageHostHints,
  }) {
    return DolaSelectors(
      chatUrl: chatUrl ?? this.chatUrl,
      composer: composer ?? this.composer,
      sendButton: sendButton ?? this.sendButton,
      resultImage: resultImage ?? this.resultImage,
      refusal: refusal ?? this.refusal,
      loginWall: loginWall ?? this.loginWall,
      imageHostHints: imageHostHints ?? this.imageHostHints,
    );
  }

  Map<String, dynamic> toJson() => {
        'chatUrl': chatUrl,
        'composer': composer,
        'sendButton': sendButton,
        'resultImage': resultImage,
        'refusal': refusal,
        'loginWall': loginWall,
        'imageHostHints': imageHostHints,
      };

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  static DolaSelectors fromJson(Map<String, dynamic> m) {
    List<String> list(String key, List<String> fallback) {
      final v = m[key];
      if (v is! List) return fallback;
      final out = [
        for (final e in v)
          if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
      ];
      return out.isEmpty ? fallback : out;
    }

    const d = defaults;
    final url = (m['chatUrl'] ?? '').toString().trim();
    return DolaSelectors(
      chatUrl: url.isEmpty ? d.chatUrl : url,
      composer: list('composer', d.composer),
      sendButton: list('sendButton', d.sendButton),
      resultImage: list('resultImage', d.resultImage),
      refusal: list('refusal', d.refusal),
      loginWall: list('loginWall', d.loginWall),
      imageHostHints: list('imageHostHints', d.imageHostHints),
    );
  }

  /// Parses a Settings override. Returns [defaults] for blank input so the
  /// user can always get back to a known-good state by clearing the field.
  static DolaSelectors parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return defaults;
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a JSON object with selector arrays.',
      );
    }
    return fromJson(decoded);
  }

  bool get isDefault => toPrettyJson() == defaults.toPrettyJson();
}
