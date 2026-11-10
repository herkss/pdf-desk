import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'pdf_ops.dart' as ops;
import 'storage.dart';

/// Dragging desk documents out of the window onto the Windows desktop or
/// an Explorer folder, as files (see windows/runner/drag_out.cpp).
abstract final class DragOut {
  static const _channel = MethodChannel('pdf_desk/drag_out');

  static bool get supported => Platform.isWindows;

  /// Files of the drag in progress, so the desk doesn't import them back if
  /// they are dropped on its own window.
  static Set<String> _active = {};

  static bool isOwnDrag(Iterable<String> paths) =>
      _active.isNotEmpty && paths.every((f) => _active.any((a) => p.equals(a, f)));

  /// The files to hand to Windows for desk [entries], named like the
  /// documents. A plain PDF is handed over as it is; one with annotations,
  /// or a binder, becomes a PDF with the annotations burned in, as other
  /// programs can't read the desk's annotation layer. The shell wants the
  /// files in one folder, so if any is made, all go to a temp folder.
  static Future<List<String>> prepare(List<String> entries) async {
    final needsExport = <String>{};
    for (final e in entries) {
      if (isBinderPath(e) || (await loadAnnotations(e)).isNotEmpty) needsExport.add(e);
    }
    if (needsExport.isEmpty) return entries;
    final root = Directory(p.join(Directory.systemTemp.path, 'pdfdesk_drag'));
    // Earlier drags' files are no longer needed once a new drag starts.
    if (await root.exists()) {
      await for (final old in root.list()) {
        try {
          await old.delete(recursive: true);
        } on FileSystemException {
          // Still in use by Explorer: next time.
        }
      }
    }
    final dir = await Directory(p.join(root.path, const Uuid().v4())).create(recursive: true);
    final out = <String>[];
    for (final e in entries) {
      final target = uniquePath(dir.path, p.basenameWithoutExtension(e), '.pdf');
      if (needsExport.contains(e)) {
        await writeBytesAtomic(target, await ops.exportFlattened([e]));
      } else {
        await File(e).copy(target);
      }
      out.add(target);
    }
    return out;
  }

  /// Starts the Windows drag; returns once the files are dropped (true) or
  /// the drag is cancelled (false).
  static Future<bool> start(List<String> files) async {
    _active = files.toSet();
    try {
      final effect = await _channel.invokeMethod<int>('startFileDrag', files);
      return (effect ?? 0) > 0;
    } on PlatformException catch (e) {
      debugPrint('drag out: $e');
      return false;
    } finally {
      // The drop on our own window (if any) arrives right after the drag.
      Future<void>.delayed(const Duration(seconds: 2), () => _active = {});
    }
  }
}
