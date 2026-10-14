import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/generation.dart';
import '../core/image_io.dart';
import '../core/import_images.dart';
import '../secure_store.dart';
import '../widgets/device_mockup.dart';
import '../widgets/studio_widgets.dart';
import 'app_shell.dart';

/// Everything generated this run, newest first.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.gallery});

  final SessionGallery gallery;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  int _cols = 3;
  int _preset = 0;
  bool _savingAll = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cols = await AppPrefs.gridCols();
      final preset = await AppPrefs.lastExport();
      if (!mounted) return;
      setState(() {
        _cols = cols;
        _preset = preset;
      });
    } catch (_) {}
  }

  /// Brings images generated outside the app - for example in the Dola page
  /// itself - into this run's gallery. Imported images are ordinary results
  /// from here on: export presets, metadata, ZIP and upload all apply.
  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final out = await ImportedImages.pick();
      if (!mounted) return;
      if (out.images.isNotEmpty) widget.gallery.addAll(out.images);
      if (out.isEmpty) return;
      if (out.failures.isEmpty) {
        _snack('Imported ${out.images.length} image(s).');
      } else {
        _snack('Imported ${out.images.length}, skipped '
            '${out.failures.length}: ${out.failures.first}');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setCols(int v) async {
    setState(() => _cols = v.clamp(2, 6));
    try {
      await AppPrefs.setGridCols(_cols);
    } catch (_) {}
  }

  Future<void> _saveAll() async {
    final items = widget.gallery.items;
    if (items.isEmpty || _savingAll) return;
    setState(() => _savingAll = true);
    var ok = 0;
    for (final r in items) {
      try {
        await ImageIo.save(r, _preset);
        ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _savingAll = false);
    _snack('Saved $ok of ${items.length} images');
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear gallery?'),
        content: const Text(
          'This only clears the list in the app. Images you already saved '
          'to disk are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes == true) widget.gallery.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.gallery,
      builder: (context, _) {
        final items = widget.gallery.items;
        return Column(
          children: [
            _bar(items.length),
            const Divider(height: 1, color: Skin.line),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.grid_view_outlined,
                      title: 'Gallery is empty',
                      message:
                          'Images you generate in Studio or Batch collect '
                          'here until you close the app.',
                    )
                  : GridView.builder(
                      padding: screenScrollPadding(context, Skin.s4),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _cols,
                        crossAxisSpacing: Skin.s3,
                        mainAxisSpacing: Skin.s3,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _tile(items[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Skin.s5, Skin.s4, Skin.s4, Skin.s4),
      child: Row(
        children: [
          const Text('Gallery',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: Skin.text,
              )),
          const SizedBox(width: Skin.s3),
          Text('$count',
              style: const TextStyle(fontSize: 14, color: Skin.textFaint)),
          const Spacer(),
          IconButton(
            tooltip: 'Fewer columns',
            icon: const Icon(Icons.zoom_in, size: 19),
            onPressed: _cols <= 2 ? null : () => _setCols(_cols - 1),
          ),
          IconButton(
            tooltip: 'More columns',
            icon: const Icon(Icons.zoom_out, size: 19),
            onPressed: _cols >= 6 ? null : () => _setCols(_cols + 1),
          ),
          const SizedBox(width: Skin.s2),
          OutlinedButton.icon(
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
          const SizedBox(width: Skin.s2),
          OutlinedButton.icon(
            onPressed: count == 0 || _savingAll ? null : _saveAll,
            icon: _savingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 16),
            label: const Text('Save all'),
          ),
          const SizedBox(width: Skin.s2),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline, size: 19),
            onPressed: count == 0 ? null : _confirmClear,
          ),
        ],
      ),
    );
  }

  Widget _tile(GenerationResult r) {
    return GestureDetector(
      onTap: () => _open(r),
      child: Container(
        decoration: BoxDecoration(
          color: Skin.surface,
          borderRadius: BorderRadius.circular(Skin.rMd),
          border: Border.all(color: Skin.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(r.data, fit: BoxFit.cover),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Skin.s2,
                  vertical: 6,
                ),
                color: Skin.canvas.withValues(alpha: 0.78),
                child: Text(
                  r.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Skin.textDim),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(GenerationResult r) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(Skin.s4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Image.memory(r.data, fit: BoxFit.contain),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Skin.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.prompt,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Skin.text,
                          height: 1.45,
                        )),
                    const SizedBox(height: Skin.s3),
                    MetaRow('Size', r.prettyDimensions),
                    MetaRow('Format', r.format.toUpperCase()),
                    MetaRow('Weight', r.prettySize),
                    MetaRow('Created', r.createdAt.toString().substring(0, 19)),
                    const SizedBox(height: Skin.s3),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final f = await ImageIo.save(r, _preset);
                              _snack('Saved to ${f.path}');
                            } catch (e) {
                              _snack('Could not save: $e');
                            }
                          },
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Save'),
                        ),
                        const SizedBox(width: Skin.s2),
                        OutlinedButton.icon(
                          onPressed: () => ImageIo.share(r, _preset),
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: const Text('Share'),
                        ),
                        const SizedBox(width: Skin.s2),
                        OutlinedButton.icon(
                          onPressed: () => showDevicePreview(
                            context,
                            image: MemoryImage(r.data),
                            title: r.prompt,
                          ),
                          icon: const Icon(Icons.phone_iphone, size: 16),
                          label: const Text('Preview'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            widget.gallery.remove(r);
                            Navigator.pop(context);
                          },
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
