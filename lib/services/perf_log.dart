import 'dart:io';

import 'package:intl/intl.dart';

/// A small diagnostic log of slow steps and file-lock waits, in the
/// settings folder (도움말 → 진단 로그), so a slow PC can tell us why.
abstract final class PerfLog {
  static String? path;
  static final _fmt = DateFormat('MM-dd HH:mm:ss.SSS');

  static void write(String line) {
    final p = path;
    if (p == null) return;
    try {
      final f = File(p);
      // Keep it small: start over past 512 KB.
      if (f.existsSync() && f.lengthSync() > 512 * 1024) f.writeAsStringSync('');
      f.writeAsStringSync('${_fmt.format(DateTime.now())}  $line\n', mode: FileMode.append);
    } catch (_) {
      // A log must never get in the way.
    }
  }

  /// Runs [task] and notes it if it took longer than [slow].
  static Future<T> time<T>(
    String name,
    Future<T> Function() task, {
    Duration slow = const Duration(milliseconds: 300),
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await task();
    } finally {
      if (sw.elapsed >= slow) write('$name: ${sw.elapsedMilliseconds} ms');
    }
  }
}
