import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_desk/models/annotation.dart';
import 'package:pdf_desk/services/settings.dart';
import 'package:pdf_desk/services/storage.dart';
import 'package:pdf_desk/services/trash.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('pdfdesk_trash'));
  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold it.
    }
  });

  test('deleted documents keep their annotations and come back', () async {
    final folder = await Directory(p.join(root.path, 'sub')).create();
    final doc = p.join(folder.path, 'A.pdf');
    await File(doc).writeAsString('%PDF-1.4 fake');
    await saveAnnotations(doc, [
      Annotation(type: AnnotationType.pen, page: 0, points: [Offset.zero]),
    ]);
    final trash = Trash(root.path);

    final item = await trash.put(doc);
    expect(File(doc).existsSync(), isFalse);
    expect(File(annotationPathFor(doc)).existsSync(), isFalse);
    expect((await trash.list()).single.name, 'A.pdf');

    // Same name taken meanwhile: restored under a new name.
    await File(doc).writeAsString('new');
    final back = await trash.restore(item);
    expect(p.basename(back), 'A (2).pdf');
    expect(await File(back).readAsString(), '%PDF-1.4 fake');
    expect((await loadAnnotations(back)).single.type, AnnotationType.pen);
    expect(await trash.list(), isEmpty);

    await trash.put(back);
    await trash.empty();
    expect(await trash.list(), isEmpty);
  });

  test('the desk folder moves out of OneDrive with everything in it', () async {
    final from = await Directory(p.join(root.path, 'OneDrive', 'Documents', 'PdfDesk')).create(recursive: true);
    expect(Settings.isCloudSynced(from.path), isTrue);
    expect(Settings.isCloudSynced(p.join(root.path, 'PdfDesk')), isFalse);
    await File(p.join(from.path, 'A.pdf')).writeAsString('a');
    await Directory(p.join(from.path, '.pdfdesk', 'annotations')).create(recursive: true);
    await File(p.join(from.path, '.pdfdesk', 'layout.json')).writeAsString('{}');
    await Directory(p.join(from.path, 'Projects')).create();

    final to = await moveDeskRoot(from.path, p.join(root.path, 'PdfDesk'));
    expect(to, p.join(root.path, 'PdfDesk'));
    expect(File(p.join(to, 'A.pdf')).existsSync(), isTrue);
    expect(File(p.join(to, '.pdfdesk', 'layout.json')).existsSync(), isTrue);
    expect(Directory(p.join(to, 'Projects')).existsSync(), isTrue);
    expect(from.existsSync(), isFalse);

    // A target that already has files is left alone.
    final again = await Directory(p.join(root.path, 'OneDrive', 'X')).create(recursive: true);
    await File(p.join(again.path, 'B.pdf')).writeAsString('b');
    expect(p.basename(await moveDeskRoot(again.path, to)), 'PdfDesk (2)');
  });
}
