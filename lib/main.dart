import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'l10n/l10n.dart';
import 'services/perf_log.dart';
import 'services/settings.dart';
import 'ui/common/annotation_painter.dart' show annotationFontFallback, annotationFontFamily;
import 'ui/common/app_theme.dart';
import 'ui/desk/desk_screen.dart';
import 'ui/desk/desk_tool_settings.dart';
import 'ui/viewer/tool_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final settings = await Settings.load();
  runApp(PdfDeskApp(settings: settings));
}

class PdfDeskApp extends StatelessWidget {
  PdfDeskApp({super.key, required this.settings}) {
    appLanguage.value = AppLanguage.byCode(settings.language);
    appTheme.value = AppTheme.byName(settings.theme);
    loadToolStyles(settings.toolStyles);
    applyDeskSettings(settings);
    PerfLog.path = settings.logPath;
    PerfLog.write('start ${Platform.operatingSystemVersion}, desk ${settings.rootPath}');
    Timer? save;
    toolStylesChanged = () {
      save?.cancel();
      save = Timer(const Duration(milliseconds: 500), () {
        settings.toolStyles = toolStylesToJson();
        settings.save();
      });
    };
  }

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appLanguage, appTheme]),
      builder: (context, _) => _app(appLanguage.value, appTheme.value),
    );
  }

  Widget _app(AppLanguage lang, AppTheme theme) => MaterialApp(
    title: 'PDF Desk',
    debugShowCheckedModeBanner: false,
    locale: lang.locale,
    supportedLocales: [for (final l in AppLanguage.values) l.locale],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildAppTheme(theme, fontFamily: annotationFontFamily, fontFamilyFallback: annotationFontFallback),
    // A new key rebuilds every screen, so all text switches language.
    home: DeskScreen(key: ValueKey(lang), settings: settings),
  );
}
