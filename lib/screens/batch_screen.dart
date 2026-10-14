import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/generation.dart';
import '../core/generator_factory.dart';
import '../core/image_io.dart';
import '../secure_store.dart';
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
    if (!mounted) return;
    setState(() {
      _generator = gen;
      _preset = preset;
    });
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
        const Divider(height: 1, color: Ink.line),
        Expanded(
          child: ListView(
            padding: screenScrollPadding(context, Ink.s4),
            children: [
              _composer(),
              if (_stageCaption != null) ...[
                const SizedBox(height: Ink.s4),
                StageStrip(caption: _stageCaption!),
              ],
              const SizedBox(height: Ink.s5),
              if (_jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: Ink.s6),
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
                  if (i != _jobs.length - 1) const SizedBox(height: Ink.s2),
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
      padding: const EdgeInsets.fromLTRB(Ink.s5, Ink.s4, Ink.s4, Ink.s4),
      child: Row(
        children: [
          const Text('Batch',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: Ink.text,
              )),
          const SizedBox(width: Ink.s3),
          if (_jobs.isNotEmpty)
            Text(
              '${_count(JobStatus.done)} done  /  ${_count(JobStatus.queued)} queued'
              '${_count(JobStatus.failed) > 0 ? '  /  ${_count(JobStatus.failed)} failed' : ''}',
              style: const TextStyle(fontSize: 12.5, color: Ink.textFaint),
            ),
          const Spacer(),
          if (_jobs.any((j) => j.result != null))
            OutlinedButton.icon(
              onPressed: _saveDone,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Save done'),
            ),
          const SizedBox(width: Ink.s2),
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
          const SizedBox(height: Ink.s3),
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
      JobStatus.queued => (Icons.schedule, Ink.textFaint),
      JobStatus.running => (Icons.autorenew, Ink.accent),
      JobStatus.done => (Icons.check_circle_outline, Ink.success),
      JobStatus.failed => (Icons.error_outline, Ink.danger),
      JobStatus.skipped => (Icons.remove_circle_outline, Ink.textFaint),
    };

    return Panel(
      padding: const EdgeInsets.all(Ink.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (job.result != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Ink.rSm),
              child: Image.memory(
                job.result!.data,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            )
          else
            Icon(icon, size: 18, color: tone),
          const SizedBox(width: Ink.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: Ink.text),
                ),
                if (job.error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    job.error!.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Ink.danger),
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
