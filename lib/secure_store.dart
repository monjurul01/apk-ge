import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dola/dola_selectors.dart';
import 'dola/dola_session.dart';

/// The Dola browser session lives in OS secure storage (Keychain /
/// Keystore / Windows Credential Manager), never in plain preferences -
/// these cookies are bearer credentials for the user's account.
class DolaSessionStore {
  DolaSessionStore._();

  static const _storage = FlutterSecureStorage();
  static const _kSession = 'dola_session';

  static Future<DolaSession> load() async {
    final raw = await _storage.read(key: _kSession) ?? '';
    if (raw.trim().isEmpty) return DolaSession.empty;
    try {
      return DolaSession.parse(raw);
    } catch (_) {
      // A corrupt blob must not wedge the app on launch.
      return DolaSession.empty;
    }
  }

  static Future<void> save(DolaSession session) =>
      _storage.write(key: _kSession, value: session.toRawJson());

  static Future<void> clear() => _storage.delete(key: _kSession);
}

/// Gemini Web (cookie) session, used only for prompt/metadata authoring -
/// never for image generation.
class GeminiWebStore {
  GeminiWebStore._();

  static const _storage = FlutterSecureStorage();
  static const _kSession = 'gemini_web_session';

  /// Raw session JSON ('' when not configured).
  static Future<String> load() async =>
      await _storage.read(key: _kSession) ?? '';

  static Future<void> save(String sessionJson) =>
      _storage.write(key: _kSession, value: sessionJson.trim());

  static Future<void> clear() => _storage.delete(key: _kSession);
}

/// Non-secret app preferences.
class AppPrefs {
  AppPrefs._();

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Shared instance for other preference holders.
  static Future<SharedPreferences> prefs() => _p();

  /// Selector overrides for the Dola driver. Stored as raw JSON so a bad
  /// edit degrades to the built-in defaults instead of crashing.
  static Future<DolaSelectors> selectors() async {
    final raw = (await _p()).getString('dola_selectors') ?? '';
    if (raw.trim().isEmpty) return DolaSelectors.defaults;
    try {
      return DolaSelectors.parse(raw);
    } catch (_) {
      return DolaSelectors.defaults;
    }
  }

  static Future<String> selectorsRaw() async =>
      (await _p()).getString('dola_selectors') ?? '';

  static Future<void> setSelectorsRaw(String v) async {
    final p = await _p();
    if (v.trim().isEmpty) {
      await p.remove('dola_selectors');
    } else {
      await p.setString('dola_selectors', v.trim());
    }
  }

  static Future<List<String>> history() async =>
      (await _p()).getStringList('history') ?? [];

  static Future<void> setHistory(List<String> v) async =>
      (await _p()).setStringList('history', v);

  static Future<int> lastExport() async =>
      (await _p()).getInt('export_preset') ?? 0;

  static Future<void> setExport(int v) async =>
      (await _p()).setInt('export_preset', v);

  static Future<int> gridCols() async => (await _p()).getInt('grid_cols') ?? 3;

  static Future<void> setGridCols(int v) async =>
      (await _p()).setInt('grid_cols', v.clamp(2, 6));
}
