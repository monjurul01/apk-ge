import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Small all-caps section label. Used instead of big headings so the
/// screens stay dense without feeling shouty.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Skin.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A flat bordered panel. The whole UI is built from these - no shadows,
/// no elevation, just hairlines on near-black.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Skin.s4),
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Skin.surface,
        borderRadius: BorderRadius.circular(Skin.rMd),
        border: Border.all(color: borderColor ?? Skin.line),
      ),
      child: child,
    );
  }
}

/// Inline status / error strip.
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = Skin.accent,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color tone;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: tone.withValues(alpha: 0.07),
      borderColor: tone.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(
        horizontal: Skin.s3,
        vertical: Skin.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: Skin.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Skin.text,
                    )),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!,
                      style: const TextStyle(fontSize: 13, color: Skin.textDim)),
                ],
              ],
            ),
          ),
          if (action != null && actionLabel != null) ...[
            const SizedBox(width: Skin.s2),
            TextButton(onPressed: action, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Key/value row used in the result inspector.
class MetaRow extends StatelessWidget {
  const MetaRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: Skin.textFaint)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12.5, color: Skin.text)),
          ),
        ],
      ),
    );
  }
}

/// Empty-state placeholder for the canvas and the gallery.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Skin.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Skin.raised,
                borderRadius: BorderRadius.circular(Skin.rMd),
                border: Border.all(color: Skin.line),
              ),
              child: Icon(icon, color: Skin.textFaint, size: 24),
            ),
            const SizedBox(height: Skin.s4),
            Text(title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Skin.text,
                )),
            const SizedBox(height: Skin.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Skin.textFaint,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin progress strip with a stage caption, shown while generating.
class StageStrip extends StatelessWidget {
  const StageStrip({super.key, required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: const LinearProgressIndicator(minHeight: 3),
        ),
        const SizedBox(height: Skin.s2),
        Text(caption,
            style: const TextStyle(fontSize: 12.5, color: Skin.textDim)),
      ],
    );
  }
}
