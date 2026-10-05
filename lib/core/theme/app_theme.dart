import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_colors.dart';

/// Colours the Material scheme has no slot for, resolved for light or dark.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.card,
    required this.hairline,
    required this.muted,
    required this.subtle,
    required this.accent,
    required this.accentSoft,
    required this.accentOnSoft,
    required this.action,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.skeleton,
  });

  final Color card;
  final Color hairline;
  final Color muted;
  final Color subtle;
  final Color accent;
  final Color accentSoft;
  final Color accentOnSoft;
  final Color action;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color skeleton;

  static const light = Palette(
    card: Colors.white,
    hairline: Brand.stone200,
    muted: Brand.stone600,
    subtle: Brand.stone500,
    accent: Brand.saffron700,
    accentSoft: Brand.saffron50,
    accentOnSoft: Brand.saffron700,
    action: Brand.leaf700,
    success: Brand.leaf700,
    successSoft: Brand.leaf50,
    danger: Brand.chilli,
    dangerSoft: Color(0xFFFEF2F2),
    skeleton: Brand.stone200,
  );

  static const dark = Palette(
    card: Brand.stone900,
    hairline: Brand.stone800,
    muted: Brand.stone300,
    subtle: Brand.stone400,
    accent: Brand.saffron400,
    accentSoft: Color(0xFF3A2416),
    accentOnSoft: Brand.saffron200,
    action: Color(0xFF22A355),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF12301F),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3B1515),
    skeleton: Brand.stone800,
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

abstract final class AppTheme {
  static const radius = 20.0;
  static const fieldRadius = 14.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? Palette.dark : Palette.light;
    final background = isDark ? Brand.stone950 : Brand.cream;
    final onBackground = isDark ? Brand.stone100 : Brand.ink;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.action,
      onPrimary: Colors.white,
      primaryContainer: palette.successSoft,
      onPrimaryContainer: isDark ? Brand.leaf50 : Brand.leaf800,
      secondary: palette.accent,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? palette.accentSoft : Brand.saffron100,
      onSecondaryContainer: isDark ? Brand.saffron200 : Brand.saffron700,
      tertiary: Brand.saffron600,
      onTertiary: Colors.white,
      error: palette.danger,
      onError: Colors.white,
      errorContainer: palette.dangerSoft,
      onErrorContainer: palette.danger,
      surface: background,
      onSurface: onBackground,
      onSurfaceVariant: palette.muted,
      surfaceContainerLowest: palette.card,
      surfaceContainerLow: isDark ? Brand.stone900 : Colors.white,
      surfaceContainer: isDark ? Brand.stone900 : Brand.saffron50,
      surfaceContainerHigh: isDark ? Brand.stone800 : Colors.white,
      surfaceContainerHighest: isDark ? Brand.stone800 : Brand.stone100,
      outline: isDark ? Brand.stone700 : Brand.stone300,
      outlineVariant: palette.hairline,
      inverseSurface: isDark ? Brand.stone100 : Brand.stone900,
      onInverseSurface: isDark ? Brand.stone900 : Brand.stone50,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    final text = _textTheme(onBackground, palette.muted);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    const buttonShape = StadiumBorder();
    const buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 14);
    final buttonText = text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w600);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: 'Inter',
      textTheme: text,
      extensions: [palette],
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onBackground,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Colors.black26,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(side: BorderSide(color: palette.hairline)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.action,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark ? Brand.stone800 : Brand.stone200,
          disabledForegroundColor: isDark ? Brand.stone500 : Brand.stone500,
          minimumSize: const Size(64, 52),
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBackground,
          minimumSize: const Size(64, 52),
          padding: buttonPadding,
          shape: buttonShape,
          side: BorderSide(color: scheme.outline),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          minimumSize: const Size(48, 48),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: palette.action, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: palette.danger, width: 2),
        ),
        labelStyle: TextStyle(color: palette.muted),
        hintStyle: TextStyle(color: palette.subtle),
        errorMaxLines: 3,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.card,
        selectedColor: isDark ? palette.accentSoft : Brand.saffron100,
        side: BorderSide(color: palette.hairline),
        shape: const StadiumBorder(),
        labelStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark ? palette.accentSoft : Brand.saffron100,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium!.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? palette.accentOnSoft : palette.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? palette.accentOnSoft : palette.muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        titleTextStyle: text.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fieldRadius)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.action : null,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.accentOnSoft,
        unselectedLabelColor: palette.muted,
        indicatorColor: palette.accent,
        labelStyle: text.labelLarge!.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.labelLarge,
        dividerColor: palette.hairline,
      ),
      dividerTheme: DividerThemeData(color: palette.hairline, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: palette.muted,
        minVerticalPadding: 12,
        titleTextStyle: text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodyMedium!.copyWith(color: palette.muted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.action : palette.subtle,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.action : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(Color ink, Color muted) {
    TextStyle display(double size, double height, [FontWeight weight = FontWeight.w600]) => TextStyle(
      fontFamily: 'Fraunces',
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: ink,
      letterSpacing: -0.2,
    );
    TextStyle body(double size, double height, FontWeight weight, [Color? color]) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color ?? ink,
    );
    return TextTheme(
      displayLarge: display(44, 1.1),
      displayMedium: display(36, 1.12),
      displaySmall: display(30, 1.15),
      headlineLarge: display(28, 1.2),
      headlineMedium: display(24, 1.22),
      headlineSmall: display(21, 1.25),
      titleLarge: display(20, 1.3),
      titleMedium: body(16, 1.35, FontWeight.w600),
      titleSmall: body(14, 1.35, FontWeight.w600),
      bodyLarge: body(16, 1.5, FontWeight.w400),
      bodyMedium: body(14, 1.45, FontWeight.w400),
      bodySmall: body(12.5, 1.4, FontWeight.w400, muted),
      labelLarge: body(14, 1.2, FontWeight.w600),
      labelMedium: body(12.5, 1.2, FontWeight.w500),
      labelSmall: body(11, 1.2, FontWeight.w600),
    );
  }
}
