import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/models/annotation.dart';
import 'package:pdf_desk/services/drag_out.dart';
import 'package:pdf_desk/services/storage.dart';

import 'pdfium_test_setup.dart';

void main() {
  test('dragged-out files keep their names and carry the annotations', () async {
    final tmp = await Directory.systemTemp.createTemp('pdfdesk_dragout');
    await initPdfiumForTests(tmp.path);
    Future<String> make(String name) async {
      final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text(name)));
      final path = p.join(tmp.path, '$name.pdf');
      await File(path).writeAsBytes(await doc.save());
      return path;
    }

    final plain = await make('견적서');
    // Plain PDFs are handed over as they are.
    expect(await DragOut.prepare([plain]), [plain]);

    final noted = await make('회의록');
    await saveAnnotations(noted, [
      Annotation(type: AnnotationType.rect, page: 0, points: [const Offset(10, 10), const Offset(80, 80)]),
    ]);
    final files = await DragOut.prepare([plain, noted]);
    expect(files.map(p.basename), ['견적서.pdf', '회의록.pdf']);
    expect(p.dirname(files[0]), p.dirname(files[1])); // one folder for the shell
    expect(files.every((f) => File(f).existsSync()), isTrue);
    // Exported with the annotations, not a plain copy of the original.
    expect(File(files[1]).readAsBytesSync(), isNot(File(noted).readAsBytesSync()));
    expect(File(noted).existsSync(), isTrue); // the desk keeps its documents
  });
}
