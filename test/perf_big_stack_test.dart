import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/services/pdf_ops.dart' as ops;

import 'pdfium_test_setup.dart';

void main() {
  testWidgets('stacking two big documents is quick', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_bigperf');
      await initPdfiumForTests(tmp.path);
      Future<String> big(String dir, String name) async {
        final doc = pw.Document(compress: false);
        for (var i = 0; i < 24; i++) {
          doc.addPage(
            pw.Page(build: (_) => pw.Column(children: [for (var l = 0; l < 60; l++) pw.Text('$name $i $l lorem ipsum')])),
          );
        }
        final path = p.join(dir, '$name.pdf');
        await File(path).writeAsBytes(await doc.save());
        return path;
      }

      final old = await Directory(p.join(tmp.path, 'old')).create();
      final neu = await Directory(p.join(tmp.path, 'new')).create();
      final o1 = await big(old.path, 'A'), o2 = await big(old.path, 'B');
      final n1 = await big(neu.path, 'A'), n2 = await big(neu.path, 'B');
      final sw = Stopwatch()..start();
      await ops.StackUndo.capture(old.path, [o1, o2]);
      await ops.stackOnto(o1, [o2]);
      await ops.pageCountOf(o1);
      final tOld = sw.elapsedMilliseconds;
      sw.reset();
      final (_, pages) = await ops.stackWithUndo(neu.path, n1, [n2]);
      final tNew = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('PERF 24p+24p (${File(n1).lengthSync() ~/ 1024} KB): before ${tOld}ms, now ${tNew}ms');
      expect(pages, 48);
    });
  });
}
