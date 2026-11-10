// Renders the desk and viewer to PNGs for visual review.
// Run: SCREENSHOT_DIR=/some/dir PDFDESK_FONT=/path/to/korean.ttf flutter test test/screenshot_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/l10n/l10n.dart';
import 'package:pdf_desk/main.dart';
import 'package:pdf_desk/models/annotation.dart';
import 'package:pdf_desk/services/settings.dart';
import 'package:pdf_desk/services/storage.dart';
import 'package:pdf_desk/ui/common/app_theme.dart';
import 'package:pdf_desk/ui/common/help.dart';
import 'package:pdf_desk/ui/common/language_menu.dart';
import 'package:pdf_desk/ui/desk/desk_canvas.dart';
import 'package:pdf_desk/ui/viewer/page_view.dart';

import 'pdfium_test_setup.dart';

final _outDir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

Future<void> _makePdf(String path, String title, int pages, {bool landscape = false}) async {
  final doc = pw.Document();
  for (var i = 1; i <= pages; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: landscape ? pdf.PdfPageFormat.a4.landscape : pdf.PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('$title  - page $i', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            for (var l = 0; l < 14; l++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text('Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor $l.'),
              ),
            pw.SizedBox(height: 20),
            pw.Container(height: 120, color: pdf.PdfColors.blue100),
          ],
        ),
      ),
    );
  }
  await File(path).writeAsBytes(await doc.save());
}

Future<void> _settle(WidgetTester tester, [int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(_outDir!, '$name.png')).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('screenshots', (tester) async {
    late Settings settings;
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_shot');
      await initPdfiumForTests(tmp.path);
      final font = Platform.environment['PDFDESK_FONT'];
      if (font != null) await _loadFont('Malgun Gothic', font);
      final sdk = p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
      final icons = Directory(sdk)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('MaterialIcons-Regular.otf'))
          .firstOrNull;
      if (icons != null) await _loadFont('MaterialIcons', icons.path);

      final root = await Directory(p.join(tmp.path, 'PdfDesk')).create();
      await _makePdf(p.join(root.path, '견적서_2026.pdf'), 'Quotation', 3);
      await _makePdf(p.join(root.path, '회의록.pdf'), 'Minutes', 2);
      await _makePdf(p.join(root.path, '계약서 초안.pdf'), 'Contract', 5);
      await _makePdf(p.join(root.path, '도면 A-102.pdf'), 'Drawing', 1, landscape: true);
      final binder = await Directory(p.join(root.path, '2026 상반기 보고서$binderExt')).create();
      await _makePdf(p.join(binder.path, '1월.pdf'), 'January', 2);
      await _makePdf(p.join(binder.path, '2월.pdf'), 'February', 2);
      await Directory(p.join(root.path, '거래처')).create();
      await Directory(p.join(root.path, '프로젝트')).create();
      await saveAnnotations(p.join(root.path, '견적서_2026.pdf'), [
        Annotation(
          type: AnnotationType.marker,
          page: 0,
          points: [const Offset(40, 90), const Offset(330, 90)],
          color: const Color(0xFFFDD835),
          strokeWidth: 14,
        ),
        Annotation(
          type: AnnotationType.sticky,
          page: 0,
          points: [const Offset(380, 120), const Offset(540, 190)],
          color: Colors.black87,
          fill: const Color(0xFFFFF176),
          text: '단가 재확인 필요\n(10/22까지)',
          fontSize: 13,
        ),
        Annotation(
          type: AnnotationType.stamp,
          page: 0,
          points: [const Offset(470, 700), const Offset(540, 770)],
          color: const Color(0xFFD32F2F),
          text: '승인\n26.10.20\n홍길동',
        ),
        Annotation(
          type: AnnotationType.ellipse,
          page: 0,
          points: [const Offset(30, 330), const Offset(330, 380)],
          strokeWidth: 2.5,
        ),
        Annotation(
          type: AnnotationType.arrow,
          page: 0,
          points: [const Offset(420, 300), const Offset(335, 350)],
          strokeWidth: 2.5,
        ),
        Annotation(
          type: AnnotationType.text,
          page: 0,
          points: [const Offset(400, 270), const Offset(560, 292)],
          text: '금액 오타?',
          fontSize: 14,
        ),
        Annotation(
          type: AnnotationType.rect,
          page: 0,
          points: [const Offset(40, 430), const Offset(300, 520)],
          color: const Color(0xFF1E88E5),
          fill: const Color(0x80BBDEFB),
          lineStyle: LineStyle.dashed,
        ),
        Annotation(
          type: AnnotationType.line,
          page: 0,
          points: [const Offset(330, 470), const Offset(540, 470)],
          color: const Color(0xFF43A047),
          strokeWidth: 3,
          lineStyle: LineStyle.dotted,
          heads: 3,
        ),
        Annotation(
          type: AnnotationType.text,
          page: 0,
          points: [const Offset(60, 460), const Offset(280, 490)],
          text: 'Times Bold Italic',
          fontSize: 18,
          fontFamily: 'Times New Roman',
          bold: true,
          italic: true,
          fill: const Color(0xFFFFF59D),
        ),
      ]);
      settings = Settings.at(File(p.join(tmp.path, 'settings.json')), root.path)..stampName = '홍길동';
    });

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: PdfDeskApp(settings: settings),
      ),
    );
    await _settle(tester, 20);
    await tester.tap(find.text('견적서_2026'));
    await tester.pump();
    await _settle(tester, 30);
    await _shot(tester, 'desk');

    await tester.tap(find.text('열기').first);
    await _settle(tester, 25);
    expect(find.text('1 / 3'), findsOneWidget);
    await _shot(tester, 'viewer');

    // Right-click the dashed rectangle and open its properties.
    await tester.tap(find.text('전체 페이지'));
    await _settle(tester, 8);
    await _shot(tester, 'viewer_styles');
    final pageBox = tester.getRect(find.byType(AnnotatedPage).first);
    final scale = pageBox.width / 595.28;
    final g = await tester.startGesture(
      pageBox.topLeft + const Offset(42, 500) * scale,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await _settle(tester, 5);
    await tester.tap(find.text('속성 (색·선·배경·글꼴)…'));
    await _settle(tester, 5);
    expect(find.text('주석 속성'), findsOneWidget);
    await _shot(tester, 'style_dialog');
    await tester.tap(find.byIcon(Icons.palette_outlined).last);
    await _settle(tester, 5);
    await _shot(tester, 'color_picker');

    // Right-click settings of viewer tools.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await _settle(tester, 3);
    nav.pop();
    await _settle(tester, 3);
    for (final (label, name) in [('도장', 'stamp_settings'), ('사각형', 'rect_settings')]) {
      final g2 = await tester.startGesture(
        tester.getCenter(find.text(label).first),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g2.up();
      await _settle(tester, 6);
      await _shot(tester, name);
      expect(tester.takeException(), isNull);
      nav.pop();
      await _settle(tester, 3);
    }

    // Back to the desk, then the language menu and other languages.
    tester.state<NavigatorState>(find.byType(Navigator).first).popUntil((r) => r.isFirst);
    await _settle(tester, 10);
    await tester.tap(find.byType(LanguageMenu));
    await _settle(tester, 8);
    await _shot(tester, 'language_menu');
    await tester.tap(find.text('English').last);
    await _settle(tester, 25);
    await _shot(tester, 'desk_en');
    appLanguage.value = AppLanguage.ja;
    await _settle(tester, 25);
    await _shot(tester, 'desk_ja');
    appLanguage.value = AppLanguage.ko;
    await _settle(tester, 15);

    // Help, about and a dark theme.
    final ctx = tester.element(find.byType(DeskCanvas));
    unawaited(showManual(ctx, chapter: 5));
    await _settle(tester, 8);
    await _shot(tester, 'manual');
    Navigator.of(ctx).pop();
    await _settle(tester, 5);
    unawaited(showAbout(ctx));
    await _settle(tester, 12);
    await _shot(tester, 'about');
    Navigator.of(ctx).pop();
    appTheme.value = AppTheme.iosDark;
    await _settle(tester, 20);
    await _shot(tester, 'desk_dark');
    appTheme.value = AppTheme.paper;
    await _settle(tester, 20);
    await _shot(tester, 'desk_paper');
    appTheme.value = AppTheme.iosLight;
  }, skip: _outDir == null);
}
