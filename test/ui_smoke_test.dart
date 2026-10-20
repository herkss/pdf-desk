import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/main.dart';
import 'package:pdf_desk/services/settings.dart';
import 'package:pdf_desk/services/storage.dart';
import 'package:pdf_desk/ui/viewer/page_view.dart';

import 'pdfium_test_setup.dart';

Future<void> makePdf(String path, List<String> pages) async {
  final doc = pw.Document();
  for (final t in pages) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text(t))));
  }
  await File(path).writeAsBytes(await doc.save());
}

/// Lets real async work (file IO, PDFium worker) finish between frames.
Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory tmp;
  late Settings settings;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pdfdesk_ui');
    await initPdfiumForTests(tmp.path);
    final root = await Directory(p.join(tmp.path, 'root')).create();
    await makePdf(p.join(root.path, 'Alpha.pdf'), ['a1', 'a2']);
    await makePdf(p.join(root.path, 'Beta.pdf'), ['b1']);
    await Directory(p.join(root.path, 'Projects')).create();
    settings = Settings.at(File(p.join(tmp.path, 'settings.json')), root.path);
  });

  tearDownAll(() => tmp.delete(recursive: true));

  testWidgets('desk shows documents, selects, opens viewer and annotates', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(PdfDeskApp(settings: settings));
    await settle(tester);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget); // folder tree
    expect(find.text('2개 항목'), findsOneWidget);

    // Select by clicking the card.
    await tester.tap(find.text('Alpha'));
    await tester.pump();
    expect(find.text('2개 항목 · 1개 선택'), findsOneWidget);

    // Open with the toolbar button.
    await tester.tap(find.text('열기'));
    await settle(tester, 12);
    expect(find.text('1 / 2'), findsOneWidget);

    // Draw a pen stroke on the first page.
    await tester.tap(find.text('펜'));
    await tester.pump();
    final pageFinder = find.byType(AnnotatedPage).first;
    // A point near the top of the first page (the page is taller than the window).
    final center = tester.getRect(pageFinder).topCenter + const Offset(0, 200);
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(center + Offset(i * 8.0, i * 4.0));
    }
    await gesture.up();
    await tester.pump(const Duration(seconds: 1)); // autosave debounce
    await settle(tester, 4);

    final ctrl = tester.widget<AnnotatedPage>(pageFinder).controller;
    expect(
      ctrl.annotations.single.points.first.dy * tester.getSize(pageFinder).width / ctrl.pageSize(0).width,
      closeTo(center.dy - tester.getRect(pageFinder).top, 1),
    );
    // Select the stroke with the select tool.
    await tester.tap(find.text('선택'));
    await tester.pump();
    await tester.tapAt(center + const Offset(40, 20));
    await tester.pump();
    expect(find.text('선택한 주석 삭제 (1)'), findsOneWidget);

    await settle(tester, 20); // autosave runs real file IO
    final sidecar = File(annotationPathFor(p.join(settings.rootPath, 'Alpha.pdf')));
    expect(sidecar.existsSync(), isTrue);
    expect(sidecar.readAsStringSync(), contains('"pen"'));

    // Back to the desk.
    await tester.tap(find.text('데스크'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1)); // route transition
    expect(find.byType(AnnotatedPage), findsNothing);
    expect(find.text('2개 항목 · 1개 선택'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
