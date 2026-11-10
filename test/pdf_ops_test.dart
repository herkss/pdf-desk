import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/models/annotation.dart';
import 'package:pdf_desk/services/fonts.dart';
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

  test('stacking onto a document and spreading it back out', () async {
    final dir = await Directory(p.join(tmp.path, 'stack')).create();
    final a = await makePdf(dir.path, 'S', ['S1']);
    final b = await makePdf(dir.path, 'T', ['T1', 'T2']);
    await saveAnnotations(b, [
      Annotation(type: AnnotationType.rect, page: 1, points: [const Offset(10, 20), const Offset(110, 70)]),
    ]);

    await ops.stackOnto(a, [b]);
    expect(await pageTexts(a), ['S1', 'T1', 'T2']);
    expect(File(b).existsSync(), isFalse);
    expect((await loadAnnotations(a)).single.page, 2);

    // Undo restores both documents exactly.
    final c = await makePdf(dir.path, 'U', ['U1']);
    final undo = await ops.StackUndo.capture(dir.path, [a, c]);
    await ops.stackOnto(a, [c]);
    expect(await pageTexts(a), ['S1', 'T1', 'T2', 'U1']);
    await undo.restore();
    expect(await pageTexts(a), ['S1', 'T1', 'T2']);
    expect(await pageTexts(c), ['U1']);
    expect((await loadAnnotations(a)).single.page, 2);

    final sheets = await ops.spreadPages(a, dir.path);
    expect(File(a).existsSync(), isFalse);
    expect([for (final s in sheets) p.basename(s)], ['S_01.pdf', 'S_02.pdf', 'S_03.pdf']);
    expect(await pageTexts(sheets[2]), ['T2']);
    expect((await loadAnnotations(sheets[2])).single.page, 0);
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

  test('styled shapes and fonts round-trip and export', () async {
    final a = await makePdf(tmp.path, 'S', ['Styles']);
    final notes = [
      Annotation(
        type: AnnotationType.rect,
        page: 0,
        points: [const Offset(40, 40), const Offset(200, 120)],
        fill: const Color(0x8064B5F6),
        lineStyle: LineStyle.dashed,
      ),
      Annotation(
        type: AnnotationType.ellipse,
        page: 0,
        points: [const Offset(220, 40), const Offset(320, 120)],
        fill: const Color(0xFFFFF59D),
        strokeWidth: 0,
      ),
      Annotation(
        type: AnnotationType.line,
        page: 0,
        points: [const Offset(40, 200), const Offset(300, 200)],
        lineStyle: LineStyle.dashDot,
        heads: 3,
      ),
      Annotation(
        type: AnnotationType.text,
        page: 0,
        points: [const Offset(40, 300), const Offset(300, 330)],
        text: 'STYLED TEXT',
        fontFamily: 'Times New Roman',
        bold: true,
        italic: true,
      ),
    ];
    final back = [for (final n in notes) Annotation.fromJson(n.toJson())];
    expect(back[0].lineStyle, LineStyle.dashed);
    expect(back[0].fill!.toARGB32(), 0x8064B5F6);
    expect(back[1].strokeWidth, 0);
    expect((back[2].startHead, back[2].endHead), (true, true));
    expect((back[3].fontFamily, back[3].bold, back[3].italic), ('Times New Roman', true, true));
    expect(Annotation(type: AnnotationType.arrow, page: 0, points: []).endHead, isTrue);

    await saveAnnotations(a, notes);
    final out = p.join(tmp.path, 'sflat.pdf');
    await File(out).writeAsBytes(await ops.exportFlattened([a]));
    expect((await pageTexts(out)).join(' '), contains('STYLED TEXT'));
  });

  test('stacking moves the originals aside and undoes exactly', () async {
    final folder = await Directory(p.join(tmp.path, 'fast')).create();
    final t = await makePdf(folder.path, 'T', ['T1', 'T2']);
    final a = await makePdf(folder.path, 'A', ['A1']);
    final b = await makePdf(folder.path, 'B', ['B1', 'B2']);
    await saveAnnotations(a, [
      Annotation(type: AnnotationType.pen, page: 0, points: [const Offset(1, 1), const Offset(5, 5)]),
    ]);
    final (undo, pages) = await ops.stackWithUndo(folder.path, t, [a, b]);
    expect(pages, 5);
    expect(await pageTexts(t), ['T1', 'T2', 'A1', 'B1', 'B2']);
    expect((await loadAnnotations(t)).single.page, 2);
    expect(File(a).existsSync() || pendingDeletes.contains(a), isFalse);
    expect(File(b).existsSync(), isFalse);

    await undo.restore();
    expect(await pageTexts(t), ['T1', 'T2']);
    expect(await pageTexts(a), ['A1']);
    expect(await pageTexts(b), ['B1', 'B2']);
    expect((await loadAnnotations(a)).single.page, 0);
    expect(await loadAnnotations(t), isEmpty);
  });

  test('an exported PDF becomes editable again when it comes back to a desk', () async {
    final a = await makePdf(tmp.path, 'Round', ['Body text']);
    await saveAnnotations(a, [
      Annotation(
        type: AnnotationType.text,
        page: 0,
        points: [const Offset(50, 50), const Offset(300, 80)],
        text: 'EDITABLE NOTE',
      ),
      Annotation(
        type: AnnotationType.rect,
        page: 0,
        points: [const Offset(40, 300), const Offset(200, 400)],
        fill: const Color(0x8064B5F6),
        lineStyle: LineStyle.dashed,
      ),
    ]);
    // Out to a folder: the drawings are burned in, readable anywhere.
    final outside = await Directory(p.join(tmp.path, 'outside')).create();
    final copy = p.join(outside.path, 'Round.pdf');
    await File(copy).writeAsBytes(await ops.exportFlattened([a]));
    expect((await pageTexts(copy)).join(' '), contains('EDITABLE NOTE'));

    // Back onto a desk: the same annotations, editable, and not twice.
    final desk = await Directory(p.join(tmp.path, 'desk2')).create();
    final back = (await ops.importFile(copy, desk.path))!;
    final notes = await loadAnnotations(back);
    expect(notes.map((n) => n.type), [AnnotationType.text, AnnotationType.rect]);
    expect(notes.first.text, 'EDITABLE NOTE');
    expect(notes.last.lineStyle, LineStyle.dashed);
    final text = (await pageTexts(back)).join(' ');
    expect(text, contains('Body text'));
    expect(text, isNot(contains('EDITABLE NOTE')));

    // A PDF from anywhere else is left alone.
    final plain = await makePdf(tmp.path, 'Plain', ['x']);
    expect(await ops.restoreEditable(plain), isFalse);
  });

  test('blank documents have the chosen paper', () async {
    final a4 = ops.paperSizes['A4']!;
    final out = await ops.createBlank(tmp.path, '새 문서', Size(a4.height, a4.width), pages: 3);
    expect(p.basename(out), '새 문서.pdf');
    final d = await ops.openPdfInMemory(out);
    expect(d.pages.length, 3);
    expect(d.pages[0].width, closeTo(841.89, 0.5));
    expect(d.pages[0].height, closeTo(595.28, 0.5));
    await d.dispose();
    expect(p.basename(await ops.createBlank(tmp.path, '새 문서', a4)), '새 문서 (2).pdf');
  });

  test('a face is extracted from a font collection', () async {
    final ttc = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (!ttc.existsSync()) return markTestSkipped('no .ttc font here');
    final data = await ttc.readAsBytes();
    final face = extractTtcFace(data, 0)!;
    expect(String.fromCharCodes(face.sublist(0, 4)), 'OTTO');
    expect(face.length, lessThan(data.length));
    expect(extractTtcFace(data, 99), isNull);
  });

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
