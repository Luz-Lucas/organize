import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'themes.dart';

export 'themes.dart' show OrgThemeSpec, orgThemes, orgThemeById;

/// Guarda a especificação do tema ativo dentro do [ThemeData], para widgets
/// próprios lerem os tokens crus (glifo, motivo, raios, `line`, `accentText`…).
class OrgTokens extends ThemeExtension<OrgTokens> {
  const OrgTokens(this.spec);

  final OrgThemeSpec spec;

  @override
  OrgTokens copyWith({OrgThemeSpec? spec}) => OrgTokens(spec ?? this.spec);

  /// Temas não se misturam: a troca é instantânea (sem interpolação).
  @override
  OrgTokens lerp(ThemeExtension<OrgTokens>? other, double t) =>
      other is OrgTokens && t >= 0.5 ? other : this;
}

extension OrgTokensX on BuildContext {
  /// Tokens do tema atual: `context.org.line`, `context.org.radiusMd`,
  /// `context.org.accentText`… Cores só por aqui ou por `Theme.of(context)`.
  OrgThemeSpec get org => Theme.of(this).extension<OrgTokens>()!.spec;
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Monta o [ThemeData] escuro de um sistema de design.
///
/// Com [googleFonts] falso (testes), usa a tipografia padrão do Material em
/// vez de carregar fontes.
ThemeData buildOrgTheme(OrgThemeSpec s, {bool googleFonts = true}) {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: s.accentDeep,
    onPrimary: s.onAccent,
    primaryContainer: s.accentSoft,
    onPrimaryContainer: s.accentText,
    secondary: s.secondary,
    onSecondary: s.surface,
    secondaryContainer: s.secondarySoft,
    onSecondaryContainer: s.ink,
    tertiary: s.accent,
    onTertiary: s.surface,
    error: const Color(0xFFF2726B),
    onError: const Color(0xFF1A0000),
    errorContainer: const Color(0xFF4A1F1D),
    onErrorContainer: const Color(0xFFFFD9D6),
    surface: s.surface,
    onSurface: s.ink,
    onSurfaceVariant: s.inkMuted,
    outline: s.line,
    outlineVariant: s.line,
    surfaceContainerLowest: s.surface,
    surfaceContainerLow: _mix(s.surface, s.surfaceRaised, 0.35),
    surfaceContainer: _mix(s.surface, s.surfaceRaised, 0.7),
    surfaceContainerHigh: s.surfaceRaised,
    surfaceContainerHighest: _mix(s.surfaceRaised, s.line, 0.35),
    surfaceTint: Colors.transparent,
  );

  final base = Typography.material2021().white.apply(
        bodyColor: s.ink,
        displayColor: s.ink,
        decorationColor: s.ink,
      );
  TextTheme text = base;
  if (googleFonts) {
    final sans = GoogleFonts.getTextTheme(s.sans, base);
    TextStyle display(TextStyle? st) =>
        GoogleFonts.getFont(s.display, textStyle: st).copyWith(color: s.ink);
    text = sans.copyWith(
      displayLarge: display(sans.displayLarge),
      displayMedium: display(sans.displayMedium),
      displaySmall: display(sans.displaySmall),
      headlineLarge: display(sans.headlineLarge),
      headlineMedium: display(sans.headlineMedium),
      headlineSmall: display(sans.headlineSmall),
      titleLarge: display(sans.titleLarge),
    );
  }
  text = text.copyWith(
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelSmall: text.labelSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w600),
  );

  final radiusSm = BorderRadius.circular(s.radiusSm);
  final radiusMd = BorderRadius.circular(s.radiusMd);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radiusMd, borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: s.surface,
    canvasColor: s.surface,
    dividerColor: s.line,
    dividerTheme: DividerThemeData(color: s.line, thickness: 1, space: 1),
    textTheme: text,
    primaryTextTheme: text,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: s.line)),
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: s.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radiusMd, side: BorderSide(color: s.line)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(s.radiusLg),
        side: BorderSide(color: s.line),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radiusMd, side: BorderSide(color: s.line)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceRaised,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.surfaceRaised,
      contentTextStyle: TextStyle(color: s.ink),
      shape: RoundedRectangleBorder(borderRadius: radiusMd, side: BorderSide(color: s.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surfaceRaised,
      border: border(s.line),
      enabledBorder: border(s.line),
      focusedBorder: border(s.accentText, 1.5),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 1.5),
      labelStyle: TextStyle(color: s.inkMuted),
      hintStyle: TextStyle(color: s.inkMuted),
      floatingLabelStyle: TextStyle(color: s.accentText),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: s.accentDeep,
        foregroundColor: s.onAccent,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: s.accentDeep,
        foregroundColor: s.onAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: s.ink,
        side: BorderSide(color: s.line),
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: s.accentText,
        shape: RoundedRectangleBorder(borderRadius: radiusSm),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.accentDeep,
      foregroundColor: s.onAccent,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.radiusLg)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: s.surfaceRaised,
      selectedColor: s.accentSoft,
      side: BorderSide(color: s.line),
      labelStyle: TextStyle(color: s.ink),
      shape: RoundedRectangleBorder(borderRadius: radiusSm),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: s.inkMuted,
      textColor: s.ink,
      shape: RoundedRectangleBorder(borderRadius: radiusSm),
    ),
    iconTheme: IconThemeData(color: s.inkMuted),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: s.surface,
      indicatorColor: s.accentSoft,
      selectedIconTheme: IconThemeData(color: s.accentText),
      unselectedIconTheme: IconThemeData(color: s.inkMuted),
      selectedLabelTextStyle: TextStyle(color: s.accentText),
      unselectedLabelTextStyle: TextStyle(color: s.inkMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: s.accentSoft,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith((st) =>
          IconThemeData(color: st.contains(WidgetState.selected) ? s.accentText : s.inkMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: st.contains(WidgetState.selected) ? s.accentText : s.inkMuted,
          )),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: s.accentText,
      selectionColor: s.accentDeep.withValues(alpha: 0.45),
      selectionHandleColor: s.accentText,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: s.accentText),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.onAccent : s.inkMuted),
      trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.accentDeep : s.surfaceRaised),
      trackOutlineColor: WidgetStateProperty.all(s.line),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.accentDeep : Colors.transparent),
      checkColor: WidgetStatePropertyAll(s.onAccent),
      side: BorderSide(color: s.inkMuted, width: 1.5),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: s.surfaceRaised,
        borderRadius: radiusSm,
        border: Border.all(color: s.line),
      ),
      textStyle: TextStyle(color: s.ink, fontSize: 12),
    ),
    extensions: [OrgTokens(s)],
  );
}
