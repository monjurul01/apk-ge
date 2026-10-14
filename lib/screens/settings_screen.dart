import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/export_presets.dart';
import '../dola/dola_selectors.dart';
import '../dola/dola_session.dart';
import '../secure_store.dart';
import '../widgets/studio_widgets.dart';
import 'dola_login_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cookieCtl.dispose();
    _selectorCtl.dispose();
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
      padding: screenScrollPadding(context, Ink.s5),
      children: [
        const Text('Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Ink.text,
            )),
        const SizedBox(height: Ink.s5),

        const SectionLabel('Image backend'),
        _backendPanel(),

        const SizedBox(height: Ink.s5),
        const SectionLabel('Export'),
        _exportPanel(),

        const SizedBox(height: Ink.s5),
        const SectionLabel('Prompt authoring'),
        _geminiPanel(),

        const SizedBox(height: Ink.s5),
        const SectionLabel('Advanced'),
        _selectorPanel(),

        const SizedBox(height: Ink.s5),
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
                  color: usable ? Ink.success : Ink.textFaint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Ink.s2),
              const Expanded(
                child: Text('Dola',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Ink.text,
                    )),
              ),
              if (usable)
                TextButton(
                  onPressed: _clearSession,
                  child: const Text('Sign out'),
                ),
            ],
          ),
          const SizedBox(height: Ink.s1),
          Text(_session.summary,
              style: const TextStyle(fontSize: 13, color: Ink.textDim)),

          const SizedBox(height: Ink.s4),
          const NoticeBar(
            icon: Icons.info_outline,
            title: 'Sign-in works; generation is not connected yet',
            message:
                'You can sign in and save a session here. The generation '
                'driver itself still needs to be connected, so generating '
                'will fail until then.',
            tone: Ink.info,
          ),

          const SizedBox(height: Ink.s4),
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
            const SizedBox(height: Ink.s3),
            const Text(
              'Fallback: export cookies from a desktop browser with a '
              'cookie-export extension and paste the JSON here. A raw '
              '"name=value; name=value" header works too.',
              style: TextStyle(fontSize: 12.5, color: Ink.textFaint, height: 1.5),
            ),
            const SizedBox(height: Ink.s3),
            TextField(
              controller: _cookieCtl,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '[{"name":"sessionid","value":"...","domain":".dola.com"}]',
              ),
            ),
            const SizedBox(height: Ink.s3),
            Row(
              children: [
                FilledButton(
                  onPressed: _saveCookies,
                  child: const Text('Save session'),
                ),
                const SizedBox(width: Ink.s2),
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

          const SizedBox(height: Ink.s4),
          const Divider(height: 1, color: Ink.line),
          const SizedBox(height: Ink.s3),
          const Text(
            'These cookies are account credentials. They are kept in this '
            'device\'s secure storage and sent only to dola.com. Driving a '
            'consumer account from an app is against Dola\'s terms of '
            'service, and the account can be throttled or banned for it.',
            style: TextStyle(fontSize: 12, color: Ink.textFaint, height: 1.5),
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
                color: Ink.text,
              )),
          const SizedBox(height: Ink.s1),
          const Text(
            'Resizing and cropping now runs on this device, so saving works '
            'offline and does not depend on a delivery URL staying alive.',
            style: TextStyle(fontSize: 12.5, color: Ink.textFaint, height: 1.5),
          ),
          const SizedBox(height: Ink.s3),
          Wrap(
            spacing: Ink.s2,
            runSpacing: Ink.s2,
            children: [
              for (var i = 0; i < ExportPresets.all.length; i++)
                ChoiceChip(
                  label: Text(ExportPresets.all[i].label),
                  selected: _preset == i,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    color: _preset == i ? Ink.onAccent : Ink.textDim,
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
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gemini Web session',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Ink.text,
                    )),
                SizedBox(height: 2),
                Text(
                  'Used only to write prompt metadata - never for image '
                  'generation.',
                  style: TextStyle(fontSize: 12.5, color: Ink.textFaint),
                ),
              ],
            ),
          ),
          Text(_geminiSummary,
              style: const TextStyle(fontSize: 12.5, color: Ink.textDim)),
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
                color: Ink.text,
              )),
          const SizedBox(height: Ink.s1),
          const Text(
            'Dola has no public API, so the app drives its web page directly. '
            'If Dola ships a redesign, generation breaks with "could not find '
            'the prompt box" - paste corrected CSS selectors here to fix it '
            'without waiting for an app update. Leave empty for the defaults.',
            style: TextStyle(fontSize: 12.5, color: Ink.textFaint, height: 1.5),
          ),
          const SizedBox(height: Ink.s3),
          TextField(
            controller: _selectorCtl,
            maxLines: 10,
            minLines: 4,
            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: DolaSelectors.defaults.toPrettyJson(),
            ),
          ),
          const SizedBox(height: Ink.s3),
          Row(
            children: [
              OutlinedButton(
                onPressed: _saveSelectors,
                child: const Text('Save selectors'),
              ),
              const SizedBox(width: Ink.s2),
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
      color: Ink.canvas,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Image Studio 2.0',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Ink.textDim,
              )),
          SizedBox(height: 4),
          Text(
            'Text-to-image generation for Windows and Android.',
            style: TextStyle(fontSize: 12.5, color: Ink.textFaint),
          ),
        ],
      ),
    );
  }
}
