import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'services/settings.dart';
import 'ui/common/annotation_painter.dart' show annotationFontFallback, annotationFontFamily;
import 'ui/desk/desk_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final settings = await Settings.load();
  runApp(PdfDeskApp(settings: settings));
}

class PdfDeskApp extends StatelessWidget {
  const PdfDeskApp({super.key, required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Desk',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B5797)),
        visualDensity: VisualDensity.compact,
        fontFamily: annotationFontFamily,
        fontFamilyFallback: annotationFontFallback,
        tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
      ),
      home: DeskScreen(settings: settings),
    );
  }
}
