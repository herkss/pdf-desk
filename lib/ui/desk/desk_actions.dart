import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../services/desk_controller.dart';
import '../../services/pdf_ops.dart' as ops;
import '../../services/storage.dart';
import '../../services/thumbnails.dart';
import '../../services/trash.dart';
import '../common/dialogs.dart';
import 'new_document_dialog.dart';
import 'trash_dialog.dart';
import '../viewer/viewer_screen.dart';
import '../../l10n/l10n.dart';

/// User-facing desk operations. Each one works on the current selection
/// unless given explicit entries.
class DeskActions {
  DeskActions(this.context, this.desk);
  final BuildContext context;
  final DeskController desk;

  List<DeskEntry> get _sel => desk.selectedEntries;

  Future<void> _done() => desk.refreshAfterChange();

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
        dialogTitle: tr('데스크로 가져오기'),
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp', 'tif', 'tiff'],
      );
      files = picked.map((f) => f.path).whereType<String>().toList();
    }
    if (files.isEmpty || !context.mounted) return;
    final importable = files.where(isImportable).toList();
    final skipped = files.length - importable.length;
    final created = await runBusy(context, tr('가져오는 중… ({n}개)', {'n': importable.length}), () async {
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
    if (skipped > 0 && context.mounted) showInfo(context, tr('지원하지 않는 파일 {n}개는 건너뛰었습니다.', {'n': skipped}));
  }

  /// 새 문서: asks for the paper and lays a blank document at [at].
  Future<void> newDocument([Offset? at]) async {
    final r = await showNewDocumentDialog(context);
    if (r == null || !context.mounted) return;
    final out = await runBusy(
      context,
      tr('만드는 중…'),
      () => ops.createBlank(desk.folder, r.name, r.size, pages: r.pages),
    );
    if (out == null) return;
    desk.place([out], at: at);
    await _done();
    desk.selectPaths([out]);
  }

  Future<void> combine([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.length < 2) {
      showInfo(context, tr('묶을 문서를 2개 이상 선택하세요.'));
      return;
    }
    final name = await promptText(context, title: tr('문서 묶기'), label: tr('새 문서 이름'), initial: list.first.title);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final keep = await _askKeepOriginals(tr('묶기'));
    if (keep == null || !context.mounted) return;
    final out = await runBusy(context, tr('문서를 묶는 중…'), () async {
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
      showInfo(context, tr('분할할 문서 1개를 선택하세요.'));
      return;
    }
    final keep = await _askKeepOriginals(tr('분할'));
    if (keep == null || !context.mounted) return;
    final outs = await runBusy(context, tr('페이지별로 분할하는 중…'), () async {
      final outs = await ops.splitPages(e.path, desk.folder);
      if (!keep) await deleteDocument(e.path);
      return outs;
    });
    if (outs == null) return;
    desk.place(outs, at: desk.positionOf(e));
    await _done();
  }

  /// 펼치기: deals documents out as one sheet per page, each document on its
  /// own row starting where the first one lay. Binders are unbound the same
  /// way. 겹치기 puts sheets back together.
  Future<void> spread([DeskEntry? entry]) async {
    final list = entry != null ? [entry] : _sel;
    if (list.isEmpty) {
      showInfo(context, tr('펼칠 문서를 선택하세요.'));
      return;
    }
    final origin = list.map(desk.positionOf).reduce((a, b) => a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx) ? a : b);
    final groups = await runBusy(context, tr('낱장으로 펼치는 중…'), () async {
      final groups = <List<String>>[];
      for (final e in list) {
        if (e.isBinder) {
          groups.add(await ops.unbind(e.path));
        } else if (await ops.pageCountOf(e.path) > 1) {
          groups.add(
            desk.settings.spreadKeepsOriginal
                ? await ops.splitPages(e.path, desk.folder)
                : await ops.spreadPages(e.path, desk.folder),
          );
        }
      }
      return groups;
    });
    if (groups == null) return;
    if (groups.isEmpty) {
      if (context.mounted) showInfo(context, tr('한 장짜리 문서는 펼칠 수 없습니다.'));
      return;
    }
    desk.placeSpreadRows(groups, origin);
    await _done();
    desk.selectPaths([for (final g in groups) ...g]);
  }

  /// Lays documents printed to the "PDF Desk" printer on the desk, spread out
  /// one sheet per page if the user chose so.
  Future<void> receivePrinted(List<String> paths) async {
    final placed = <String>[];
    try {
      for (final path in paths) {
        desk.place([path]);
        if (desk.settings.spreadPrinted && await ops.pageCountOf(path) > 1) {
          final origin = desk.positionOf(DeskEntry(path));
          final sheets = await ops.spreadPages(path, p.dirname(path));
          desk.placeSpread(sheets, origin);
          placed.addAll(sheets);
        } else {
          placed.add(path);
        }
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
    await _done();
    desk.selectPaths(placed);
    if (context.mounted && paths.isNotEmpty) {
      showInfo(
        context,
        paths.length == 1 ? tr('인쇄한 문서를 데스크에 놓았습니다.') : tr('인쇄한 문서 {n}개를 데스크에 놓았습니다.', {'n': paths.length}),
      );
    }
  }

  /// 겹치기: puts [sources] on [target] — their pages are appended to it.
  /// Dropping onto a binder adds them to the binder instead.
  Future<void> stackOnto(DeskEntry target, List<String> sources) async {
    if (target.isBinder) {
      await addToBinder(target, sources);
      return;
    }
    final before = {
      for (final s in [target.path, ...sources]) p.basename(s): desk.layout.positions[p.basename(s)],
    };
    // The previous 겹치기 can't be undone any more; drop its 실행 취소 now.
    final messenger = ScaffoldMessenger.maybeOf(context)?..removeCurrentSnackBar();
    final result = await runBusy(context, tr('문서를 겹치는 중…'), () => ops.stackWithUndo(desk.folder, target.path, sources));
    if (result == null) return;
    final (undo, pages) = result;
    await _done();
    desk.selectOnly(target);
    messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr("'{title}'에 겹쳤습니다 (모두 {pages}쪽)", {'title': target.title, 'pages': pages})),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: tr('실행 취소'), onPressed: () => _undoStack(undo, before)),
        ),
      );
  }

  /// Undoes a 겹치기 without needing this widget's context any more (the
  /// dragged documents' cards are gone by then).
  Future<void> _undoStack(ops.StackUndo undo, Map<String, Offset?> positions) async {
    try {
      await undo.restore();
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    desk.animateLayout();
    positions.forEach((name, pos) {
      if (pos != null) desk.layout.positions[name] = pos;
    });
    ThumbnailService.instance.invalidate();
    await desk.refresh();
    desk.selectPaths(undo.paths);
  }

  /// 겹치기 for the selection: everything goes onto the first selected item.
  Future<void> stackSelection() async {
    final list = _sel;
    if (list.length < 2) {
      showInfo(context, tr('겹칠 문서를 2개 이상 선택하세요.'));
      return;
    }
    await stackOnto(list.first, [for (final e in list.skip(1)) e.path]);
  }

  Future<bool?> _askKeepOriginals(String verb) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('원본 문서')),
      content: Text(tr('{verb} 후 원본 문서를 어떻게 할까요?', {'verb': verb})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('취소'))),
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('원본 삭제'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('원본 유지'))),
      ],
    ),
  );

  Future<void> makeBinder([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.isEmpty) {
      showInfo(context, tr('바인더에 넣을 문서를 선택하세요.'));
      return;
    }
    final name = await promptText(context, title: tr('바인더 만들기'), label: tr('바인더 이름'), initial: tr('새 바인더'));
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final out = await runBusy(
      context,
      tr('바인더를 만드는 중…'),
      () => ops.createBinder([for (final e in list) e.path], desk.folder, name),
    );
    if (out == null) return;
    desk.place([out], at: desk.positionOf(list.first));
    await _done();
  }

  Future<void> addToBinder(DeskEntry binder, List<String> docs) async {
    final r = await runBusy(context, tr('바인더에 추가하는 중…'), () async {
      await ops.addToBinder(binder.path, docs);
      return true;
    });
    if (r != null) await _done();
  }

  Future<void> unbind([DeskEntry? entry]) async {
    final e = entry ?? (_sel.length == 1 ? _sel.first : null);
    if (e == null || !e.isBinder) {
      showInfo(context, tr('해제할 바인더를 선택하세요.'));
      return;
    }
    final origin = desk.positionOf(e);
    final outs = await runBusy(context, tr('바인더를 해제하는 중…'), () => ops.unbind(e.path));
    if (outs == null) return;
    desk.placeSpread(outs, origin);
    await _done();
    desk.selectPaths(outs);
  }

  Future<void> rotate(int quarterTurns) async {
    final docs = _sel.where((e) => !e.isBinder).toList();
    if (docs.isEmpty) return;
    await runBusy(context, tr('회전하는 중…'), () async {
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
    final name = await promptText(context, title: tr('이름 바꾸기'), initial: e.title);
    if (name == null || name.trim().isEmpty || name == e.title || !context.mounted) return;
    final ext = e.isBinder ? binderExt : '.pdf';
    final target = p.join(desk.folder, '${sanitizeFileName(name)}$ext');
    if (File(target).existsSync() || Directory(target).existsSync()) {
      showInfo(context, tr('같은 이름이 이미 있습니다.'));
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
    final outs = await runBusy(context, tr('복제하는 중…'), () => _copyEntries(docs));
    if (outs == null) return;
    desk.place(outs, at: desk.positionOf(docs.first));
    await _done();
  }

  /// Ctrl + drag: copies of [paths] are laid down [delta] away from the
  /// originals, keeping their arrangement, on top and selected.
  Future<void> copyDragged(List<String> paths, Offset delta) async {
    final docs = [for (final s in paths) ...desk.entries.where((e) => e.path == s)];
    if (docs.isEmpty) return;
    final outs = await runBusy(context, tr('복사하는 중…'), () => _copyEntries(docs));
    if (outs == null) return;
    for (final (i, out) in outs.indexed) {
      final pos = desk.positionOf(docs[i]) + delta;
      desk.layout.positions[p.basename(out)] = Offset(math.max(0, pos.dx), math.max(0, pos.dy));
    }
    desk.endMove();
    await _done();
    desk.selectPaths(outs);
  }

  /// Copies documents and binders (with their annotations) as '… 복사본'.
  Future<List<String>> _copyEntries(List<DeskEntry> docs) async {
    final outs = <String>[];
    for (final e in docs) {
      if (e.isBinder) {
        final target = uniquePath(desk.folder, tr('{title} 복사본', {'title': e.title}), binderExt);
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
        final target = uniquePath(desk.folder, tr('{title} 복사본', {'title': e.title}), '.pdf');
        await copyDocument(e.path, target);
        outs.add(target);
      }
    }
    return outs;
  }

  /// 삭제: documents go to the trash (휴지통); the snackbar can undo it.
  Future<void> delete() async {
    final docs = _sel;
    if (docs.isEmpty) return;
    final s = desk.settings;
    if (s.confirmDelete || !s.deleteToTrash) {
      final ok = await confirm(
        context,
        title: tr('삭제'),
        message: !s.deleteToTrash
            ? tr('{n}개 항목을 영구히 삭제할까요? 되돌릴 수 없습니다.', {'n': docs.length})
            : docs.length == 1
            ? tr("'{title}'을(를) 휴지통으로 옮길까요?", {'title': docs.first.title})
            : tr('{n}개 항목을 휴지통으로 옮길까요?', {'n': docs.length}),
        okLabel: tr('삭제'),
        destructive: true,
      );
      if (!ok || !context.mounted) return;
    }
    if (!s.deleteToTrash) {
      await runBusy(context, tr('삭제하는 중…'), () async {
        for (final e in docs) {
          await deleteDocument(e.path);
        }
        return true;
      });
      await _done();
      return;
    }
    final trash = Trash(desk.settings.rootPath);
    final positions = {for (final e in docs) e.fileName: desk.positionOf(e)};
    final items = await runBusy(context, tr('삭제하는 중…'), () async {
      return [for (final e in docs) await trash.put(e.path)];
    });
    await _done();
    if (items == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(tr('휴지통으로 옮겼습니다 ({n}개)', {'n': items.length})),
          action: SnackBarAction(
            label: tr('실행 취소'),
            onPressed: () async {
              for (final item in items) {
                final back = await trash.restore(item);
                final pos = positions[item.name];
                if (pos != null) desk.layout.positions[p.basename(back)] = pos;
              }
              desk.endMove();
              await _done();
            },
          ),
        ),
      );
  }

  /// 휴지통: restore or permanently delete what was deleted from the desk.
  Future<void> openTrash() async {
    final trash = Trash(desk.settings.rootPath);
    final restored = await showTrashDialog(context, trash);
    if (restored.isNotEmpty) {
      await _done();
      desk.selectPaths(restored.where((r) => p.dirname(r) == desk.folder).toList());
    }
  }

  Future<void> exportPdf([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.isEmpty) return;
    final suggested = list.length == 1 ? '${list.first.title}.pdf' : tr('내보내기.pdf');
    final bytes = await runBusy(context, tr('PDF로 내보내는 중…'), () => ops.exportFlattened([for (final e in list) e.path]));
    if (bytes == null || !context.mounted) return;
    final saved = await FilePicker.saveFile(
      dialogTitle: tr('PDF로 내보내기 (주석 포함)'),
      fileName: suggested,
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (saved != null && context.mounted) {
      showInfo(context, tr('내보냈습니다: {toFilePath}', {'toFilePath': saved.toFilePath()}));
    }
  }

  Future<void> printDocs([List<DeskEntry>? entries]) async {
    final list = entries ?? _sel;
    if (list.isEmpty) return;
    final bytes = await runBusy(context, tr('인쇄 준비 중…'), () => ops.exportFlattened([for (final e in list) e.path]));
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

  /// Files dragged from the disk explorer onto the desk: PDFs are moved
  /// here (copied with [copy]); images become PDFs and, when moving, the
  /// original image is removed.
  Future<void> receiveDiskFiles(List<String> files, Offset? at, {bool copy = false}) async {
    final importable = files.where(isImportable).toList();
    if (importable.isEmpty) {
      showInfo(context, tr('지원하지 않는 파일입니다.'));
      return;
    }
    final created = await runBusy(context, copy ? tr('복사하는 중…') : tr('이동하는 중…'), () async {
      final out = <String>[];
      for (final f in importable) {
        if (p.dirname(f) == desk.folder) continue;
        if (isPdf(f) && !copy) {
          final moved = await moveDocument(f, uniquePath(desk.folder, p.basenameWithoutExtension(f), '.pdf'));
          await ops.restoreEditable(moved);
          out.add(moved);
          continue;
        }
        final r = await ops.importFile(f, desk.folder);
        if (r == null) continue;
        out.add(r);
        if (!copy) await deleteDocument(f);
      }
      return out;
    });
    if (created == null) return;
    desk.place(created, at: at);
    await _done();
    desk.selectPaths(created);
  }

  /// Desk documents dropped on a disk folder are copied there as ordinary
  /// PDFs: annotations are burned in and a binder becomes one PDF, so other
  /// programs see what the desk shows. The desk keeps its documents.
  Future<void> copyToDiskFolder(List<String> paths, String folder) async {
    final done = await runBusy(context, tr('복사하는 중…'), () async {
      var n = 0;
      for (final path in paths) {
        final title = p.basenameWithoutExtension(path);
        final target = uniquePath(folder, title, '.pdf');
        if (isBinderPath(path) || (await loadAnnotations(path)).isNotEmpty) {
          await writeBytesAtomic(target, await ops.exportFlattened([path]));
        } else {
          await File(path).copy(target);
        }
        n++;
      }
      return n;
    });
    if (done == null || !context.mounted) return;
    showInfo(context, tr("{n}개를 '{folder}'에 복사했습니다.", {'n': done, 'folder': p.basename(folder)}));
  }

  Future<void> moveToFolder(List<String> paths, String folder) async {
    if (folder == desk.folder) return;
    await runBusy(context, tr('이동하는 중…'), () async {
      for (final path in paths) {
        final ext = isBinderPath(path) ? binderExt : '.pdf';
        await moveDocument(path, uniquePath(folder, p.basenameWithoutExtension(path), ext));
      }
      return true;
    });
    await _done();
  }
}
