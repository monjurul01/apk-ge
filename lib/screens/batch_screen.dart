import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../core/generation.dart';
import '../core/generator_factory.dart';
import '../core/image_io.dart';
import '../distribute.dart';
import '../gemini_api.dart';
import '../gemini_web.dart';
import '../secure_store.dart';
import '../zip_export.dart';
import '../widgets/studio_widgets.dart';
import 'app_shell.dart';

enum JobStatus { queued, running, done, failed, skipped }

class _Job {
  _Job(this.prompt);

  final String prompt;
  JobStatus status = JobStatus.queued;
  GenerationResult? result;
  GenerationException? error;
  int attempts = 0;

  /// AI-written title / tags / category / description, once requested.
  SetMetadata? meta;

  /// Which Gemini surface produced [meta].
  String? metaModel;
}

/// Sequential prompt queue.
///
/// The previous batch screen built multi-image wallpaper *sets* by chaining
/// image-to-image edits off a hidden anchor frame, with a fixed seed so the
/// subject stayed identical across variants. That depended on seed control,
/// explicit aspect ratios and an edit endpoint. The current backend is a
/// chat product with none of those, so the set/arc machinery is gone and
/// this is an honest queue: one prompt in, one image out, run in order.
///
/// The prompt-set vocabulary still lives in `models.dart` so the sets can
/// come back if a backend that supports seeded editing is wired in.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.gallery});

  final SessionGallery gallery;

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final _input = TextEditingController();
  final _jobs = <_Job>[];

  ImageGenerator? _generator;
  bool _running = false;
  bool _cancel = false;
  int _preset = 0;
  String? _stageCaption;

  /// Gemini Web client for metadata, null until a session is saved.
  GeminiWebClient? _gemini;
  bool _writingMeta = false;
  String _metaStatus = '';
  bool _savingZip = false;
  bool _uploading = false;
  String _uploadStatus = '';

  /// Pause between jobs. Free consumer accounts get throttled aggressively,
  /// and a burst of back-to-back prompts is what trips it.
  static const _cooldown = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _input.dispose();
    _generator?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final gen = await buildGenerator();
    int preset = 0;
    try {
      preset = await AppPrefs.lastExport();
    } catch (_) {}
    // Metadata is optional: a missing or broken Gemini session must not
    // stop image generation, so parse failures are swallowed here and
    // surfaced only when metadata is actually requested.
    GeminiWebClient? gemini;
    try {
      final raw = await GeminiWebStore.load();
      if (raw.trim().isNotEmpty) {
        gemini = GeminiWebClient(GeminiWebSession.parse(raw));
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _generator = gen;
      _preset = preset;
      _gemini = gemini;
    });
  }

  // ------------------------------------------------------------ metadata

  /// Writes AI metadata for every finished job that does not have it yet.
  Future<void> _writeMetadata() async {
    final pending =
        _jobs.where((j) => j.result != null && j.meta == null).toList();
    if (pending.isEmpty || _writingMeta) return;

    final web = _gemini;
    if (web == null) {
      _snack('Add a Gemini Web session in Settings first.');
      return;
    }

    setState(() => _writingMeta = true);
    var ok = 0;
    for (var i = 0; i < pending.length; i++) {
      if (!mounted) break;
      final job = pending[i];
      setState(() =>
          _metaStatus = 'Writing metadata ${i + 1} of ${pending.length}...');
      try {
        final gen = await GeminiApi.generate(
          type: 'SINGLE',
          concept: _conceptOf(job.prompt),
          prompt: job.prompt,
          file: _fileNameOf(job),
          web: web,
        );
        if (!mounted) break;
        setState(() {
          job.meta = gen.metadata;
          job.metaModel = gen.model;
        });
        ok++;
      } catch (e) {
        if (mounted) _snack('Metadata failed: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _writingMeta = false;
      _metaStatus = '';
    });
    _snack('Metadata written for $ok of ${pending.length} images.');
  }

  /// First few words of the prompt, used as the concept name.
  String _conceptOf(String prompt) {
    final words = prompt.trim().split(RegExp(r'\s+'));
    return words.take(5).join(' ');
  }

  String _fileNameOf(_Job job) {
    final r = job.result;
    if (r == null) return 'image.jpg';
    return ImageIo.fileNameFor(r, _preset);
  }

  // ------------------------------------------------------------- upload

  /// Uploads every finished image to your own R2 bucket through your
  /// worker, then pushes one queue record per image to the resolved
  /// account's Firebase database. Each image goes to exactly one account.
  Future<void> _publish() async {
    final done = _jobs.where((j) => j.result != null).toList();
    if (done.isEmpty || _uploading) return;

    final DistConfig cfg;
    try {
      cfg = await DistributeStore.load();
    } catch (e) {
      _snack('Could not read the distribution settings: $e');
      return;
    }
    if (cfg.accounts.isEmpty || cfg.r2WorkerUrl.trim().isEmpty) {
      _snack('Add your accounts and R2 worker URL in Settings first.');
      return;
    }

    setState(() {
      _uploading = true;
      _uploadStatus = 'Starting upload...';
    });
    var ok = 0;
    try {
      for (var i = 0; i < done.length; i++) {
        if (!mounted) break;
        final job = done[i];
        final account = await _resolveTarget(cfg, cfg.defaultTarget);
        if (account == null) {
          _snack('No account available for "${cfg.defaultTarget}".');
          break;
        }
        setState(() => _uploadStatus =
            'Uploading ${i + 1} of ${done.length} to ${account.name}...');
        final bytes = ImageIo.bytesFor(job.result!, _preset);
        final name = _fileNameOf(job);
        final url = await uploadFileToR2(
          bytes: bytes,
          fileName: name,
          mime: 'image/jpeg',
          workerUrl: cfg.r2WorkerUrl,
          folder: account.r2Folder,
        );
        final record = buildSetRecord(
          firstName: name,
          firstSize: bytes.length,
          totalSize: bytes.length,
          width: job.result!.width,
          height: job.result!.height,
          contentType: 'wallpaper',
          firstFileUrl: url,
          prompt: job.prompt,
          imageModel: job.result!.modelId,
          metadata: job.meta,
          single: true,
        );
        await pushToDatabase(
          dbUrl: account.dbUrl,
          queuePath: cfg.queuePath,
          record: record,
          secret: account.secret,
        );
        ok++;
      }
    } catch (e) {
      if (mounted) _snack('Upload failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadStatus = '';
        });
      }
    }
    if (mounted) _snack('Uploaded $ok of ${done.length} images.');
  }

  /// Resolves 'spread' to one account via a persisted round-robin over
  /// the spread pool; any other value is matched by account name.
  Future<DistAccount?> _resolveTarget(DistConfig cfg, String target) async {
    if (target != 'spread') {
      for (final a in cfg.accounts) {
        if (a.name == target) return a;
      }
      return null;
    }
    final pool = cfg.spreadAccounts;
    if (pool.isEmpty) return null;
    final cursor = await DistributeStore.spreadCursor();
    await DistributeStore.setSpreadCursor(cursor + 1);
    return pool[cursor % pool.length];
  }

  // ----------------------------------------------------------------- zip

  /// Bundles every finished image plus a metadata.json into one archive.
  Future<void> _saveZip() async {
    final done = _jobs.where((j) => j.result != null).toList();
    if (done.isEmpty || _savingZip) return;

    setState(() => _savingZip = true);
    _snack('Preparing ZIP...');
    try {
      final entries = <ZipEntryData>[];
      final metas = <SetMetadata>[];

      for (final job in done) {
        final name = _fileNameOf(job);
        entries.add(ZipEntryData(
          'images/$name',
          ImageIo.bytesFor(job.result!, _preset),
        ));
        // Jobs without AI metadata still get a row, so the manifest always
        // lines up with the images in the archive.
        metas.add(job.meta ??
            SetMetadata(
              file: name,
              title: '',
              tags: const [],
              category: '',
              description: '',
            ));
        entries.add(ZipEntryData(
          'prompts/${name.replaceAll(RegExp(r'\.[a-z]+$'), '')}.txt',
          utf8.encode(job.prompt),
        ));
      }

      entries.add(ZipEntryData(
        'metadata.json',
        utf8.encode(GeminiApi.metadataJson(metas)),
      ));

      final zipFile = await buildZipFile(
        'ai-studio-${DateTime.now().millisecondsSinceEpoch}.zip',
        entries,
      );
      if (!mounted) return;
      setState(() => _savingZip = false);

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop gets a Save As dialog rather than the mobile share sheet.
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ZIP archive',
          fileName: zipFile.uri.pathSegments.last,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (!mounted) return;
        if (savePath == null) {
          _snack('Save cancelled. The ZIP is at ${zipFile.path}');
          return;
        }
        await zipFile.copy(savePath);
        _snack('Saved ${done.length} images to $savePath');
      } else {
        await Share.shareXFiles([XFile(zipFile.path)]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingZip = false);
      _snack('ZIP failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addPrompts() {
    final lines = _input.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    setState(() {
      _jobs.addAll(lines.map(_Job.new));
      _input.clear();
    });
  }

  Future<void> _run() async {
    final gen = _generator;
    if (gen == null || _running) return;
    final pending = _jobs
        .where((j) => j.status == JobStatus.queued || j.status == JobStatus.failed)
        .toList();
    if (pending.isEmpty) return;

    setState(() {
      _running = true;
      _cancel = false;
    });

    for (final job in pending) {
      if (_cancel) {
        setState(() => job.status = JobStatus.skipped);
        continue;
      }
      setState(() {
        job.status = JobStatus.running;
        job.error = null;
        job.attempts++;
      });

      try {
        final r = await gen.generate(
          prompt: job.prompt,
          onStage: (s) {
            if (mounted) setState(() => _stageCaption = s.label);
          },
        );
        if (!mounted) return;
        setState(() {
          job.result = r;
          job.status = JobStatus.done;
          _stageCaption = null;
        });
        widget.gallery.add(r);
      } on GenerationException catch (e) {
        if (!mounted) return;
        setState(() {
          job.error = e;
          job.status = JobStatus.failed;
          _stageCaption = null;
        });
        // A dead session or a region block will fail every remaining job
        // the same way, so stop instead of burning through the queue.
        if (e.kind == GenerationErrorKind.signedOut ||
            e.kind == GenerationErrorKind.regionBlocked) {
          _snack('Stopped: ${e.message}');
          break;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          job.error = GenerationException(
            GenerationErrorKind.unknown,
            'Failed.',
            detail: '$e',
          );
          job.status = JobStatus.failed;
          _stageCaption = null;
        });
      }

      if (!_cancel && job != pending.last) {
        await Future<void>.delayed(_cooldown);
      }
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _stageCaption = null;
    });
  }

  Future<void> _saveDone() async {
    final done = _jobs.where((j) => j.result != null).toList();
    if (done.isEmpty) return;
    var ok = 0;
    for (final j in done) {
      try {
        await ImageIo.save(j.result!, _preset);
        ok++;
      } catch (_) {}
    }
    _snack('Saved $ok of ${done.length} images');
  }

  int _count(JobStatus s) => _jobs.where((j) => j.status == s).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        const Divider(height: 1, color: Skin.line),
        Expanded(
          child: ListView(
            padding: screenScrollPadding(context, Skin.s4),
            children: [
              _composer(),
              if (_stageCaption != null) ...[
                const SizedBox(height: Skin.s4),
                StageStrip(caption: _stageCaption!),
              ],
              if (_uploadStatus.isNotEmpty) ...[
                const SizedBox(height: Skin.s3),
                StageStrip(caption: _uploadStatus),
              ],
              if (_metaStatus.isNotEmpty) ...[
                const SizedBox(height: Skin.s4),
                StageStrip(caption: _metaStatus),
              ],
              const SizedBox(height: Skin.s5),
              if (_jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: Skin.s6),
                  child: EmptyState(
                    icon: Icons.layers_outlined,
                    title: 'Queue is empty',
                    message:
                        'Paste one prompt per line above, then run the queue. '
                        'Jobs run one at a time with a short pause between '
                        'them to avoid being throttled.',
                  ),
                )
              else ...[
                const SectionLabel('Queue'),
                for (var i = 0; i < _jobs.length; i++) ...[
                  _jobRow(i, _jobs[i]),
                  if (i != _jobs.length - 1) const SizedBox(height: Skin.s2),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Skin.s5, Skin.s4, Skin.s4, Skin.s4),
      child: Row(
        children: [
          const Text('Batch',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: Skin.text,
              )),
          const SizedBox(width: Skin.s3),
          if (_jobs.isNotEmpty)
            Text(
              '${_count(JobStatus.done)} done  /  ${_count(JobStatus.queued)} queued'
              '${_count(JobStatus.failed) > 0 ? '  /  ${_count(JobStatus.failed)} failed' : ''}',
              style: const TextStyle(fontSize: 12.5, color: Skin.textFaint),
            ),
          const Spacer(),
          if (_jobs.any((j) => j.result != null)) ...[
            OutlinedButton.icon(
              onPressed: _writingMeta || _running ? null : _writeMetadata,
              icon: _writingMeta
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sell_outlined, size: 16),
              label: const Text('Write metadata'),
            ),
            const SizedBox(width: Skin.s2),
            OutlinedButton.icon(
              onPressed: _savingZip || _running ? null : _saveZip,
              icon: _savingZip
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_zip_outlined, size: 16),
              label: const Text('ZIP'),
            ),
            const SizedBox(width: Skin.s2),
            OutlinedButton.icon(
              onPressed: _uploading || _running ? null : _publish,
              icon: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Upload'),
            ),
            const SizedBox(width: Skin.s2),
            OutlinedButton.icon(
              onPressed: _saveDone,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Save done'),
            ),
          ],
          const SizedBox(width: Skin.s2),
          if (_running)
            OutlinedButton.icon(
              onPressed: () => setState(() => _cancel = true),
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop'),
            )
          else
            FilledButton.icon(
              onPressed: _jobs.any((j) =>
                      j.status == JobStatus.queued ||
                      j.status == JobStatus.failed)
                  ? _run
                  : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Run queue'),
            ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Add prompts (one per line)'),
          TextField(
            controller: _input,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'Misty pine forest at dawn\n'
                  'Neon alley after rain\n'
                  'Brass orrery on a dark desk',
            ),
          ),
          const SizedBox(height: Skin.s3),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _addPrompts,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add to queue'),
              ),
              const Spacer(),
              if (_jobs.isNotEmpty)
                TextButton(
                  onPressed: _running
                      ? null
                      : () => setState(() => _jobs.clear()),
                  child: const Text('Clear queue'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jobRow(int index, _Job job) {
    final (icon, tone) = switch (job.status) {
      JobStatus.queued => (Icons.schedule, Skin.textFaint),
      JobStatus.running => (Icons.autorenew, Skin.accent),
      JobStatus.done => (Icons.check_circle_outline, Skin.success),
      JobStatus.failed => (Icons.error_outline, Skin.danger),
      JobStatus.skipped => (Icons.remove_circle_outline, Skin.textFaint),
    };

    return Panel(
      padding: const EdgeInsets.all(Skin.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (job.result != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Skin.rSm),
              child: Image.memory(
                job.result!.data,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            )
          else
            Icon(icon, size: 18, color: tone),
          const SizedBox(width: Skin.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: Skin.text),
                ),
                if (job.error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    job.error!.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Skin.danger),
                  ),
                ],
                if (job.meta != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    job.meta!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Skin.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (job.meta!.tagsCsv.isNotEmpty)
                    Text(
                      job.meta!.tagsCsv,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Skin.textFaint,
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (!_running)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() => _jobs.removeAt(index)),
            ),
        ],
      ),
    );
  }
}
