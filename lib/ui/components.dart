import 'package:flutter/material.dart';

import 'app_theme.dart';

enum Tone { info, success, warning, error }

extension ToneColors on Tone {
  Color get color => switch (this) {
        Tone.info => AppColors.primaryDark,
        Tone.success => AppColors.success,
        Tone.warning => AppColors.warning,
        Tone.error => AppColors.error,
      };
  Color get background => switch (this) {
        Tone.info => AppColors.primaryLight,
        Tone.success => AppColors.successLight,
        Tone.warning => AppColors.warningLight,
        Tone.error => AppColors.errorLight,
      };
  IconData get icon => switch (this) {
        Tone.info => Icons.info_outline,
        Tone.success => Icons.check_circle_outline,
        Tone.warning => Icons.warning_amber_rounded,
        Tone.error => Icons.error_outline,
      };
}

/// A small status pill. Always shows an icon and text, never color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge(
      {super.key, required this.label, required this.tone, this.icon});
  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tone.color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon ?? tone.icon, size: 16, color: tone.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    color: tone.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5)),
          ),
        ]),
      );
}

/// Colored message box for warnings, errors, success and information.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.tone,
    this.title,
    this.message,
    this.lines = const [],
    this.action,
  });
  final Tone tone;
  final String? title;
  final String? message;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border(left: BorderSide(color: tone.color, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(tone.icon, color: tone.color),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Text(title!,
                  style: textTheme.titleSmall?.copyWith(
                      color: tone.color, fontWeight: FontWeight.w700)),
            if (message != null)
              Padding(
                padding: EdgeInsets.only(top: title == null ? 0 : 4),
                child: Text(message!, style: textTheme.bodyMedium),
              ),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: textTheme.bodyMedium),
                      Expanded(child: Text(line, style: textTheme.bodyMedium)),
                    ]),
              ),
            if (action != null) action!,
          ]),
        ),
      ]),
    );
  }
}

/// Section title used inside screens and cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
        ],
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
                header: true, child: Text(title, style: textTheme.titleMedium)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: textTheme.bodySmall),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Friendly empty state with an optional primary action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.leading,
    this.action,
  });
  final String title;
  final String message;
  final Widget? leading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(children: [
        leading ??
            const Icon(Icons.medication_outlined,
                size: 64, color: AppColors.primary),
        const SizedBox(height: 16),
        Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message,
            style:
                textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 20),
          action!,
        ],
      ]),
    );
  }
}

/// Non-dismissible progress dialog content for long local AI work.
class ProcessingDialog extends StatelessWidget {
  const ProcessingDialog({super.key, required this.title, this.message});
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(title,
              style: textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}
