import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_desk/services/print_inbox.dart';
import 'package:pdf_desk/services/storage.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('pdfdesk_inbox'));
  tearDown(() => tmp.delete(recursive: true));

  test('collects only finished print jobs onto the desk', () async {
    final inbox = await Directory(p.join(tmp.path, 'inbox')).create();
    final desk = await Directory(p.join(tmp.path, 'desk')).create();
    final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('printed')));
    final bytes = await doc.save();
    final job = File(printerOutputFile(inbox.path));

    // The spooler is still writing: no %%EOF yet.
    await job.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    expect(await PrintInbox.collect(inbox.path, desk.path, settle: Duration.zero), isEmpty);
    expect(job.existsSync(), isTrue);

    await job.writeAsBytes(bytes);
    final got = await PrintInbox.collect(inbox.path, desk.path, settle: Duration.zero);
    expect(got, hasLength(1));
    expect(p.basename(got.single), startsWith('인쇄_'));
    expect(p.dirname(got.single), desk.path);
    expect(job.existsSync(), isFalse);

    // A second job printed within the same second gets its own name.
    await job.writeAsBytes(bytes);
    final again = await PrintInbox.collect(inbox.path, desk.path, settle: Duration.zero);
    expect(again.single, isNot(got.single));
  });

  test('file operations are retried while a file is briefly locked', () async {
    var calls = 0;
    final r = await retryFileOp(() async {
      if (++calls < 3) throw const PathAccessException('x.pdf', OSError('in use', 32), 'Deletion failed');
      return 'ok';
    });
    expect(r, 'ok');
    expect(calls, 3);
    await expectLater(
      retryFileOp(() async => throw const FileSystemException('always'), attempts: 2),
      throwsA(isA<FileSystemException>()),
    );
  });
}
