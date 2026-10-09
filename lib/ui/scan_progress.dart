import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Non-dismissible scan progress with stage, elapsed time and Cancel Scan.
class ScanProgressDialog extends StatefulWidget {
  const ScanProgressDialog({
    super.key,
    required this.title,
    required this.stage,
    required this.onCancel,
    this.message,
  });
  final String title;
  final ValueListenable<String> stage;
  final VoidCallback onCancel;
  final String? message;

  @override
  State<ScanProgressDialog> createState() => _ScanProgressDialogState();
}

class _ScanProgressDialogState extends State<ScanProgressDialog> {
  int _seconds = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

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
          Text(widget.title,
              style: textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: widget.stage,
            builder: (_, stage, __) => Text(stage,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.primaryDark),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 6),
          Text('Elapsed: $_seconds s', style: textTheme.bodySmall),
          if (widget.message != null) ...[
            const SizedBox(height: 8),
            Text(widget.message!,
                style: textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel Scan')),
          ),
        ],
      ),
    );
  }
}
