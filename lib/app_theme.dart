import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens for the "Darkroom" studio skin.
///
/// Deliberately a single dark palette rather than a seeded light/dark pair:
/// the app is an image tool, and a neutral near-black canvas is the only
/// honest background to judge colour against.
class Skin {
  Skin._();

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
      primary: Skin.accent,
      onPrimary: Skin.onAccent,
      secondary: Skin.info,
      onSecondary: Skin.onAccent,
      surface: Skin.surface,
      onSurface: Skin.text,
      error: Skin.danger,
      onError: Skin.onAccent,
      outline: Skin.line,
      outlineVariant: Skin.lineBright,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Skin.canvas,
      canvasColor: Skin.canvas,
      dividerColor: Skin.line,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: Skin.canvas,
        foregroundColor: Skin.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Skin.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: Skin.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skin.rMd),
          side: const BorderSide(color: Skin.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Skin.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skin.rLg),
          side: const BorderSide(color: Skin.line),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Skin.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skin.rMd),
          side: const BorderSide(color: Skin.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Skin.raised,
        hintStyle: const TextStyle(color: Skin.textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: _field(Skin.line),
        enabledBorder: _field(Skin.line),
        focusedBorder: _field(Skin.accent, width: 1.4),
        errorBorder: _field(Skin.danger),
        focusedErrorBorder: _field(Skin.danger, width: 1.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Skin.accent,
          foregroundColor: Skin.onAccent,
          disabledBackgroundColor: Skin.sunken,
          disabledForegroundColor: Skin.textFaint,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Skin.rMd),
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
          foregroundColor: Skin.text,
          side: const BorderSide(color: Skin.lineBright),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Skin.rMd),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Skin.accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Skin.textDim),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Skin.raised,
        selectedColor: Skin.accent,
        side: const BorderSide(color: Skin.line),
        labelStyle: const TextStyle(fontSize: 13, color: Skin.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skin.rSm),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Skin.raised,
        contentTextStyle: const TextStyle(color: Skin.text, fontSize: 14),
        actionTextColor: Skin.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Skin.rMd),
          side: const BorderSide(color: Skin.line),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Skin.canvas,
        indicatorColor: Skin.sunken,
        selectedIconTheme: IconThemeData(color: Skin.accent, size: 22),
        unselectedIconTheme: IconThemeData(color: Skin.textFaint, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: Skin.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Skin.textFaint,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Skin.surface,
        indicatorColor: Skin.sunken,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? Skin.text : Skin.textFaint,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected) ? Skin.accent : Skin.textFaint,
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Skin.accent,
        inactiveTrackColor: Skin.sunken,
        thumbColor: Skin.accent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Skin.accent,
        linearTrackColor: Skin.sunken,
        circularTrackColor: Skin.sunken,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Skin.raised,
          borderRadius: BorderRadius.circular(Skin.rSm),
          border: Border.all(color: Skin.line),
        ),
        textStyle: const TextStyle(color: Skin.text, fontSize: 12),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: Skin.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: TextStyle(
          color: Skin.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        bodyMedium: TextStyle(color: Skin.text, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: Skin.textDim, fontSize: 13, height: 1.4),
        labelSmall: TextStyle(
          color: Skin.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static OutlineInputBorder _field(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Skin.rMd),
        borderSide: BorderSide(color: c, width: width),
      );
}

/// Scroll-view padding that also clears the Android system navigation bar.
///
/// Android 15+ renders edge-to-edge, so the gesture / 3-button bar overlays
/// the app. Adding the [MediaQuery] bottom inset keeps the last widgets
/// fully visible on every screen size, while desktop is unaffected because
/// the inset is zero there.
EdgeInsets screenScrollPadding(BuildContext context, [double base = Skin.s4]) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(base, base, base, base + bottom);
}

/// True when there is room for the rail + a side panel.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;
