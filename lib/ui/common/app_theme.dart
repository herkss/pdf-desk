import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Surface and text colors of the desk UI, per theme.
@immutable
class DeskPalette extends ThemeExtension<DeskPalette> {
  const DeskPalette({
    required this.desk,
    required this.bar,
    required this.sidebar,
    required this.pane,
    required this.menu,
    required this.field,
    required this.separator,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.folder,
    required this.radius,
  });

  /// The desk surface the sheets lie on.
  final Color desk;

  /// Toolbars, menu bar and status bar.
  final Color bar;
  final Color sidebar;

  /// Preview pane and other content panes.
  final Color pane;
  final Color menu;

  /// Text field fill.
  final Color field;
  final Color separator;

  /// Text, from strongest to faintest.
  final Color ink, ink2, ink3, ink4;
  final Color folder;

  /// Corner radius of buttons, menus and dialogs.
  final double radius;

  @override
  DeskPalette copyWith() => this;

  @override
  DeskPalette lerp(DeskPalette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension DeskPaletteContext on BuildContext {
  DeskPalette get palette => Theme.of(this).extension<DeskPalette>()!;
  Color get ink => palette.ink;
  Color get ink2 => palette.ink2;
  Color get ink3 => palette.ink3;
  Color get ink4 => palette.ink4;

  /// A thin separator line.
  BorderSide get hairline => BorderSide(color: palette.separator, width: 0.5);
}

/// The app's looks, chosen in 표시 → 테마.
enum AppTheme {
  iosLight,
  iosDark,
  classic,
  paper,
  forest,
  midnight;

  String get label => switch (this) {
    iosLight => tr('iOS 라이트'),
    iosDark => tr('iOS 다크'),
    classic => tr('클래식 (DocuWorks)'),
    paper => tr('종이 (세피아)'),
    forest => tr('포레스트'),
    midnight => tr('미드나이트'),
  };

  /// Sample colors for the theme menu: bar, desk, accent.
  List<Color> get swatch => [_spec.palette.bar, _spec.palette.desk, _spec.primary];

  static AppTheme byName(String? name) => values.firstWhere((t) => t.name == name, orElse: () => iosLight);

  _ThemeSpec get _spec => switch (this) {
    iosLight => const _ThemeSpec(
      brightness: Brightness.light,
      primary: Color(0xFF007AFF),
      accentContainer: Color(0xFFDCEBFF),
      background: Color(0xFFF2F2F7),
      surface: Colors.white,
      palette: DeskPalette(
        desk: Color(0xFFE5E5EA),
        bar: Color(0xFFF9F9F9),
        sidebar: Color(0xFFF2F2F7),
        pane: Colors.white,
        menu: Color(0xFFFBFBFD),
        field: Color(0xFFEFEFF4),
        separator: Color(0xFFC6C6C8),
        ink: Color(0xDD000000),
        ink2: Color(0x8A000000),
        ink3: Color(0x73000000),
        ink4: Color(0x42000000),
        folder: Color(0xFF5AC8FA),
        radius: 10,
      ),
    ),
    iosDark => const _ThemeSpec(
      brightness: Brightness.dark,
      primary: Color(0xFF0A84FF),
      accentContainer: Color(0xFF0B3A6E),
      background: Color(0xFF000000),
      surface: Color(0xFF1C1C1E),
      palette: DeskPalette(
        desk: Color(0xFF111113),
        bar: Color(0xFF1C1C1E),
        sidebar: Color(0xFF1C1C1E),
        pane: Color(0xFF2C2C2E),
        menu: Color(0xFF2C2C2E),
        field: Color(0xFF2C2C2E),
        separator: Color(0xFF38383A),
        ink: Color(0xF2FFFFFF),
        ink2: Color(0x99EBEBF5),
        ink3: Color(0x80EBEBF5),
        ink4: Color(0x4DEBEBF5),
        folder: Color(0xFF64D2FF),
        radius: 10,
      ),
    ),
    classic => const _ThemeSpec(
      brightness: Brightness.light,
      primary: Color(0xFF2B5797),
      accentContainer: Color(0xFFD6E2F3),
      background: Color(0xFFF0F2F5),
      surface: Colors.white,
      palette: DeskPalette(
        desk: Color(0xFFDDE3EA),
        bar: Color(0xFFFAFBFC),
        sidebar: Color(0xFFF7F8FA),
        pane: Color(0xFFF7F8FA),
        menu: Colors.white,
        field: Colors.white,
        separator: Color(0xFFD5D9DE),
        ink: Color(0xDD000000),
        ink2: Color(0x8A000000),
        ink3: Color(0x73000000),
        ink4: Color(0x42000000),
        folder: Color(0xFFF4B400),
        radius: 4,
      ),
    ),
    paper => const _ThemeSpec(
      brightness: Brightness.light,
      primary: Color(0xFF9C5B2E),
      accentContainer: Color(0xFFF1DFC8),
      background: Color(0xFFF6EFE3),
      surface: Color(0xFFFFFBF4),
      palette: DeskPalette(
        desk: Color(0xFFE6D7BF),
        bar: Color(0xFFF8F1E5),
        sidebar: Color(0xFFF3EADB),
        pane: Color(0xFFFFFBF4),
        menu: Color(0xFFFFFBF4),
        field: Color(0xFFEFE5D4),
        separator: Color(0xFFD9C9AE),
        ink: Color(0xFF3B2A1A),
        ink2: Color(0xFF6E5A44),
        ink3: Color(0xFF8C7860),
        ink4: Color(0xFFB8A68C),
        folder: Color(0xFFC98B3B),
        radius: 8,
      ),
    ),
    forest => const _ThemeSpec(
      brightness: Brightness.light,
      primary: Color(0xFF2E7D4F),
      accentContainer: Color(0xFFD3EBDD),
      background: Color(0xFFEFF4F0),
      surface: Colors.white,
      palette: DeskPalette(
        desk: Color(0xFFD5E3D9),
        bar: Color(0xFFF6FAF7),
        sidebar: Color(0xFFEEF4EF),
        pane: Colors.white,
        menu: Colors.white,
        field: Color(0xFFE6EFE8),
        separator: Color(0xFFC3D3C7),
        ink: Color(0xFF1B2A20),
        ink2: Color(0xFF4F6456),
        ink3: Color(0xFF6C8072),
        ink4: Color(0xFFA2B3A7),
        folder: Color(0xFF6FAE5F),
        radius: 12,
      ),
    ),
    midnight => const _ThemeSpec(
      brightness: Brightness.dark,
      primary: Color(0xFF7C9CFF),
      accentContainer: Color(0xFF2A3566),
      background: Color(0xFF0F1426),
      surface: Color(0xFF171D33),
      palette: DeskPalette(
        desk: Color(0xFF0B1020),
        bar: Color(0xFF171D33),
        sidebar: Color(0xFF141A2E),
        pane: Color(0xFF1C2340),
        menu: Color(0xFF222A4A),
        field: Color(0xFF222A4A),
        separator: Color(0xFF2E3758),
        ink: Color(0xFFE6E9F5),
        ink2: Color(0xFFA9B0CC),
        ink3: Color(0xFF8790B0),
        ink4: Color(0xFF575F80),
        folder: Color(0xFF9DB2FF),
        radius: 10,
      ),
    ),
  };
}

class _ThemeSpec {
  const _ThemeSpec({
    required this.brightness,
    required this.primary,
    required this.accentContainer,
    required this.background,
    required this.surface,
    required this.palette,
  });
  final Brightness brightness;
  final Color primary;
  final Color accentContainer;
  final Color background;
  final Color surface;
  final DeskPalette palette;
}

/// The current theme; the app rebuilds when it changes.
final appTheme = ValueNotifier(AppTheme.iosLight);

/// Material widgets restyled per [theme]: accent color, gray grouped
/// backgrounds, rounded sheets, pill buttons, hairline separators and iOS
/// page transitions.
ThemeData buildAppTheme(AppTheme theme, {String? fontFamily, List<String>? fontFamilyFallback}) {
  final spec = theme._spec;
  final pal = spec.palette;
  final dark = spec.brightness == Brightness.dark;
  final primary = spec.primary;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: spec.brightness,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: spec.accentContainer,
    onPrimaryContainer: dark ? Colors.white : primary,
    secondaryContainer: spec.accentContainer,
    onSecondaryContainer: dark ? Colors.white : primary,
    error: const Color(0xFFFF3B30),
    surface: spec.surface,
    onSurface: pal.ink,
    surfaceTint: Colors.transparent,
  );
  final r = pal.radius;
  final fill = dark ? const Color(0x33787880) : const Color(0x1F787880);
  // Styles set in component themes don't inherit the theme's font, so each
  // one names it (otherwise Korean/Japanese/Chinese can show as boxes).
  TextStyle text({double? size, FontWeight? weight, Color? color}) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  );
  final base = ThemeData(brightness: spec.brightness, fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback);
  return base.copyWith(
    colorScheme: scheme,
    extensions: [pal],
    visualDensity: VisualDensity.compact,
    textTheme: base.textTheme.apply(bodyColor: pal.ink, displayColor: pal.ink),
    iconTheme: IconThemeData(color: pal.ink2),
    hintColor: pal.ink3,
    scaffoldBackgroundColor: spec.background,
    canvasColor: pal.menu,
    cardColor: spec.surface,
    dividerColor: pal.separator,
    dividerTheme: DividerThemeData(color: pal.separator, thickness: 0.5, space: 1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: fill,
    hoverColor: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(color: const Color(0xE6303033), borderRadius: BorderRadius.circular(8)),
      textStyle: text(color: Colors.white, size: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: spec.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 4)),
      titleTextStyle: text(size: 17, weight: FontWeight.w600, color: pal.ink),
      contentTextStyle: text(size: 14, color: pal.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: pal.menu,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 2)),
      textStyle: text(size: 13.5, color: pal.ink),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(pal.menu),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 2))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? pal.ink4 : pal.ink),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(r * 0.6))),
        textStyle: WidgetStatePropertyAll(text(size: 13.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: r <= 4 ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)) : const StadiumBorder(),
        elevation: 0,
        textStyle: text(weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        shape: r <= 4 ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)) : const StadiumBorder(),
        side: BorderSide(color: pal.separator),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: pal.ink)),
    // Plain styles: a state-dependent style loses the font when the chip
    // merges it, and CJK labels turn into boxes.
    chipTheme: ChipThemeData(
      backgroundColor: pal.field,
      selectedColor: primary,
      secondarySelectedColor: primary,
      checkmarkColor: Colors.white,
      side: BorderSide(color: pal.separator, width: 0.5),
      shape: r <= 4 ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)) : const StadiumBorder(),
      labelStyle: text(size: 13, color: pal.ink),
      secondaryLabelStyle: text(size: 13, color: Colors.white),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (dark ? pal.pane : Colors.white) : fill.withValues(alpha: 0.08),
        ),
        foregroundColor: WidgetStatePropertyAll(pal.ink),
        side: WidgetStatePropertyAll(BorderSide(color: pal.separator, width: 0.5)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(r - 1))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Color(0xFF34C759) : fill,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : pal.separator),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: primary,
      inactiveTrackColor: pal.separator.withValues(alpha: 0.6),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2, pressedElevation: 3),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: pal.field,
      hintStyle: text(color: pal.ink3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r - 1), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(r - 1), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r - 1),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF2303033),
      contentTextStyle: text(color: Colors.white, size: 14),
      actionTextColor: const Color(0xFF64A8FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 2)),
      elevation: 6,
      width: 560,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(dark ? const Color(0x66FFFFFF) : const Color(0x66000000)),
    ),
    listTileTheme: ListTileThemeData(selectedColor: primary, iconColor: pal.ink2, textColor: pal.ink),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: text(size: 13, color: pal.ink)),
  );
}
