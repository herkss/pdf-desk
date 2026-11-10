import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_desk/services/pdf_ops.dart' as ops;
import 'package:pdf_desk/services/thumbnails.dart';

import 'pdf_ops_test.dart' show makePdf;
import 'pdfium_test_setup.dart';

void main() {
  testWidgets('stacking 12 documents and drawing the result is quick', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_perf');
      await initPdfiumForTests(tmp.path);
      final docs = [for (var i = 0; i < 12; i++) await makePdf(tmp.path, 'D$i', ['page $i a', 'page $i b', 'page $i c'])];
      final sw = Stopwatch()..start();
      final undo = await ops.StackUndo.capture(tmp.path, docs);
      final tCapture = sw.elapsedMilliseconds;
      await ops.stackOnto(docs.first, docs.skip(1).toList());
      final tStack = sw.elapsedMilliseconds - tCapture;
      final thumb = await ThumbnailService.instance.get(docs.first).timeout(const Duration(seconds: 20));
      final tThumb = sw.elapsedMilliseconds - tCapture - tStack;
      // ignore: avoid_print
      print('PERF capture=${tCapture}ms stack=${tStack}ms thumb=${tThumb}ms pages=${thumb?.pageCount} size=${File(docs.first).lengthSync()}');
      expect(thumb?.pageCount, 36);
      expect(undo.paths.length, 12);
      expect(p.basename(docs.first), 'D0.pdf');
    });
  });
}
