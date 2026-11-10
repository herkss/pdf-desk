import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/models/annotation.dart';
import 'package:pdf_desk/services/pdf_ops.dart' as ops;
import 'package:pdf_desk/services/storage.dart';
import 'package:pdf_desk/ui/viewer/region_copy.dart';
import 'package:pdf_desk/ui/viewer/viewer_controller.dart';

import 'pdfium_test_setup.dart';

void main() {
  testWidgets('a copied region pastes into another document and exports', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_clip');
      await initPdfiumForTests(tmp.path);
      Future<String> make(String name, String text) async {
        final doc = pw.Document()
          ..addPage(pw.Page(build: (_) => pw.Center(child: pw.Text(text, style: const pw.TextStyle(fontSize: 40)))));
        final path = p.join(tmp.path, '$name.pdf');
        await File(path).writeAsBytes(await doc.save());
        return path;
      }

      final from = ViewerController(await make('From', 'HELLO REGION'));
      await from.load();
      final size = from.pageSize(0);
      final region = Rect.fromCenter(center: size.center(Offset.zero), width: 400, height: 80);
      final copied = await copyPageRegion(from, 0, region);
      expect(copied, isNotNull);
      final (image, text) = copied!;
      expect(image.type, AnnotationType.image);
      expect(image.bounds, region);
      expect(image.image, isNotEmpty);
      expect(text.replaceAll(' ', ''), contains('HELLOREGION'));

      // Paste into a different document; it is saved with it.
      ViewerController.copyToClipboard([image]);
      final to = ViewerController(await make('To', 'other'));
      await to.load();
      to.paste(0);
      expect(to.annotations.single.type, AnnotationType.image);
      await to.save();
      final saved = (await loadAnnotations(to.path)).single;
      expect(saved.image, image.image);

      // Export burns the picture in as an image.
      final plain = (await ops.exportFlattened([p.join(tmp.path, 'From.pdf')])).length;
      final withImage = await ops.exportFlattened([to.path]);
      expect(withImage.length, greaterThan(plain));
      final out = p.join(tmp.path, 'out.pdf');
      await File(out).writeAsBytes(withImage);
      final d = await ops.openPdfInMemory(out);
      expect(d.pages.length, 1);
      await d.dispose();
      from.dispose();
      to.dispose();
    });
  });
}
