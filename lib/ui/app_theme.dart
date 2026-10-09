import 'package:flutter/material.dart';

/// IMedsU brand and status colors. Text colors meet WCAG AA (4.5:1) on white.
class AppColors {
  static const primary = Color(0xFF087F8C); // Teal
  static const primaryDark = Color(0xFF065E68);
  static const primaryLight = Color(0xFFEAF5F8);
  static const mint = Color(0xFFA7E3D5);
  static const background = Color(0xFFF8FAFB);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF1F2937); // Dark slate
  static const textSecondary = Color(0xFF64748B); // Slate gray
  static const outline = Color(0xFF7C8A9E); // 3:1 for field borders
  static const divider = Color(0xFFE2E8F0);
  static const success = Color(0xFF25865A);
  static const successLight = Color(0xFFE7F5EE);
  static const warning = Color(0xFFA96508);
  static const warningLight = Color(0xFFFFF6E6);
  static const error = Color(0xFFB42318);
  static const errorLight = Color(0xFFFDEDEC);
}

class AppTheme {
  static const radius = 14.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.primaryDark,
      secondaryContainer: AppColors.mint,
      onSecondaryContainer: AppColors.text,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.error,
      outline: AppColors.outline,
      outlineVariant: AppColors.divider,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text),
          titleLarge: base.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text),
          titleMedium: base.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: AppColors.text),
          bodyLarge: base.textTheme.bodyLarge
              ?.copyWith(fontSize: 17, height: 1.4, color: AppColors.text),
          bodyMedium: base.textTheme.bodyMedium
              ?.copyWith(fontSize: 15, height: 1.4, color: AppColors.text),
          bodySmall: base.textTheme.bodySmall?.copyWith(
              fontSize: 13, height: 1.35, color: AppColors.textSecondary),
          labelLarge: base.textTheme.labelLarge
              ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    const buttonSize = Size(64, 52);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: text,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 2),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: buttonSize,
            padding: buttonPadding,
            shape: shape,
            textStyle: text.labelLarge),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: buttonSize,
            padding: buttonPadding,
            shape: shape,
            foregroundColor: AppColors.primaryDark,
            side: const BorderSide(color: AppColors.outline),
            textStyle: text.labelLarge),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: AppColors.primaryDark,
            shape: shape,
            textStyle: text.labelLarge),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        extendedTextStyle: text.labelLarge,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.primaryDark),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius - 2),
            borderSide: const BorderSide(color: AppColors.outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius - 2),
            borderSide: const BorderSide(color: AppColors.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius - 2),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: text.bodyMedium,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
        iconColor: AppColors.primaryDark,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primaryLight,
      ),
    );
  }
}
