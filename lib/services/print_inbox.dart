import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'storage.dart';
import '../l10n/l10n.dart';

/// Picks up PDFs that the "PDF Desk" printer writes into [inboxDir] and moves
/// them onto the desk.
///
/// The printer always writes to the same file name, so jobs are collected as
/// soon as they're complete. The spooler writes the file in pieces; a job
/// counts as complete once its size stops changing and it ends with `%%EOF`.
class PrintInbox {
  PrintInbox(this.inboxDir, {required this.deskFolder, required this.onReceived});

  final String inboxDir;

  /// Where received documents go (the folder open on the desk).
  final String Function() deskFolder;
  final Future<void> Function(List<String> paths) onReceived;

  Timer? _timer;
  bool _busy = false;

  void start({Duration interval = const Duration(milliseconds: 1500)}) {
    Directory(inboxDir).createSync(recursive: true);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _poll());
    _poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final got = await collect(inboxDir, deskFolder());
      if (got.isNotEmpty) await onReceived(got);
    } catch (e) {
      debugPrint('print inbox: $e');
    } finally {
      _busy = false;
    }
  }

  /// Moves every complete PDF in [inbox] into [folder] as `인쇄_<date time>.pdf`
  /// and returns the new paths. Files still being written are left alone.
  static Future<List<String>> collect(
    String inbox,
    String folder, {
    Duration settle = const Duration(milliseconds: 700),
  }) async {
    final dir = Directory(inbox);
    if (!await dir.exists() || folder.isEmpty) return [];
    final candidates = [
      await for (final e in dir.list())
        if (e is File && isPdf(e.path)) e,
    ];
    final out = <String>[];
    for (final f in candidates) {
      if (!await _isComplete(f, settle)) continue;
      final name = tr('인쇄_{now}', {'now': DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())});
      final target = uniquePath(folder, name, '.pdf');
      try {
        // Fails while the spooler still holds the file open; retried next poll.
        await moveDocument(f.path, target);
        out.add(target);
      } on FileSystemException catch (e) {
        debugPrint('print inbox: ${f.path} not ready: ${e.message}');
      }
    }
    return out;
  }

  static Future<bool> _isComplete(File f, Duration settle) async {
    try {
      final before = await f.length();
      if (before == 0) return false;
      await Future<void>.delayed(settle);
      final len = await f.length();
      if (len != before) return false;
      final raf = await f.open();
      try {
        final tail = len < 2048 ? len : 2048;
        await raf.setPosition(len - tail);
        final bytes = await raf.read(tail);
        return String.fromCharCodes(bytes).contains('%%EOF');
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return false;
    }
  }
}

/// Path the printer port writes to.
String printerOutputFile(String inboxDir) => p.join(inboxDir, 'print.pdf');
