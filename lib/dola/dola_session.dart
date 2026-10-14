import 'dart:convert';

/// One cookie belonging to a Dola session.
///
/// Mirrors the shape exported by the common "Export cookies" browser
/// extensions (EditThisCookie / Cookie-Editor), so a session captured in a
/// desktop browser can be pasted straight into Settings.
class DolaCookie {
  final String name;
  final String value;
  final String domain;
  final String path;

  /// Unix seconds. Null / 0 means a session cookie with no explicit expiry.
  final int? expires;

  final bool secure;
  final bool httpOnly;

  const DolaCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.expires,
    this.secure = true,
    this.httpOnly = false,
  });

  bool get isExpired {
    final e = expires;
    if (e == null || e <= 0) return false; // session cookie
    return DateTime.fromMillisecondsSinceEpoch(e * 1000).isBefore(
      DateTime.now(),
    );
  }

  /// True for the dola.com family (including the mcs- / passport- subdomains).
  bool get isDolaDomain {
    final d = domain.toLowerCase();
    return d.contains('dola.com') ||
        d.contains('ciciai.com') ||
        d.contains('doubao.com');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        if (expires != null) 'expirationDate': expires,
        'secure': secure,
        'httpOnly': httpOnly,
      };

  static DolaCookie fromJson(Map<String, dynamic> m) {
    // Extensions disagree on the expiry key and on its type (double seconds
    // vs int millis), so normalise defensively.
    final rawExp = m['expirationDate'] ?? m['expires'] ?? m['expiry'];
    int? exp;
    if (rawExp is num) {
      final v = rawExp.toDouble();
      // Anything past year ~2286 in seconds is really milliseconds.
      exp = v > 1e11 ? (v / 1000).round() : v.round();
    }
    return DolaCookie(
      name: (m['name'] ?? '').toString(),
      value: (m['value'] ?? '').toString(),
      domain: (m['domain'] ?? '.dola.com').toString(),
      path: (m['path'] ?? '/').toString(),
      expires: exp,
      secure: m['secure'] == true || m['secure'] == null,
      httpOnly: m['httpOnly'] == true,
    );
  }
}

/// A captured Dola browser session.
class DolaSession {
  final List<DolaCookie> cookies;

  /// When this session was captured, used to warn about staleness.
  final DateTime capturedAt;

  const DolaSession({required this.cookies, required this.capturedAt});

  /// A "nothing saved yet" session. Not `const`, because its timestamp is
  /// a real DateTime rather than a sentinel.
  static final DolaSession empty = DolaSession(
    cookies: const [],
    capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Cookie names that actually carry authentication for the ByteDance
  /// passport stack Dola sits on. Presence of any one of these means the
  /// session is worth trying; absence means the user is not signed in.
  static const strongAuthNames = {
    'sessionid',
    'sessionid_ss',
    'sid_tt',
    'sid_guard',
    'uid_tt',
    'uid_tt_ss',
  };

  /// Supporting cookies that are required alongside the auth ones for the
  /// backend to route the request. Missing these usually yields a redirect
  /// to the login page rather than a clean 401.
  static const supportingNames = {
    'passport_csrf_token',
    'passport_csrf_token_default',
    'store-idc',
    'store-country-code',
    'odin_tt',
    'samantha_web_web_id',
    'web_id',
    'msToken',
  };

  List<DolaCookie> get dolaCookies =>
      cookies.where((c) => c.isDolaDomain).toList();

  /// The auth cookies present, by name.
  Set<String> get presentAuthNames => {
        for (final c in cookies)
          if (strongAuthNames.contains(c.name) && c.value.trim().isNotEmpty)
            c.name,
      };

  /// A session is usable when it carries at least one strong auth cookie
  /// that has not expired.
  bool get isUsable => cookies.any(
        (c) =>
            strongAuthNames.contains(c.name) &&
            c.value.trim().isNotEmpty &&
            !c.isExpired,
      );

  bool get isEmpty => cookies.isEmpty;

  /// Cookies that have passed their expiry date.
  List<DolaCookie> get expired => cookies.where((c) => c.isExpired).toList();

  /// Ready-to-send `Cookie:` header for the dola.com origin.
  String get cookieHeader => dolaCookies
      .where((c) => !c.isExpired && c.value.trim().isNotEmpty)
      .map((c) => '${c.name}=${c.value}')
      .join('; ');

  /// One-line description for the Settings row.
  String get summary {
    if (isEmpty) return 'No session saved';
    final auth = presentAuthNames.length;
    final age = DateTime.now().difference(capturedAt);
    final when = age.inDays > 0
        ? '${age.inDays}d ago'
        : age.inHours > 0
            ? '${age.inHours}h ago'
            : 'just now';
    if (!isUsable) {
      return '${cookies.length} cookies, no valid auth cookie - sign in again';
    }
    final stale = expired.isNotEmpty ? ', ${expired.length} expired' : '';
    return '${cookies.length} cookies ($auth auth$stale), captured $when';
  }

  String toRawJson() => jsonEncode({
        'capturedAt': capturedAt.toIso8601String(),
        'cookies': [for (final c in cookies) c.toJson()],
      });

  /// Accepts either this app's own envelope, a bare extension cookie array,
  /// or a raw `name=value; name=value` header string.
  static DolaSession parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return DolaSession(cookies: const [], capturedAt: _now());

    // 1. Raw Cookie header (no JSON punctuation at the start).
    if (!text.startsWith('{') && !text.startsWith('[')) {
      return DolaSession(
        cookies: _parseHeader(text),
        capturedAt: _now(),
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('That is not valid JSON or a cookie header: $e');
    }

    // 2. Bare array from a cookie-export extension.
    if (decoded is List) {
      return DolaSession(
        cookies: _fromList(decoded),
        capturedAt: _now(),
      );
    }

    // 3. This app's envelope, or a { "cookies": [...] } wrapper.
    if (decoded is Map<String, dynamic>) {
      final list = decoded['cookies'];
      if (list is! List) {
        throw const FormatException(
          'Expected a "cookies" array in the pasted JSON.',
        );
      }
      DateTime captured;
      try {
        captured = DateTime.parse(decoded['capturedAt'].toString());
      } catch (_) {
        captured = _now();
      }
      return DolaSession(cookies: _fromList(list), capturedAt: captured);
    }

    throw const FormatException('Unrecognised session format.');
  }

  static List<DolaCookie> _fromList(List<dynamic> raw) {
    final out = <DolaCookie>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final c = DolaCookie.fromJson(Map<String, dynamic>.from(item));
      if (c.name.isEmpty || c.value.isEmpty) continue;
      out.add(c);
    }
    if (out.isEmpty) {
      throw const FormatException('No usable cookies found in that export.');
    }
    return out;
  }

  static List<DolaCookie> _parseHeader(String header) {
    final out = <DolaCookie>[];
    for (final part in header.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      out.add(DolaCookie(name: name, value: value, domain: '.dola.com'));
    }
    if (out.isEmpty) {
      throw const FormatException(
        'Could not read any "name=value" pairs from that text.',
      );
    }
    return out;
  }

  static DateTime _now() => DateTime.now();
}

