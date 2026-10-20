import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/models/annotation.dart';
import 'package:pdf_desk/services/pdf_ops.dart' as ops;
import 'package:pdf_desk/services/storage.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdfium_test_setup.dart';

Future<String> makePdf(String dir, String name, List<String> pageTexts, {bool landscape = false}) async {
  final doc = pw.Document();
  for (final t in pageTexts) {
    doc.addPage(
      pw.Page(
        pageFormat: landscape ? pw_pdf.PdfPageFormat.a4.landscape : pw_pdf.PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Text(t, style: const pw.TextStyle(fontSize: 30))),
      ),
    );
  }
  final path = p.join(dir, '$name.pdf');
  await File(path).writeAsBytes(await doc.save());
  return path;
}

Future<List<String>> pageTexts(String path) async {
  final d = await ops.openPdfInMemory(path);
  try {
    return [for (final pg in d.pages) ((await pg.loadText())?.fullText ?? '').trim()];
  } finally {
    await d.dispose();
  }
}

bool get _koreanFontAvailable =>
    Platform.environment['PDFDESK_FONT'] != null || File(r'C:\Windows\Fonts\malgun.ttf').existsSync();

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pdfdesk_test');
    await initPdfiumForTests(tmp.path);
  });

  tearDownAll(() => tmp.delete(recursive: true));

  test('combine, split, rotate, reorder, delete keep annotations aligned', () async {
    final a = await makePdf(tmp.path, 'A', ['A1', 'A2']);
    final b = await makePdf(tmp.path, 'B', ['B1'], landscape: true);
    await saveAnnotations(a, [
      Annotation(type: AnnotationType.rect, page: 1, points: [const Offset(10, 20), const Offset(110, 70)]),
    ]);
    await saveAnnotations(b, [
      Annotation(type: AnnotationType.text, page: 0, points: [const Offset(5, 5), const Offset(50, 25)], text: 'hi'),
    ]);

    final combined = await ops.combine([a, b], tmp.path, 'AB');
    expect(await pageTexts(combined), ['A1', 'A2', 'B1']);
    final anns = await loadAnnotations(combined);
    expect(anns.map((x) => x.page).toList()..sort(), [1, 2]);

    // Rotate page 2 (index 1, A4 portrait 595x842) clockwise: rect moves.
    await ops.rotatePages(combined, {1}, 1);
    final d = await ops.openPdfInMemory(combined);
    expect(d.pages[1].rotation, PdfPageRotation.clockwise90);
    expect(d.pages[1].width, closeTo(842, 1));
    await d.dispose();
    final rect = (await loadAnnotations(combined)).firstWhere((x) => x.type == AnnotationType.rect);
    // (x,y) -> (h - y, x) with h = 842
    expect(rect.bounds.left, closeTo(842 - 70, 0.5));
    expect(rect.bounds.top, closeTo(10, 0.5));

    await ops.reorderPages(combined, [2, 0, 1]);
    expect(await pageTexts(combined), ['B1', 'A1', 'A2']);
    expect((await loadAnnotations(combined)).firstWhere((x) => x.type == AnnotationType.text).page, 0);

    await ops.deletePages(combined, {0});
    expect(await pageTexts(combined), ['A1', 'A2']);
    expect((await loadAnnotations(combined)).length, 1);

    final parts = await ops.splitPages(combined, tmp.path);
    expect(parts.length, 2);
    expect(await pageTexts(parts[1]), ['A2']);
    expect((await loadAnnotations(parts[1])).length, 1);
    expect((await loadAnnotations(parts[0])).length, 0);
  });

  test('flatten burns annotations into page content', () async {
    final a = await makePdf(tmp.path, 'F', ['Page']);
    await saveAnnotations(a, [
      Annotation(
        type: AnnotationType.text,
        page: 0,
        points: [const Offset(50, 50), const Offset(300, 80)],
        text: 'FLATTENED NOTE',
        fontSize: 16,
      ),
      Annotation(
        type: AnnotationType.pen,
        page: 0,
        points: [const Offset(10, 10), const Offset(100, 100), const Offset(150, 20)],
      ),
      Annotation(
        type: AnnotationType.stamp,
        page: 0,
        points: [const Offset(400, 400), const Offset(464, 464)],
        text: 'OK\n26.10.20\nKim',
      ),
      Annotation(
        type: AnnotationType.marker,
        page: 0,
        points: [const Offset(10, 200), const Offset(200, 200)],
        strokeWidth: 12,
      ),
    ]);
    final bytes = await ops.exportFlattened([a]);
    final out = p.join(tmp.path, 'flat.pdf');
    await File(out).writeAsBytes(bytes);
    final text = (await pageTexts(out)).join(' ');
    expect(text, contains('FLATTENED NOTE'));
    expect(text, contains('Kim'));
    // Text must land near the top of the page (display y=50 → PDF y≈842-66).
    final d = await ops.openPdfInMemory(out);
    final raw = (await d.pages[0].loadText())!;
    final idx = raw.fullText.indexOf('FLATTENED');
    final r = raw.charRects[idx].toRect(page: d.pages[0]);
    expect(r.top, inInclusiveRange(45, 75));
    expect(r.left, inInclusiveRange(48, 60));
    await d.dispose();
  });

  test('flatten respects page rotation', () async {
    final a = await makePdf(tmp.path, 'R', ['Rot']);
    await ops.rotatePages(a, {0}, 1);
    await saveAnnotations(a, [
      Annotation(
        type: AnnotationType.text,
        page: 0,
        points: [const Offset(100, 60), const Offset(300, 90)],
        text: 'ROTATED',
        fontSize: 16,
      ),
    ]);
    final out = p.join(tmp.path, 'rflat.pdf');
    await File(out).writeAsBytes(await ops.exportFlattened([a]));
    final d = await ops.openPdfInMemory(out);
    final raw = (await d.pages[0].loadText())!;
    final idx = raw.fullText.indexOf('ROTATED');
    expect(idx, greaterThanOrEqualTo(0));
    final r = raw.charRects[idx].toRect(page: d.pages[0]);
    expect(r.left, inInclusiveRange(95, 115));
    expect(r.top, inInclusiveRange(55, 85));
    await d.dispose();
  });

  test(
    'flatten writes Korean text with an embedded CJK font',
    () async {
      final a = await makePdf(tmp.path, 'K', ['Korean']);
      await saveAnnotations(a, [
        Annotation(
          type: AnnotationType.sticky,
          page: 0,
          points: [const Offset(40, 40), const Offset(200, 90)],
          text: '검토 완료 했습니다',
          fontSize: 14,
          fill: const Color(0xFFFFF176),
        ),
        Annotation(
          type: AnnotationType.stamp,
          page: 0,
          points: [const Offset(300, 40), const Offset(364, 104)],
          text: '승인\n26.10.20\n홍길동',
        ),
      ]);
      final bytes = await ops.exportFlattened([a]);
      final out = p.join(tmp.path, 'kflat.pdf');
      await File(out).writeAsBytes(bytes);
      final text = (await pageTexts(out)).join(' ');
      expect(text, contains('검토'));
      expect(text, contains('홍길동'));
    },
    skip: _koreanFontAvailable ? null : 'needs a Korean .ttf (set PDFDESK_FONT)',
  );

  test('image import and binders', () async {
    final pngPath = p.join(tmp.path, 'img.png');
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = const Color(0xFFFF0000));
    final image = await recorder.endRecording().toImage(200, 100);
    final png = await image.toByteData(format: ImageByteFormat.png);
    await File(pngPath).writeAsBytes(png!.buffer.asUint8List());
    final folder = await Directory(p.join(tmp.path, 'desk')).create();
    final imported = await ops.importFile(pngPath, folder.path);
    final d = await ops.openPdfInMemory(imported!);
    expect(d.pages.length, 1);
    expect(d.pages[0].width, greaterThan(d.pages[0].height));
    await d.dispose();

    final x = await makePdf(folder.path, 'X', ['X1']);
    final binder = await ops.createBinder([imported, x], folder.path, 'My Binder');
    expect((await binderDocuments(binder)).map(p.basename).toList(), ['img.pdf', 'X.pdf']);
    expect((await ops.pagesOfEntry(binder)).length, 2);
    final out = await ops.unbind(binder);
    expect(out.length, 2);
    expect(Directory(binder).existsSync(), isFalse);
  });
}
