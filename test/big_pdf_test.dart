import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/services/pdf_ops.dart' as ops;
import 'package:pdf_desk/services/thumbnails.dart';

import 'pdfium_test_setup.dart';

/// Documents over 1 MB must open from memory too (see openPdfBytes): read
/// on demand they can hang the PDF worker on Windows.
void main() {
  testWidgets('big documents stack and render', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_big');
      await initPdfiumForTests(tmp.path);
      Future<String> big(String name) async {
        final doc = pw.Document(compress: false);
        for (var i = 0; i < 48; i++) {
          doc.addPage(
            pw.Page(
              build: (_) => pw.Column(
                children: [for (var l = 0; l < 60; l++) pw.Text('$name page $i line $l lorem ipsum dolor sit amet')],
              ),
            ),
          );
        }
        final path = p.join(tmp.path, '$name.pdf');
        await File(path).writeAsBytes(await doc.save());
        return path;
      }

      final a = await big('A'), b = await big('B');
      expect(File(a).lengthSync(), greaterThan(1024 * 1024));
      await ops.stackOnto(a, [b]);
      expect(await ops.pageCountOf(a), 96);
      final t = await ThumbnailService.instance.get(a);
      expect(t?.pageCount, 96);
    });
  });
}
