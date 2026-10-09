import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Two-tone capsule mark (teal + mint), drawn with Flutter only.
class CapsuleMark extends StatelessWidget {
  const CapsuleMark({super.key, this.size = 24, this.onDark = false});

  /// Length of the capsule's bounding box.
  final double size;

  /// Use light colors on a teal background (e.g. app icon style).
  final bool onDark;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CapsulePainter(onDark: onDark)),
      );
}

class _CapsulePainter extends CustomPainter {
  _CapsulePainter({required this.onDark});
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final length = size.shortestSide;
    final width = length * 0.42;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4); // Subtle diagonal orientation.
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: length, height: width),
      Radius.circular(width / 2),
    );
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(Rect.fromLTRB(-length / 2, -width / 2, 0, width / 2),
        Paint()..color = onDark ? Colors.white : AppColors.primary);
    canvas.drawRect(Rect.fromLTRB(0, -width / 2, length / 2, width / 2),
        Paint()..color = AppColors.mint);
    canvas.restore();
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, length * 0.04)
        ..color = onDark ? Colors.white : AppColors.primaryDark,
    );
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) =>
      oldDelegate.onDark != onDark;
}

/// The IMedsU wordmark: "I" and "U" in dark slate, "Meds" emphasized in teal
/// with a small capsule accent above it.
class IMedsULogo extends StatelessWidget {
  const IMedsULogo({super.key, this.fontSize = 24});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final slate = TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: -0.5,
        height: 1);
    final meds =
        slate.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary);
    // Brand mark: limit scaling so it fits the app bar; content text scales.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Semantics(
        label: 'IMedsU',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('I', style: slate),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: fontSize * 0.05),
                  child: CapsuleMark(size: fontSize * 0.62),
                ),
                Text('Meds', style: meds),
              ],
            ),
            Text('U', style: slate),
          ],
        ),
      ),
    );
  }
}
