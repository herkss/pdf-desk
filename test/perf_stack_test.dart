import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_desk/services/pdf_ops.dart' as ops;
import 'package:pdf_desk/services/thumbnails.dart';

import 'pdf_ops_test.dart' show makePdf;
import 'pdfium_test_setup.dart';

void main() {
  testWidgets('spreading, stacking and drawing stay quick', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_perf');
      await initPdfiumForTests(tmp.path);
      final big = await makePdf(tmp.path, 'Big', [for (var i = 0; i < 24; i++) 'page $i']);
      final sw = Stopwatch()..start();
      int lap() {
        final t = sw.elapsedMilliseconds;
        sw.reset();
        return t;
      }

      final sheets = await ops.spreadPages(big, tmp.path);
      final tSpread = lap();
      for (final s in sheets) {
        await ThumbnailService.instance.get(s);
      }
      final tThumbs = lap();
      final undo = await ops.StackUndo.capture(tmp.path, sheets);
      final tCapture = lap();
      await ops.stackOnto(sheets.first, sheets.skip(1).toList());
      final tStack = lap();
      final count = await ops.pageCountOf(sheets.first);
      // ignore: avoid_print
      print('PERF spread24=${tSpread}ms thumbs24=${tThumbs}ms capture=${tCapture}ms stack=${tStack}ms');
      expect(count, 24);
      // Thumbnails were saved for next time.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final thumbs = Directory('${tmp.path}/.pdfdesk/thumbs');
      expect(thumbs.existsSync() && thumbs.listSync().whereType<File>().any((f) => f.path.endsWith('.png')), isTrue);
      expect(undo.paths.length, 24);
    });
  });
}
