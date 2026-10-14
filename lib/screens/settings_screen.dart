import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/export_presets.dart';
import '../distribute.dart';
import '../dola/dola_selectors.dart';
import '../gemini_web.dart';
import '../dola/dola_session.dart';
import '../secure_store.dart';
import '../widgets/studio_widgets.dart';
import 'dola_login_screen.dart';

/// Editable row for one distribution account.
class _DistAccountEdit {
  final nameCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  final secretCtrl = TextEditingController();
  bool obscure = true;

  _DistAccountEdit();

  _DistAccountEdit.from(DistAccount a) {
    nameCtrl.text = a.name;
    urlCtrl.text = a.dbUrl;
    secretCtrl.text = a.secret;
  }

  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    secretCtrl.dispose();
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cookieCtl = TextEditingController();
  final _selectorCtl = TextEditingController();

  DolaSession _session = DolaSession.empty;
  String _geminiSummary = 'Not configured';
  int _preset = 0;
  bool _loading = true;
  bool _showCookieField = false;

  // Gemini Web session editor state.
  final _geminiCtl = TextEditingController();
  bool _geminiBusy = false;
  bool _geminiOk = false;
  List<String> _geminiLines = const [];

  // Distribution (own R2 worker + Firebase accounts) editor state.
  final _distR2Ctl = TextEditingController();
  final _distQueueCtl = TextEditingController();
  final List<_DistAccountEdit> _distAccounts = [];
  String _distDefaultTarget = 'spread';
  final List<String> _distSpreadPool = [];
  bool _distBusy = false;
  bool _distOk = false;
  String? _distStatus;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDist();
  }

  @override
  void dispose() {
    _cookieCtl.dispose();
    _selectorCtl.dispose();
    _geminiCtl.dispose();
    _distR2Ctl.dispose();
    _distQueueCtl.dispose();
    for (final a in _distAccounts) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    DolaSession session = DolaSession.empty;
    var selectors = '';
    var gemini = '';
    var preset = 0;
    try {
      session = await DolaSessionStore.load();
      selectors = await AppPrefs.selectorsRaw();
      gemini = await GeminiWebStore.load();
      preset = await AppPrefs.lastExport();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _session = session;
      _selectorCtl.text = selectors;
      _geminiCtl.text = gemini;
      _geminiSummary =
          gemini.trim().isEmpty ? 'Not configured' : 'Session saved';
      _preset = preset;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveCookies() async {
    final raw = _cookieCtl.text.trim();
    if (raw.isEmpty) return;
    DolaSession parsed;
    try {
      parsed = DolaSession.parse(raw);
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    } catch (e) {
      _snack('Could not read that: $e');
      return;
    }
    if (!parsed.isUsable) {
      _snack('No valid auth cookie in there - check the export and retry.');
      return;
    }
    await DolaSessionStore.save(parsed);
    if (!mounted) return;
    setState(() {
      _session = parsed;
      _cookieCtl.clear();
      _showCookieField = false;
    });
    _snack('Session saved - ${parsed.presentAuthNames.length} auth cookies');
  }

  /// Opens the in-app browser so the user can sign in to Dola directly.
  /// Returns true when a session was captured and saved.
  Future<void> _openLogin() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const DolaLoginScreen()),
    );
    if (saved == true) await _load();
  }

  Future<void> _clearSession() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Dola?'),
        content: const Text(
          'The saved cookies are deleted from this device\'s secure storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await DolaSessionStore.clear();
    if (!mounted) return;
    setState(() => _session = DolaSession.empty);
    _snack('Signed out');
  }

  /// Validates and stores the Gemini Web session. Parsing happens before
  /// the write so a broken export is caught here rather than mid-batch.
  Future<void> _saveGemini() async {
    final raw = _geminiCtl.text.trim();
    setState(() {
      _geminiBusy = true;
      _geminiLines = const [];
    });

    if (raw.isNotEmpty) {
      try {
        final session = GeminiWebSession.parse(raw);
        setState(() {
          _geminiOk = session.authCookies.isNotEmpty;
          _geminiLines = [
            'Format detected: ${session.format}',
            session.summary,
            if (session.authCookies.isEmpty)
              'No Google auth cookie (SID / __Secure-1PSID ...) found - '
                  're-export while gemini.google.com is open.',
          ];
        });
      } on GeminiWebException catch (e) {
        setState(() {
          _geminiBusy = false;
          _geminiOk = false;
          _geminiLines = [e.message];
        });
        return;
      }
    }

    try {
      await GeminiWebStore.save(raw);
    } catch (e) {
      if (!mounted) return;
      setState(() => _geminiBusy = false);
      _snack('Save failed: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _geminiBusy = false;
      _geminiSummary = raw.isEmpty ? 'Not configured' : 'Session saved';
    });
    _snack(raw.isEmpty
        ? 'Gemini web session cleared.'
        : 'Gemini web session saved on this device.');
  }

  /// Live round-trip against Gemini Web, so a stale cookie is caught before
  /// a long metadata run rather than during it.
  Future<void> _testGemini() async {
    final raw = _geminiCtl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _geminiOk = false;
        _geminiLines = const ['Paste your Gemini web session JSON first.'];
      });
      return;
    }
    setState(() {
      _geminiBusy = true;
      _geminiLines = const [];
    });

    GeminiWebSession session;
    try {
      session = GeminiWebSession.parse(raw);
    } on GeminiWebException catch (e) {
      if (!mounted) return;
      setState(() {
        _geminiBusy = false;
        _geminiOk = false;
        _geminiLines = [e.message];
      });
      return;
    }

    final result = await GeminiWebClient(session).test();
    if (!mounted) return;
    setState(() {
      _geminiBusy = false;
      _geminiOk = result.ok;
      _geminiLines = [
        'Format detected: ${session.format}',
        result.summary,
        result.ok
            ? 'OK (${result.ms}ms) - ${result.message}'
            : 'FAIL - ${result.message}',
      ];
    });
  }

  Future<void> _clearGemini() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Gemini web session?'),
        content: const Text(
          'The saved cookies are deleted from this device\'s secure storage. '
          'AI metadata generation will stop working until you add a session '
          'again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await GeminiWebStore.clear();
    if (!mounted) return;
    setState(() {
      _geminiCtl.clear();
      _geminiOk = false;
      _geminiLines = const [];
      _geminiSummary = 'Not configured';
    });
    _snack('Gemini web session removed');
  }

  Future<void> _saveSelectors() async {
    final raw = _selectorCtl.text.trim();
    if (raw.isNotEmpty) {
      try {
        DolaSelectors.parse(raw);
      } on FormatException catch (e) {
        _snack(e.message);
        return;
      } catch (e) {
        _snack('Invalid selector JSON: $e');
        return;
      }
    }
    await AppPrefs.setSelectorsRaw(raw);
    _snack(raw.isEmpty ? 'Reverted to built-in selectors' : 'Selectors saved');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: screenScrollPadding(context, Skin.s5),
      children: [
        const Text('Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Skin.text,
            )),
        const SizedBox(height: Skin.s5),

        const SectionLabel('Image backend'),
        _backendPanel(),

        const SizedBox(height: Skin.s5),
        const SectionLabel('Export'),
        _exportPanel(),

        const SizedBox(height: Skin.s5),
        const SectionLabel('Prompt authoring'),
        _geminiPanel(),

        const SizedBox(height: Skin.s5),
        const SectionLabel('Distribution'),
        _distPanel(),

        const SizedBox(height: Skin.s5),
        const SectionLabel('Advanced'),
        _selectorPanel(),

        const SizedBox(height: Skin.s5),
        _aboutPanel(),
      ],
    );
  }

  // ------------------------------------------------------------ backend

  Widget _backendPanel() {
    final usable = _session.isUsable;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: usable ? Skin.success : Skin.textFaint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Skin.s2),
              const Expanded(
                child: Text('Dola',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Skin.text,
                    )),
              ),
              if (usable)
                TextButton(
                  onPressed: _clearSession,
                  child: const Text('Sign out'),
                ),
            ],
          ),
          const SizedBox(height: Skin.s1),
          Text(_session.summary,
              style: const TextStyle(fontSize: 13, color: Skin.textDim)),

          const SizedBox(height: Skin.s4),
          const NoticeBar(
            icon: Icons.info_outline,
            title: 'Sign-in works; generation is not connected yet',
            message:
                'You can sign in and save a session here. The generation '
                'driver itself still needs to be connected, so generating '
                'will fail until then.',
            tone: Skin.info,
          ),

          const SizedBox(height: Skin.s4),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _openLogin,
                icon: const Icon(Icons.open_in_browser, size: 17),
                label: Text(usable ? 'Sign in again' : 'Sign in to Dola'),
              ),
              const Spacer(),
              if (!_showCookieField)
                TextButton(
                  onPressed: () => setState(() => _showCookieField = true),
                  child: const Text('Paste cookies instead'),
                ),
            ],
          ),
          if (_showCookieField) ...[
            const SizedBox(height: Skin.s3),
            const Text(
              'Fallback: export cookies from a desktop browser with a '
              'cookie-export extension and paste the JSON here. A raw '
              '"name=value; name=value" header works too.',
              style: TextStyle(fontSize: 12.5, color: Skin.textFaint, height: 1.5),
            ),
            const SizedBox(height: Skin.s3),
            TextField(
              controller: _cookieCtl,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '[{"name":"sessionid","value":"...","domain":".dola.com"}]',
              ),
            ),
            const SizedBox(height: Skin.s3),
            Row(
              children: [
                FilledButton(
                  onPressed: _saveCookies,
                  child: const Text('Save session'),
                ),
                const SizedBox(width: Skin.s2),
                TextButton(
                  onPressed: () => setState(() {
                    _showCookieField = false;
                    _cookieCtl.clear();
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],

          const SizedBox(height: Skin.s4),
          const Divider(height: 1, color: Skin.line),
          const SizedBox(height: Skin.s3),
          const Text(
            'These cookies are account credentials. They are kept in this '
            'device\'s secure storage and sent only to dola.com. Driving a '
            'consumer account from an app is against Dola\'s terms of '
            'service, and the account can be throttled or banned for it.',
            style: TextStyle(fontSize: 12, color: Skin.textFaint, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- export

  Widget _exportPanel() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Default export size',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Skin.text,
              )),
          const SizedBox(height: Skin.s1),
          const Text(
            'Resizing and cropping now runs on this device, so saving works '
            'offline and does not depend on a delivery URL staying alive.',
            style: TextStyle(fontSize: 12.5, color: Skin.textFaint, height: 1.5),
          ),
          const SizedBox(height: Skin.s3),
          Wrap(
            spacing: Skin.s2,
            runSpacing: Skin.s2,
            children: [
              for (var i = 0; i < ExportPresets.all.length; i++)
                ChoiceChip(
                  label: Text(ExportPresets.all[i].label),
                  selected: _preset == i,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    color: _preset == i ? Skin.onAccent : Skin.textDim,
                  ),
                  onSelected: (_) async {
                    setState(() => _preset = i);
                    try {
                      await AppPrefs.setExport(i);
                    } catch (_) {}
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- gemini

  Widget _geminiPanel() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _geminiSummary == 'Not configured'
                      ? Skin.textFaint
                      : Skin.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Skin.s2),
              const Expanded(
                child: Text('Gemini Web session (cookies)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Skin.text,
                    )),
              ),
              if (_geminiSummary != 'Not configured')
                TextButton(
                  onPressed: _geminiBusy ? null : _clearGemini,
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: Skin.s1),
          const Text(
            'Writes AI titles, tags, categories and descriptions for your '
            'generated sets, and powers the metadata.json in the ZIP export. '
            'Never used for image generation.',
            style: TextStyle(fontSize: 12.5, color: Skin.textFaint, height: 1.5),
          ),
          const SizedBox(height: Skin.s3),
          TextField(
            controller: _geminiCtl,
            maxLines: 6,
            minLines: 3,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'Paste the cookie export from gemini.google.com '
                  '(JSON array, or a raw "name=value; ..." header)',
            ),
          ),
          const SizedBox(height: Skin.s3),
          Row(
            children: [
              FilledButton(
                onPressed: _geminiBusy ? null : _saveGemini,
                child: const Text('Save'),
              ),
              const SizedBox(width: Skin.s2),
              OutlinedButton.icon(
                onPressed: _geminiBusy ? null : _testGemini,
                icon: _geminiBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 16),
                label: const Text('Test connection'),
              ),
            ],
          ),
          if (_geminiLines.isNotEmpty) ...[
            const SizedBox(height: Skin.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Skin.s3),
              decoration: BoxDecoration(
                color: (_geminiOk ? Skin.success : Skin.danger)
                    .withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(Skin.rSm),
                border: Border.all(
                  color: (_geminiOk ? Skin.success : Skin.danger)
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _geminiLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(line,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Skin.textDim,
                            height: 1.4,
                          )),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------- distribution

  Future<void> _loadDist() async {
    try {
      final cfg = await DistributeStore.load();
      if (!mounted) return;
      setState(() {
        _distR2Ctl.text = cfg.r2WorkerUrl;
        _distQueueCtl.text = cfg.queuePath;
        _distAccounts
          ..clear()
          ..addAll(cfg.accounts.map(_DistAccountEdit.from));
        _distDefaultTarget = cfg.defaultTarget;
        _distSpreadPool
          ..clear()
          ..addAll(cfg.spreadPool);
      });
    } catch (_) {}
  }

  DistConfig _readDistConfig() {
    final accounts = _distAccounts
        .map((e) => DistAccount(
              name: e.nameCtrl.text.trim(),
              dbUrl: e.urlCtrl.text.trim(),
              secret: e.secretCtrl.text.trim(),
            ))
        .where((a) => a.name.isNotEmpty && a.dbUrl.isNotEmpty)
        .toList();
    var def = _distDefaultTarget;
    if (def != 'spread' && accounts.every((a) => a.name != def)) {
      def = 'spread';
    }
    final pool =
        _distSpreadPool.where((n) => accounts.any((a) => a.name == n)).toList();
    return DistConfig(
      r2WorkerUrl: _distR2Ctl.text.trim(),
      queuePath: _distQueueCtl.text.trim().isEmpty
          ? 'wallpaperQueue'
          : _distQueueCtl.text.trim(),
      accounts: accounts,
      defaultTarget: def,
      spreadPool: pool,
    );
  }

  Future<void> _saveDist() async {
    setState(() {
      _distBusy = true;
      _distStatus = null;
    });
    try {
      final cfg = _readDistConfig();
      if (cfg.accounts.isEmpty) {
        throw Exception('Add at least one account with a name and a URL.');
      }
      if (cfg.r2WorkerUrl.isEmpty) {
        throw Exception('Enter the R2 worker URL.');
      }
      final names = cfg.accounts.map((a) => a.name).toList();
      if (names.toSet().length != names.length) {
        throw Exception('Account names must be unique.');
      }
      await DistributeStore.save(cfg);
      if (!mounted) return;
      setState(() {
        _distDefaultTarget = cfg.defaultTarget;
        _distSpreadPool
          ..clear()
          ..addAll(cfg.spreadPool);
        _distOk = true;
        _distStatus = 'Saved. ${cfg.accounts.length} account(s) ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _distOk = false;
        _distStatus = 'Save failed: $e';
      });
    } finally {
      if (mounted) setState(() => _distBusy = false);
    }
  }

  Future<void> _testDistAccount(DistAccount a) async {
    if (a.dbUrl.isEmpty) {
      setState(() {
        _distOk = false;
        _distStatus = 'Enter a database URL for this account first.';
      });
      return;
    }
    setState(() {
      _distBusy = true;
      _distStatus = null;
    });
    try {
      await testDatabaseConnection(dbUrl: a.dbUrl, secret: a.secret);
      if (!mounted) return;
      setState(() {
        _distOk = true;
        _distStatus = '${a.name}: reachable. Read-only test, nothing written.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _distOk = false;
        _distStatus = '${a.name}: failed - $e';
      });
    } finally {
      if (mounted) setState(() => _distBusy = false);
    }
  }

  Widget _distPanel() {
    final names = _distAccounts
        .map((e) => e.nameCtrl.text.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _distAccounts.isEmpty ? Skin.textFaint : Skin.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Skin.s2),
              const Expanded(
                child: Text('Your upload accounts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Skin.text,
                    )),
              ),
            ],
          ),
          const SizedBox(height: Skin.s1),
          const Text(
            'Finished images upload their files to your own R2 bucket through '
            'your worker, then one record (files + metadata) is pushed to that '
            'account\'s Firebase queue. Each image goes to exactly one account.',
            style: TextStyle(fontSize: 12.5, color: Skin.textFaint, height: 1.5),
          ),
          const SizedBox(height: Skin.s3),
          TextField(
            controller: _distR2Ctl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'R2 worker URL',
              hintText: 'https://your-worker.workers.dev',
            ),
          ),
          const SizedBox(height: Skin.s3),
          TextField(
            controller: _distQueueCtl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Queue path',
              hintText: 'wallpaperQueue',
            ),
          ),
          const SizedBox(height: Skin.s4),
          Text('Accounts (${_distAccounts.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: Skin.textDim,
              )),
          const SizedBox(height: Skin.s2),
          for (var i = 0; i < _distAccounts.length; i++) ...[
            _accountRow(i),
            const SizedBox(height: Skin.s2),
          ],
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _distAccounts.add(_DistAccountEdit())),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add account'),
          ),
          const SizedBox(height: Skin.s4),
          DropdownButtonFormField<String>(
            initialValue: _distDefaultTarget,
            style: const TextStyle(fontSize: 13, color: Skin.text),
            dropdownColor: Skin.surface,
            decoration: const InputDecoration(labelText: 'Default target'),
            items: [
              const DropdownMenuItem(
                value: 'spread',
                child: Text('Spread - rotate accounts'),
              ),
              for (final n in names)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (v) => setState(() => _distDefaultTarget = v ?? 'spread'),
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: Skin.s3),
            const Text('Spread across',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: Skin.textDim,
                )),
            const SizedBox(height: Skin.s2),
            Wrap(
              spacing: Skin.s2,
              runSpacing: Skin.s2,
              children: [
                for (final n in names)
                  FilterChip(
                    label: Text(n),
                    selected: _distSpreadPool.contains(n),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _distSpreadPool.add(n);
                      } else {
                        _distSpreadPool.remove(n);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Skin.s2),
            const Text('Empty selection means all accounts.',
                style: TextStyle(fontSize: 11.5, color: Skin.textFaint)),
          ],
          const SizedBox(height: Skin.s4),
          FilledButton(
            onPressed: _distBusy ? null : _saveDist,
            child: Text(_distBusy ? 'Working...' : 'Save'),
          ),
          if (_distStatus != null) ...[
            const SizedBox(height: Skin.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Skin.s3),
              decoration: BoxDecoration(
                color: (_distOk ? Skin.success : Skin.danger)
                    .withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(Skin.rSm),
                border: Border.all(
                  color: (_distOk ? Skin.success : Skin.danger)
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Text(_distStatus!,
                  style: const TextStyle(
                      fontSize: 12, color: Skin.textDim, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountRow(int i) {
    final e = _distAccounts[i];
    return Container(
      padding: const EdgeInsets.all(Skin.s3),
      decoration: BoxDecoration(
        color: Skin.canvas,
        borderRadius: BorderRadius.circular(Skin.rSm),
        border: Border.all(color: Skin.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: e.nameCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'account_1',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Test this database',
                icon: const Icon(Icons.wifi_find_outlined, size: 18),
                onPressed: _distBusy
                    ? null
                    : () => _testDistAccount(DistAccount(
                          name: e.nameCtrl.text.trim(),
                          dbUrl: e.urlCtrl.text.trim(),
                          secret: e.secretCtrl.text.trim(),
                        )),
              ),
              IconButton(
                tooltip: 'Remove account',
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Skin.danger),
                onPressed: () => setState(() {
                  final removed = _distAccounts.removeAt(i);
                  _distSpreadPool.remove(removed.nameCtrl.text.trim());
                  removed.dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: Skin.s2),
          TextField(
            controller: e.urlCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(
              labelText: 'Database URL',
              hintText: 'https://your-db.firebasedatabase.app',
            ),
          ),
          const SizedBox(height: Skin.s2),
          TextField(
            controller: e.secretCtrl,
            obscureText: e.obscure,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              labelText: 'Secret (optional)',
              suffixIcon: IconButton(
                tooltip: e.obscure ? 'Show' : 'Hide',
                icon: Icon(
                    e.obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18),
                onPressed: () => setState(() => e.obscure = !e.obscure),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- selectors

  Widget _selectorPanel() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dola page selectors',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Skin.text,
              )),
          const SizedBox(height: Skin.s1),
          const Text(
            'Dola has no public API, so the app drives its web page directly. '
            'If Dola ships a redesign, generation breaks with "could not find '
            'the prompt box" - paste corrected CSS selectors here to fix it '
            'without waiting for an app update. Leave empty for the defaults.',
            style: TextStyle(fontSize: 12.5, color: Skin.textFaint, height: 1.5),
          ),
          const SizedBox(height: Skin.s3),
          TextField(
            controller: _selectorCtl,
            maxLines: 10,
            minLines: 4,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: DolaSelectors.defaults.toPrettyJson(),
            ),
          ),
          const SizedBox(height: Skin.s3),
          Row(
            children: [
              OutlinedButton(
                onPressed: _saveSelectors,
                child: const Text('Save selectors'),
              ),
              const SizedBox(width: Skin.s2),
              TextButton(
                onPressed: () {
                  _selectorCtl.text = DolaSelectors.defaults.toPrettyJson();
                  setState(() {});
                },
                child: const Text('Load defaults'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  _selectorCtl.clear();
                  await AppPrefs.setSelectorsRaw('');
                  _snack('Reverted to built-in selectors');
                },
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aboutPanel() {
    return Panel(
      color: Skin.canvas,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Meta Hawaladar Image Generator',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Skin.textDim,
              )),
          SizedBox(height: 4),
          Text(
            'Text-to-image generation for Windows and Android.',
            style: TextStyle(fontSize: 12.5, color: Skin.textFaint),
          ),
        ],
      ),
    );
  }
}
