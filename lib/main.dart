import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'l10n/l10n.dart';
import 'services/settings.dart';
import 'ui/common/annotation_painter.dart' show annotationFontFallback, annotationFontFamily;
import 'ui/common/ios_theme.dart';
import 'ui/desk/desk_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final settings = await Settings.load();
  runApp(PdfDeskApp(settings: settings));
}

class PdfDeskApp extends StatelessWidget {
  PdfDeskApp({super.key, required this.settings}) {
    appLanguage.value = AppLanguage.byCode(settings.language);
  }

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appLanguage,
      builder: (context, lang, _) => MaterialApp(
        title: 'PDF Desk',
        debugShowCheckedModeBanner: false,
        locale: lang.locale,
        supportedLocales: [for (final l in AppLanguage.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: iosTheme(fontFamily: annotationFontFamily, fontFamilyFallback: annotationFontFallback),
        // A new key rebuilds every screen, so all text switches language.
        home: DeskScreen(key: ValueKey(lang), settings: settings),
      ),
    );
  }
}
