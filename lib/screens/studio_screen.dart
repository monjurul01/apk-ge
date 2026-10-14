import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../core/export_presets.dart';
import '../core/generation.dart';
import '../core/generator_factory.dart';
import '../core/image_io.dart';
import '../secure_store.dart';
import '../widgets/studio_widgets.dart';
import 'app_shell.dart';

/// Single-prompt composing surface.
///
/// On a wide window this is a two-pane layout - controls on the left, a
/// large canvas on the right - instead of the previous single scrolling
/// column, so the image is visible while you edit the prompt.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.gallery});

  final SessionGallery gallery;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final _promptCtl = TextEditingController();
  final _scroll = ScrollController();

  ImageGenerator? _generator;
  GenerationResult? _current;
  GenerationException? _error;
  GenerationStage? _stage;
  bool _busy = false;
  bool _ready = false;
  int _preset = 0;
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _promptCtl.dispose();
    _scroll.dispose();
    _generator?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final gen = await buildGenerator();
    final ready = await gen.isReady;
    int preset = 0;
    List<String> history = const [];
    try {
      preset = await AppPrefs.lastExport();
      history = await AppPrefs.history();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _generator = gen;
      _ready = ready;
      _preset = preset;
      _history = history;
    });
  }

  Future<void> _rememberPrompt(String prompt) async {
    final next = [prompt, ..._history.where((p) => p != prompt)].take(30).toList();
    setState(() => _history = next);
    try {
      await AppPrefs.setHistory(next);
    } catch (_) {}
  }

  Future<void> _generate() async {
    final prompt = _promptCtl.text.trim();
    if (prompt.isEmpty || _busy) return;
    final gen = _generator;
    if (gen == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _stage = GenerationStage.connecting;
    });

    try {
      final result = await gen.generate(
        prompt: prompt,
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
      );
      if (!mounted) return;
      setState(() {
        _current = result;
        _busy = false;
        _stage = null;
      });
      widget.gallery.add(result);
      await _rememberPrompt(prompt);
    } on GenerationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
        _stage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = GenerationException(
          GenerationErrorKind.unknown,
          'Something went wrong.',
          detail: '$e',
        );
        _busy = false;
        _stage = null;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final r = _current;
    if (r == null) return;
    try {
      final file = await ImageIo.save(r, _preset);
      _snack('Saved to ${file.path}');
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Future<void> _share() async {
    final r = _current;
    if (r == null) return;
    try {
      await ImageIo.share(r, _preset);
    } catch (e) {
      _snack('Could not share: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(Skin.s5),
              child: _controls(),
            ),
          ),
          const VerticalDivider(width: 1, color: Skin.line),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Skin.s5),
              child: _canvas(),
            ),
          ),
        ],
      );
    }

    return ListView(
      controller: _scroll,
      padding: screenScrollPadding(context, Skin.s4),
      children: [
        _controls(),
        const SizedBox(height: Skin.s4),
        SizedBox(height: 420, child: _canvas()),
      ],
    );
  }

  // --------------------------------------------------------------- panes

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Studio',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Skin.text,
                  )),
            ),
            _backendPill(),
          ],
        ),
        const SizedBox(height: Skin.s5),

        if (!_ready) ...[
          NoticeBar(
            icon: Icons.link_off,
            title: 'No image backend connected',
            message: 'Finish setup in Settings before generating.',
            tone: Skin.info,
          ),
          const SizedBox(height: Skin.s4),
        ],

        const SectionLabel('Prompt'),
        TextField(
          controller: _promptCtl,
          maxLines: 6,
          minLines: 4,
          textInputAction: TextInputAction.newline,
          style: const TextStyle(fontSize: 14, height: 1.5),
          decoration: const InputDecoration(
            hintText: 'A lone lighthouse in a storm, cinematic, volumetric light...',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: Skin.s3),
          _historyChips(),
        ],

        const SizedBox(height: Skin.s4),
        const SectionLabel('Export size'),
        _presetPicker(),

        const SizedBox(height: Skin.s5),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                _busy || _promptCtl.text.trim().isEmpty ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_busy ? 'Generating...' : 'Generate'),
          ),
        ),

        if (_stage != null) ...[
          const SizedBox(height: Skin.s4),
          StageStrip(caption: _stage!.label),
        ],

        if (_error != null) ...[
          const SizedBox(height: Skin.s4),
          NoticeBar(
            icon: _error!.kind == GenerationErrorKind.signedOut
                ? Icons.lock_outline
                : Icons.error_outline,
            title: _error!.title,
            message: _error!.message,
            tone: Skin.danger,
            actionLabel: _error!.detail != null ? 'Details' : null,
            action: _error!.detail != null ? _showDetail : null,
          ),
        ],
      ],
    );
  }

  Widget _backendPill() {
    final gen = _generator;
    final name = gen?.displayName ?? 'Loading...';
    final tone = _ready ? Skin.success : Skin.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Skin.s2, vertical: 5),
      decoration: BoxDecoration(
        color: Skin.raised,
        borderRadius: BorderRadius.circular(Skin.rSm),
        border: Border.all(color: Skin.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(name,
              style: const TextStyle(fontSize: 11.5, color: Skin.textDim)),
        ],
      ),
    );
  }

  Widget _historyChips() {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: Skin.s2),
        itemBuilder: (context, i) {
          final p = _history[i];
          final short = p.length > 28 ? '${p.substring(0, 28)}...' : p;
          return ActionChip(
            label: Text(short, style: const TextStyle(fontSize: 12)),
            onPressed: () {
              _promptCtl.text = p;
              setState(() {});
            },
          );
        },
      ),
    );
  }

  Widget _presetPicker() {
    return Wrap(
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
              fontWeight: _preset == i ? FontWeight.w600 : FontWeight.w400,
            ),
            onSelected: (_) async {
              setState(() => _preset = i);
              try {
                await AppPrefs.setExport(i);
              } catch (_) {}
            },
          ),
      ],
    );
  }

  Widget _canvas() {
    final r = _current;
    return Panel(
      padding: EdgeInsets.zero,
      color: Skin.canvas,
      child: Column(
        children: [
          Expanded(
            child: r == null
                ? EmptyState(
                    icon: Icons.image_outlined,
                    title: _busy ? 'Working...' : 'Nothing generated yet',
                    message: _busy
                        ? (_stage?.label ?? '')
                        : 'Write a prompt and press Generate. The result '
                            'appears here at full size.',
                  )
                : InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Skin.s3),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Skin.rSm),
                          child: Image.memory(r.data, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
          ),
          if (r != null) _inspector(r),
        ],
      ),
    );
  }

  Widget _inspector(GenerationResult r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Skin.s3),
      decoration: const BoxDecoration(
        color: Skin.surface,
        border: Border(top: BorderSide(color: Skin.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.prettyDimensions}  /  ${r.format.toUpperCase()}  /  ${r.prettySize}',
                  style: const TextStyle(fontSize: 12.5, color: Skin.textDim),
                ),
              ),
              IconButton(
                tooltip: 'Copy prompt',
                icon: const Icon(Icons.content_copy, size: 17),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.prompt));
                  _snack('Prompt copied');
                },
              ),
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share, size: 17),
                onPressed: _share,
              ),
              IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.download, size: 18),
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetail() {
    final detail = _error?.detail;
    if (detail == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Technical detail'),
        content: SingleChildScrollView(
          child: SelectableText(
            detail,
            style: const TextStyle(fontSize: 12.5, color: Skin.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
