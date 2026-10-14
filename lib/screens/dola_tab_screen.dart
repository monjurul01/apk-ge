import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_theme.dart';
import '../core/import_images.dart';
import '../widgets/studio_widgets.dart';
import 'app_shell.dart';

/// Dola in an embedded browser, with an import path back into the app.
///
/// This is a plain browser view, the same shape as [DolaLoginScreen]: the
/// user navigates and types themselves and nothing on the page is driven,
/// read or automated. It exists so the site can be used without leaving the
/// app, and so the saved sign-in is reused instead of asking for it again.
///
/// The hand-off back into the app is deliberately manual:
///
///  1. Generate in the page yourself, exactly as you would in Chrome.
///  2. Save the result with the site's own download button.
///  3. Press Import and pick the saved file.
///
/// Imported files become ordinary [GenerationResult]s, so export presets,
/// Gemini metadata, ZIP export and upload all apply with no special case.
class DolaTabScreen extends StatefulWidget {
  const DolaTabScreen({super.key, required this.gallery});

  final SessionGallery gallery;

  @override
  State<DolaTabScreen> createState() => _DolaTabScreenState();
}

class _DolaTabScreenState extends State<DolaTabScreen>
    with AutomaticKeepAliveClientMixin {
  static const _home = 'https://www.dola.com/chat/create-image';

  InAppWebViewController? _controller;
  final _promptCtl = TextEditingController();

  double _progress = 0;
  String _url = '';
  bool _importing = false;
  int _importedThisRun = 0;

  /// Keeps the page alive across tab switches, so a chat in progress is not
  /// thrown away by going to Gallery and back.
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _promptCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Brings files the user saved from the page into this run's gallery.
  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final out = await ImportedImages.pick(prompt: _promptCtl.text);
      if (!mounted) return;
      if (out.images.isNotEmpty) {
        widget.gallery.addAll(out.images);
        setState(() => _importedThisRun += out.images.length);
      }
      if (out.isEmpty) return; // cancelled: say nothing
      if (out.failures.isEmpty) {
        _snack('Imported ${out.images.length} image(s) into the gallery.');
      } else {
        _snack('Imported ${out.images.length}, skipped '
            '${out.failures.length}: ${out.failures.first}');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Skin.s5, Skin.s4, Skin.s4, Skin.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Dola',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Skin.text,
                  )),
              const SizedBox(width: Skin.s3),
              if (_importedThisRun > 0)
                Text('$_importedThisRun imported',
                    style:
                        const TextStyle(fontSize: 13, color: Skin.textFaint)),
              const Spacer(),
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, size: 19),
                onPressed: () => _controller?.goBack(),
              ),
              IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh, size: 19),
                onPressed: () => _controller?.reload(),
              ),
              IconButton(
                tooltip: 'Back to the image page',
                icon: const Icon(Icons.home_outlined, size: 19),
                onPressed: () => _controller?.loadUrl(
                  urlRequest: URLRequest(url: WebUri(_home)),
                ),
              ),
            ],
          ),
          const SizedBox(height: Skin.s3),
          const NoticeBar(
            icon: Icons.info_outline,
            title: 'Generate here, then import',
            message: 'Use the page below exactly as you would in Chrome, then '
                'save the image with Dola\'s own download button. Press '
                'Import to bring the saved files into the gallery - from '
                'there metadata, ZIP and upload work as usual.',
          ),
          const SizedBox(height: Skin.s3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptCtl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Prompt label for imports (optional)',
                    hintText: 'Used for file names and AI metadata',
                  ),
                ),
              ),
              const SizedBox(width: Skin.s2),
              FilledButton.icon(
                onPressed: _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('Import'),
              ),
            ],
          ),
          const SizedBox(height: Skin.s3),
          SizedBox(
            height: 2,
            child: _progress > 0 && _progress < 1
                ? LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                    backgroundColor: Skin.line,
                  )
                : null,
          ),
          const SizedBox(height: Skin.s2),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Skin.rSm),
                border: Border.all(color: Skin.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_home)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  // Sign-in and share flows open provider popups; without
                  // these the flow dead-ends on a blank frame.
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
                onLoadStop: (c, url) {
                  if (mounted) setState(() => _url = url?.toString() ?? '');
                },
                onUpdateVisitedHistory: (c, url, _) {
                  if (mounted) setState(() => _url = url?.toString() ?? '');
                },
                // Host popups in the same view so the user can finish and
                // come back rather than landing on an empty window.
                onCreateWindow: (c, req) async {
                  final target = req.request.url;
                  if (target == null) return false;
                  await c.loadUrl(urlRequest: URLRequest(url: target));
                  return false;
                },
              ),
            ),
          ),
          const SizedBox(height: Skin.s2),
          Text(
            _url.isEmpty ? _home : _url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Skin.textFaint),
          ),
        ],
      ),
    );
  }
}
