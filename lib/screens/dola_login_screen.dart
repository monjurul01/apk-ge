import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_theme.dart';
import '../dola/dola_selectors.dart';
import '../dola/dola_session.dart';
import '../secure_store.dart';
import '../widgets/studio_widgets.dart';

/// An in-app browser for signing in to Dola.
///
/// This is a plain embedded browser: the user navigates and signs in
/// themselves, exactly as they would in Chrome. Nothing is automated and no
/// page is driven - the screen's only job is to let the sign-in happen and
/// then persist the resulting session so it does not have to be repeated.
///
/// It replaces the "export cookies from a desktop browser and paste the
/// JSON" flow in Settings, which stays available as a fallback.
///
/// Existing features are untouched: this screen is additive, and the
/// session it writes goes to the same [DolaSessionStore] that the manual
/// paste flow already wrote to.
class DolaLoginScreen extends StatefulWidget {
  const DolaLoginScreen({super.key});

  @override
  State<DolaLoginScreen> createState() => _DolaLoginScreenState();
}

class _DolaLoginScreenState extends State<DolaLoginScreen> {
  InAppWebViewController? _controller;

  double _progress = 0;
  String _url = '';
  bool _saving = false;

  /// Auth cookies currently visible for the dola.com origin.
  Set<String> _authFound = const {};

  /// Set once we have saved, so the banner can switch to a done state.
  bool _savedOnce = false;

  static const _startUrl = 'https://www.dola.com/chat/create-image';

  bool get _signedIn => _authFound.isNotEmpty;

  // ------------------------------------------------------------ cookies

  /// Reads the cookie jar for every host Dola's login spans. The session
  /// cookie is set on the passport host, not on www, so checking only the
  /// current page would miss it.
  Future<List<DolaCookie>> _collectCookies() async {
    const hosts = [
      'https://www.dola.com',
      'https://dola.com',
      'https://mcs-nontt.dola.com',
      'https://accounts.doubao.com',
    ];

    final jar = CookieManager.instance();
    final byName = <String, DolaCookie>{};

    for (final host in hosts) {
      List<Cookie> cookies;
      try {
        cookies = await jar.getCookies(url: WebUri(host));
      } catch (_) {
        continue;
      }
      for (final c in cookies) {
        final name = c.name.trim();
        final value = c.value?.toString() ?? '';
        if (name.isEmpty || value.isEmpty) continue;
        // Prefer whichever copy carries an explicit domain.
        final existing = byName[name];
        if (existing != null && existing.domain.isNotEmpty) continue;
        byName[name] = DolaCookie(
          name: name,
          value: value,
          domain: c.domain ?? Uri.parse(host).host,
          path: c.path ?? '/',
          expires: c.expiresDate == null
              ? null
              : (c.expiresDate! / 1000).round(),
          secure: c.isSecure ?? true,
          httpOnly: c.isHttpOnly ?? false,
        );
      }
    }
    return byName.values.toList();
  }

  /// Refreshes the signed-in indicator after each navigation.
  Future<void> _refreshAuthState() async {
    final cookies = await _collectCookies();
    final found = {
      for (final c in cookies)
        if (DolaSession.strongAuthNames.contains(c.name) && !c.isExpired)
          c.name,
    };
    if (!mounted) return;
    setState(() => _authFound = found);
  }

  Future<void> _saveSession() async {
    if (_saving) return;
    setState(() => _saving = true);

    final cookies = await _collectCookies();
    final session = DolaSession(cookies: cookies, capturedAt: DateTime.now());

    if (!session.isUsable) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not find a signed-in session yet. Finish signing in '
          'first, then try again.');
      return;
    }

    await DolaSessionStore.save(session);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedOnce = true;
    });
    _snack('Signed in - ${session.cookies.length} cookies saved');
    Navigator.of(context).pop(true);
  }

  /// Clears the jar so a different account can be used.
  Future<void> _startOver() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_startUrl)),
    );
    if (!mounted) return;
    setState(() {
      _authFound = const {};
      _savedOnce = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Skin.canvas,
      appBar: AppBar(
        title: const Text('Sign in to Dola'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => _controller?.reload(),
          ),
          IconButton(
            tooltip: 'Use a different account',
            icon: const Icon(Icons.person_off_outlined, size: 20),
            onPressed: _startOver,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress > 0 && _progress < 1)
              LinearProgressIndicator(value: _progress, minHeight: 2)
            else
              const SizedBox(height: 2),

            Padding(
              padding: const EdgeInsets.all(Skin.s3),
              child: _statusBanner(),
            ),

            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Skin.rSm),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_startUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    // Dola's sign-in opens provider popups; without this the
                    // flow dead-ends on a blank frame.
                    javaScriptCanOpenWindowsAutomatically: true,
                    supportMultipleWindows: true,
                    thirdPartyCookiesEnabled: true,
                    sharedCookiesEnabled: true,
                    useShouldOverrideUrlLoading: false,
                  ),
                  onWebViewCreated: (c) => _controller = c,
                  onProgressChanged: (c, p) {
                    if (mounted) setState(() => _progress = p / 100);
                  },
                  onLoadStop: (c, url) async {
                    if (mounted) setState(() => _url = url?.toString() ?? '');
                    await _refreshAuthState();
                  },
                  onUpdateVisitedHistory: (c, url, _) async {
                    if (mounted) setState(() => _url = url?.toString() ?? '');
                    await _refreshAuthState();
                  },
                  // Sign-in providers open in a new window; host it in a
                  // sheet so the user can complete and return.
                  onCreateWindow: (c, req) async {
                    await showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        insetPadding: const EdgeInsets.all(Skin.s4),
                        child: SizedBox(
                          width: 520,
                          height: 640,
                          child: InAppWebView(
                            windowId: req.windowId,
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                              thirdPartyCookiesEnabled: true,
                              sharedCookiesEnabled: true,
                            ),
                            onCloseWindow: (_) => Navigator.maybePop(context),
                          ),
                        ),
                      ),
                    );
                    await _refreshAuthState();
                    return true;
                  },
                ),
              ),
            ),

            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner() {
    if (_savedOnce) {
      return const NoticeBar(
        icon: Icons.check_circle_outline,
        title: 'Session saved',
        tone: Skin.success,
      );
    }
    if (_signedIn) {
      return NoticeBar(
        icon: Icons.verified_user_outlined,
        title: 'Signed in',
        message: 'Found ${_authFound.length} session '
            '${_authFound.length == 1 ? 'cookie' : 'cookies'}. '
            'Save to keep this session on the device.',
        tone: Skin.success,
      );
    }
    return const NoticeBar(
      icon: Icons.login,
      title: 'Sign in with your own Dola account',
      message: 'Use the page below exactly as you would in a browser. '
          'This screen only watches for a completed sign-in.',
      tone: Skin.info,
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Skin.s3,
        Skin.s3,
        Skin.s3,
        Skin.s3 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Skin.surface,
        border: Border(top: BorderSide(color: Skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _url.isEmpty ? DolaSelectors.defaults.chatUrl : _url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Skin.textFaint),
            ),
          ),
          const SizedBox(width: Skin.s3),
          FilledButton.icon(
            onPressed: _signedIn && !_saving ? _saveSession : null,
            icon: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 17),
            label: const Text('Save session'),
          ),
        ],
      ),
    );
  }
}
