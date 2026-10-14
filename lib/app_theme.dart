import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens for the "Darkroom" studio skin.
///
/// Deliberately a single dark palette rather than a seeded light/dark pair:
/// the app is an image tool, and a neutral near-black canvas is the only
/// honest background to judge colour against.
class Ink {
  Ink._();

  /// App background - near black, very slightly blue so it reads as
  /// intentional rather than washed-out grey.
  static const canvas = Color(0xFF0B0B0F);

  /// Default panel.
  static const surface = Color(0xFF141419);

  /// Panel that sits on top of another panel (dialogs, menus, fields).
  static const raised = Color(0xFF1C1C23);

  /// Pressed / selected fill.
  static const sunken = Color(0xFF26262F);

  /// Hairline borders. The whole UI is drawn with these instead of shadows.
  static const line = Color(0xFF2A2A33);
  static const lineBright = Color(0xFF3A3A47);

  static const text = Color(0xFFF4F4F5);
  static const textDim = Color(0xFFA1A1AA);
  static const textFaint = Color(0xFF71717A);

  /// Single accent. Amber reads as "darkroom safelight" and stays legible
  /// on near-black without the vibration a saturated blue would give.
  static const accent = Color(0xFFF5A524);
  static const accentDim = Color(0xFF8A5D12);
  static const onAccent = Color(0xFF1A1205);

  static const danger = Color(0xFFF87171);
  static const success = Color(0xFF4ADE80);
  static const info = Color(0xFF7DD3FC);

  /// Corner radius scale. Tighter than stock Material on purpose.
  static const rSm = 6.0;
  static const rMd = 10.0;
  static const rLg = 14.0;

  /// Spacing scale.
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Ink.accent,
      onPrimary: Ink.onAccent,
      secondary: Ink.info,
      onSecondary: Ink.onAccent,
      surface: Ink.surface,
      onSurface: Ink.text,
      error: Ink.danger,
      onError: Ink.onAccent,
      outline: Ink.line,
      outlineVariant: Ink.lineBright,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Ink.canvas,
      canvasColor: Ink.canvas,
      dividerColor: Ink.line,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: Ink.canvas,
        foregroundColor: Ink.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Ink.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: Ink.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ink.rMd),
          side: const BorderSide(color: Ink.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Ink.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ink.rLg),
          side: const BorderSide(color: Ink.line),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Ink.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ink.rMd),
          side: const BorderSide(color: Ink.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Ink.raised,
        hintStyle: const TextStyle(color: Ink.textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: _field(Ink.line),
        enabledBorder: _field(Ink.line),
        focusedBorder: _field(Ink.accent, width: 1.4),
        errorBorder: _field(Ink.danger),
        focusedErrorBorder: _field(Ink.danger, width: 1.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Ink.accent,
          foregroundColor: Ink.onAccent,
          disabledBackgroundColor: Ink.sunken,
          disabledForegroundColor: Ink.textFaint,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ink.rMd),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Ink.text,
          side: const BorderSide(color: Ink.lineBright),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ink.rMd),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Ink.accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Ink.textDim),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Ink.raised,
        selectedColor: Ink.accent,
        side: const BorderSide(color: Ink.line),
        labelStyle: const TextStyle(fontSize: 13, color: Ink.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ink.rSm),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Ink.raised,
        contentTextStyle: const TextStyle(color: Ink.text, fontSize: 14),
        actionTextColor: Ink.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ink.rMd),
          side: const BorderSide(color: Ink.line),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Ink.canvas,
        indicatorColor: Ink.sunken,
        selectedIconTheme: IconThemeData(color: Ink.accent, size: 22),
        unselectedIconTheme: IconThemeData(color: Ink.textFaint, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: Ink.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Ink.textFaint,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Ink.surface,
        indicatorColor: Ink.sunken,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? Ink.text : Ink.textFaint,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected) ? Ink.accent : Ink.textFaint,
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Ink.accent,
        inactiveTrackColor: Ink.sunken,
        thumbColor: Ink.accent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Ink.accent,
        linearTrackColor: Ink.sunken,
        circularTrackColor: Ink.sunken,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Ink.raised,
          borderRadius: BorderRadius.circular(Ink.rSm),
          border: Border.all(color: Ink.line),
        ),
        textStyle: const TextStyle(color: Ink.text, fontSize: 12),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: Ink.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          color: Ink.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        bodyMedium: TextStyle(color: Ink.text, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: Ink.textDim, fontSize: 13, height: 1.4),
        labelSmall: TextStyle(
          color: Ink.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static OutlineInputBorder _field(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ink.rMd),
        borderSide: BorderSide(color: c, width: width),
      );
}

/// Scroll-view padding that also clears the Android system navigation bar.
///
/// Android 15+ renders edge-to-edge, so the gesture / 3-button bar overlays
/// the app. Adding the [MediaQuery] bottom inset keeps the last widgets
/// fully visible on every screen size, while desktop is unaffected because
/// the inset is zero there.
EdgeInsets screenScrollPadding(BuildContext context, [double base = Ink.s4]) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(base, base, base, base + bottom);
}

/// True when there is room for the rail + a side panel.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;
