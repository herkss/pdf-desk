import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS system colors.
abstract final class IosColors {
  static const blue = Color(0xFF007AFF);
  static const red = Color(0xFFFF3B30);
  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9500);

  /// Grouped background (behind cards and lists).
  static const groupedBackground = Color(0xFFF2F2F7);

  /// Bars: toolbars, menus, the status bar.
  static const bar = Color(0xFFF9F9F9);
  static const separator = Color(0xFFC6C6C8);
  static const fill = Color(0x1F787880);
  static const secondaryLabel = Color(0x993C3C43);

  /// The desk surface.
  static const desk = Color(0xFFE5E5EA);
}

/// A thin iOS-style separator line.
const iosHairline = BorderSide(color: IosColors.separator, width: 0.5);

/// Material widgets restyled to look like iOS: system blue, grouped gray
/// backgrounds, white rounded sheets, pill buttons, hairline separators and
/// iOS page transitions.
ThemeData iosTheme({String? fontFamily, List<String>? fontFamilyFallback}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: IosColors.blue,
    primary: IosColors.blue,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDCEBFF),
    onPrimaryContainer: IosColors.blue,
    secondaryContainer: const Color(0xFFDCEBFF),
    onSecondaryContainer: IosColors.blue,
    error: IosColors.red,
    surface: Colors.white,
    surfaceTint: Colors.transparent,
  );
  final rounded10 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  // Styles set in component themes don't inherit the theme's font, so each
  // one names it (otherwise Korean/Japanese/Chinese can show as boxes).
  TextStyle text({double? size, FontWeight? weight, Color? color}) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
  );
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    scaffoldBackgroundColor: IosColors.groupedBackground,
    canvasColor: Colors.white,
    dividerTheme: const DividerThemeData(color: IosColors.separator, thickness: 0.5, space: 1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: IosColors.fill,
    hoverColor: const Color(0x0F000000),
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: text(size: 17, weight: FontWeight.w600, color: Colors.black),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFFFBFBFD),
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: text(size: 13.5, color: Colors.black),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFFFBFBFD)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        textStyle: WidgetStatePropertyAll(text(size: 13.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: IosColors.blue,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        elevation: 0,
        textStyle: text(weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: IosColors.blue, shape: rounded10),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IosColors.blue,
        shape: const StadiumBorder(),
        side: const BorderSide(color: IosColors.separator),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Colors.black87)),
    chipTheme: ChipThemeData(
      backgroundColor: IosColors.fill.withValues(alpha: 0.06),
      selectedColor: IosColors.blue,
      secondarySelectedColor: IosColors.blue,
      checkmarkColor: Colors.white,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: WidgetStateTextStyle.resolveWith(
        (s) => text(size: 13, color: s.contains(WidgetState.selected) ? Colors.white : Colors.black87),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : IosColors.fill.withValues(alpha: 0.08),
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.black87),
        side: const WidgetStatePropertyAll(BorderSide(color: Color(0x1F000000), width: 0.5)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? IosColors.green : const Color(0xFFE9E9EA),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? IosColors.blue : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? IosColors.blue : IosColors.separator,
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: IosColors.blue,
      inactiveTrackColor: const Color(0xFFE5E5EA),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 3, pressedElevation: 4),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFEFEFF4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: IosColors.blue, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF2303033),
      actionTextColor: const Color(0xFF64A8FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      width: 560,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: IosColors.blue),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: const WidgetStatePropertyAll(Color(0x66000000)),
    ),
    listTileTheme: const ListTileThemeData(selectedColor: IosColors.blue, iconColor: Colors.black54),
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: text(size: 13)),
  );
}
