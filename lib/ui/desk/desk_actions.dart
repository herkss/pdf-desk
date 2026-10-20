import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../services/desk_controller.dart';
import '../../services/pdf_ops.dart' as ops;
import '../../services/storage.dart';
import '../../services/thumbnails.dart';
import '../common/dialogs.dart';
import '../viewer/viewer_screen.dart';

/// User-facing desk operations. Each one works on the current selection
/// unless given explicit entries.
class DeskActions {
  DeskActions(this.context, this.desk);
  final BuildContext context;
  final DeskController desk;

  List<DeskEntry> get _sel => desk.selectedEntries;

  Future<void> _done() async {
    ThumbnailService.instance.invalidate();
    await desk.refresh();
  }

  Future<void> open([DeskEntry? entry]) async {
    final e = entry ?? (_sel.isEmpty ? null : _sel.first);
    if (e == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerScreen(path: e.path, settings: desk.settings),
      ),
    );
    await _done();
  }

  Future<void> importFiles([List<String>? paths, Offset? at]) async {
    var files = paths;
    if (files == null) {
      final picked = await FilePicker.pickFiles(
        dialogTitle: '데스크로 가져오기',
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp', 'tif', 'tiff'],
      );
      files = picked.map((f) => f.path).whereType<String>().toList();
    }
    if (files.isEmpty || !context.mounted) return;
    final importable = files.where(isImportable).toList();
    final skipped = files.length - importable.length;
    final created = await runBusy(context, '가져오는 중… (${importable.length}개)', () async {
      final out = <String>[];
      for (final f in importable) {
        final r = await ops.importFile(f, desk.folder);
        if (r != null) out.add(r);
      }
      return out;
    });
    if (created == null) return;
    desk.place(created, at: at);
    await _done();
    if (skipped > 0 && context.mounted) showInfo(context, '지원하지 않는 파일 $skipped개는 건너뛰었습니다.');
  }

  Future<void> combine([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.length < 2) {
      showInfo(context, '묶을 문서를 2개 이상 선택하세요.');
      return;
    }
    final name = await promptText(context, title: '문서 묶기', label: '새 문서 이름', initial: list.first.title);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final keep = await _askKeepOriginals('묶기');
    if (keep == null || !context.mounted) return;
    final out = await runBusy(context, '문서를 묶는 중…', () async {
      final out = await ops.combine([for (final e in list) e.path], desk.folder, name);
      if (!keep) {
        for (final e in list) {
          await deleteDocument(e.path);
        }
      }
      return out;
    });
    if (out == null) return;
    desk.place([out], at: desk.positionOf(list.first));
    await _done();
    desk.selectOnly(DeskEntry(out));
  }

  Future<void> split([DeskEntry? entry]) async {
    final e = entry ?? (_sel.length == 1 ? _sel.first : null);
    if (e == null || e.isBinder) {
      showInfo(context, '분할할 문서 1개를 선택하세요.');
      return;
    }
    final keep = await _askKeepOriginals('분할');
    if (keep == null || !context.mounted) return;
    final outs = await runBusy(context, '페이지별로 분할하는 중…', () async {
      final outs = await ops.splitPages(e.path, desk.folder);
      if (!keep) await deleteDocument(e.path);
      return outs;
    });
    if (outs == null) return;
    desk.place(outs, at: desk.positionOf(e));
    await _done();
  }

  Future<bool?> _askKeepOriginals(String verb) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('원본 문서'),
      content: Text('$verb 후 원본 문서를 어떻게 할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('원본 삭제')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('원본 유지')),
      ],
    ),
  );

  Future<void> makeBinder([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.isEmpty) {
      showInfo(context, '바인더에 넣을 문서를 선택하세요.');
      return;
    }
    final name = await promptText(context, title: '바인더 만들기', label: '바인더 이름', initial: '새 바인더');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final out = await runBusy(
      context,
      '바인더를 만드는 중…',
      () => ops.createBinder([for (final e in list) e.path], desk.folder, name),
    );
    if (out == null) return;
    desk.place([out], at: desk.positionOf(list.first));
    await _done();
  }

  Future<void> addToBinder(DeskEntry binder, List<String> docs) async {
    final r = await runBusy(context, '바인더에 추가하는 중…', () async {
      await ops.addToBinder(binder.path, docs);
      return true;
    });
    if (r != null) await _done();
  }

  Future<void> unbind([DeskEntry? entry]) async {
    final e = entry ?? (_sel.length == 1 ? _sel.first : null);
    if (e == null || !e.isBinder) {
      showInfo(context, '해제할 바인더를 선택하세요.');
      return;
    }
    final outs = await runBusy(context, '바인더를 해제하는 중…', () => ops.unbind(e.path));
    if (outs == null) return;
    desk.place(outs, at: desk.positionOf(e));
    await _done();
  }

  Future<void> rotate(int quarterTurns) async {
    final docs = _sel.where((e) => !e.isBinder).toList();
    if (docs.isEmpty) return;
    await runBusy(context, '회전하는 중…', () async {
      for (final e in docs) {
        final n = await ops.pageCountOf(e.path);
        await ops.rotatePages(e.path, {for (var i = 0; i < n; i++) i}, quarterTurns);
      }
      return true;
    });
    await _done();
  }

  Future<void> rename([DeskEntry? entry]) async {
    final e = entry ?? (_sel.length == 1 ? _sel.first : null);
    if (e == null) return;
    final name = await promptText(context, title: '이름 바꾸기', initial: e.title);
    if (name == null || name.trim().isEmpty || name == e.title || !context.mounted) return;
    final ext = e.isBinder ? binderExt : '.pdf';
    final target = p.join(desk.folder, '${sanitizeFileName(name)}$ext');
    if (File(target).existsSync() || Directory(target).existsSync()) {
      showInfo(context, '같은 이름이 이미 있습니다.');
      return;
    }
    try {
      await moveDocument(e.path, target);
      desk.renamePosition(e.path, target);
      await _done();
      desk.selectOnly(DeskEntry(target));
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  Future<void> duplicate() async {
    final docs = _sel;
    if (docs.isEmpty) return;
    final outs = await runBusy(context, '복제하는 중…', () async {
      final outs = <String>[];
      for (final e in docs) {
        if (e.isBinder) {
          final target = uniquePath(desk.folder, '${e.title} 복사본', binderExt);
          await Directory(target).create();
          final copied = <String>[];
          for (final d in await binderDocuments(e.path)) {
            final t = p.join(target, p.basename(d));
            await copyDocument(d, t);
            copied.add(t);
          }
          await saveBinderOrder(target, copied);
          outs.add(target);
        } else {
          final target = uniquePath(desk.folder, '${e.title} 복사본', '.pdf');
          await copyDocument(e.path, target);
          outs.add(target);
        }
      }
      return outs;
    });
    if (outs == null) return;
    desk.place(outs, at: desk.positionOf(docs.first));
    await _done();
  }

  Future<void> delete() async {
    final docs = _sel;
    if (docs.isEmpty) return;
    final ok = await confirm(
      context,
      title: '삭제',
      message: docs.length == 1 ? "'${docs.first.title}'을(를) 삭제할까요?" : '${docs.length}개 항목을 삭제할까요?',
      okLabel: '삭제',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runBusy(context, '삭제하는 중…', () async {
      for (final e in docs) {
        await deleteDocument(e.path);
      }
      return true;
    });
    await _done();
  }

  Future<void> exportPdf([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.isEmpty) return;
    final suggested = list.length == 1 ? '${list.first.title}.pdf' : '내보내기.pdf';
    final bytes = await runBusy(context, 'PDF로 내보내는 중…', () => ops.exportFlattened([for (final e in list) e.path]));
    if (bytes == null || !context.mounted) return;
    final saved = await FilePicker.saveFile(
      dialogTitle: 'PDF로 내보내기 (주석 포함)',
      fileName: suggested,
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (saved != null && context.mounted) showInfo(context, '내보냈습니다: ${saved.toFilePath()}');
  }

  Future<void> printDocs([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.isEmpty) return;
    final bytes = await runBusy(context, '인쇄 준비 중…', () => ops.exportFlattened([for (final e in list) e.path]));
    if (bytes == null) return;
    await Printing.layoutPdf(name: list.first.title, onLayout: (_) async => bytes);
  }

  Future<void> revealInExplorer([DeskEntry? entry]) async {
    final e = entry ?? (_sel.isEmpty ? null : _sel.first);
    if (Platform.isWindows) {
      await Process.run('explorer', e == null ? [desk.folder] : ['/select,', e.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', e == null ? [desk.folder] : ['-R', e.path]);
    } else {
      await Process.run('xdg-open', [desk.folder]);
    }
  }

  Future<void> moveToFolder(List<String> paths, String folder) async {
    if (folder == desk.folder) return;
    await runBusy(context, '이동하는 중…', () async {
      for (final path in paths) {
        final ext = isBinderPath(path) ? binderExt : '.pdf';
        await moveDocument(path, uniquePath(folder, p.basenameWithoutExtension(path), ext));
      }
      return true;
    });
    await _done();
  }
}
