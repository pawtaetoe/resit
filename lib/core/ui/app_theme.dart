import 'package:flutter/material.dart';

/// One place for the app's look so every screen matches, in light and dark.
/// Colours come from the reSIT logo: navy (the "SIT" and the R), teal (the
/// ring and arrow) and orange (the dot on the i).
class AppTheme {
  static const navy = Color(0xFF064B8B);
  static const teal = Color(0xFF1698B6);
  static const orange = Color(0xFFF9922E);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Navy as primary, teal as secondary and orange as tertiary. The main
  /// colours stay close to the logo ("fidelity"); containers and surfaces use
  /// Material's softer tones of each ("tonal spot"), so highlights stay
  /// gentle. Text on every role keeps Material's readable contrast.
  static ColorScheme scheme(Brightness brightness) {
    ColorScheme vivid(Color seed) => ColorScheme.fromSeed(
        seedColor: seed, brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.fidelity);
    ColorScheme soft(Color seed) => ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = soft(navy);
    final n = vivid(navy), t = vivid(teal), o = vivid(orange);
    final ts = soft(teal), os = soft(orange);
    return base.copyWith(
      // The logo's exact navy in light mode (white text on it is ~8.6:1).
      primary: brightness == Brightness.light ? navy : n.primary,
      onPrimary: brightness == Brightness.light ? Colors.white : n.onPrimary,
      secondary: t.primary,
      onSecondary: t.onPrimary,
      secondaryContainer: ts.primaryContainer,
      onSecondaryContainer: ts.onPrimaryContainer,
      tertiary: o.primary,
      onTertiary: o.onPrimary,
      tertiaryContainer: os.primaryContainer,
      onTertiaryContainer: os.onPrimaryContainer,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = AppTheme.scheme(brightness);
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
        // A soft shadow once content scrolls under the title.
        scrolledUnderElevation: 2,
        shadowColor: scheme.shadow.withValues(alpha: 0.4),
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
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape)),
      // Bars, toggles and chips share the buttons' 12 px corners.
      segmentedButtonTheme: SegmentedButtonThemeData(style: SegmentedButton.styleFrom(shape: shape)),
      chipTheme: ChipThemeData(shape: shape),
      // Expanding sections sit inside cards, so no extra lines around them.
      expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
  }
}

/// Spacing used across screens, so they don't each pick their own numbers.
abstract final class Space {
  /// Between sections of a screen.
  static const section = 24.0;

  /// Between cards in a list.
  static const card = 8.0;

  /// Inside a content card.
  static const inset = 16.0;

  /// Inside a dense list row.
  static const dense = 12.0;

  /// Screen edges.
  static const page = 16.0;
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

/// Colours for chart series, from the logo's blue and teal, checked for
/// colour-blind separation, lightness and contrast against the surface in
/// both modes (dataviz palette validator). Use them in this order, never
/// cycled: series 1 is always blue, series 2 always teal.
class ChartColors {
  final Color series1;
  final Color series2;

  /// Gridlines and axis lines: hairline, one step off the surface.
  final Color grid;

  /// Text on charts (axis labels, values) uses text colours, never the series
  /// colour.
  final Color text;
  final Color mutedText;
  final Color surface;

  const ChartColors._(this.series1, this.series2, this.grid, this.text, this.mutedText, this.surface);

  factory ChartColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return ChartColors._(
      dark ? const Color(0xFF3769C4) : const Color(0xFF2563B8),
      dark ? const Color(0xFF25A6B2) : const Color(0xFF1B9AAE),
      scheme.outlineVariant,
      scheme.onSurface,
      scheme.onSurfaceVariant,
      scheme.surfaceContainerLow,
    );
  }
}
