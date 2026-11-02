import 'package:flutter/material.dart';

/// One place for the app's look so every screen matches, in light and dark.
class AppTheme {
  static const _seed = Color(0xFF1E5EFF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(padding: buttonPadding, shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(padding: buttonPadding, shape: shape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }
}

/// Status colours taken from the colour scheme, so they work in dark mode.
enum Tone { success, warning, danger, neutral, info }

extension ToneColors on Tone {
  /// Background and foreground for a tinted status surface.
  (Color background, Color foreground) colors(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    switch (this) {
      case Tone.success:
        return dark
            ? (const Color(0xFF1E3A2A), const Color(0xFF9BE3B4))
            : (const Color(0xFFDDF5E5), const Color(0xFF14532D));
      case Tone.warning:
        return dark
            ? (const Color(0xFF3D3015), const Color(0xFFFFD98A))
            : (const Color(0xFFFFF1CC), const Color(0xFF6B4A00));
      case Tone.danger:
        return (scheme.errorContainer, scheme.onErrorContainer);
      case Tone.info:
        return (scheme.primaryContainer, scheme.onPrimaryContainer);
      case Tone.neutral:
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    }
  }
}
