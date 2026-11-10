import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/annotation.dart';

/// Metadata lives next to the documents in a hidden `.pdfdesk` directory, so a
/// folder can be moved or synced as a unit:
///
/// ```text
///   folder/.pdfdesk/layout.json              desk positions
///   folder/.pdfdesk/annotations/<file>.json  annotations of folder/<file>
///   folder/<name>.pdbinder/binder.json       binder document order
/// ```
const metaDirName = '.pdfdesk';
const binderExt = '.pdbinder';
const binderManifest = 'binder.json';

bool isPdf(String path) => p.extension(path).toLowerCase() == '.pdf';
bool isBinderPath(String path) => p.extension(path).toLowerCase() == binderExt;
bool isHiddenName(String name) => name.startsWith('.');

const importableImageExts = {'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp', '.tif', '.tiff'};

bool isImportable(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext == '.pdf' || importableImageExts.contains(ext);
}

String metaDirOf(String folder) => p.join(folder, metaDirName);

String annotationPathFor(String pdfPath) =>
    p.join(metaDirOf(p.dirname(pdfPath)), 'annotations', '${p.basename(pdfPath)}.json');

Future<List<Annotation>> loadAnnotations(String pdfPath) async {
  final f = File(annotationPathFor(pdfPath));
  if (!await f.exists()) return [];
  try {
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return [for (final a in (j['annotations'] as List)) Annotation.fromJson(a as Map<String, dynamic>)];
  } catch (_) {
    return [];
  }
}

Future<void> saveAnnotations(String pdfPath, List<Annotation> annotations) async {
  final f = File(annotationPathFor(pdfPath));
  if (annotations.isEmpty) {
    if (await f.exists()) await f.delete();
    return;
  }
  await f.parent.create(recursive: true);
  await _writeAtomic(
    f.path,
    utf8.encode(
      const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'annotations': [for (final a in annotations) a.toJson()],
      }),
    ),
  );
}

/// Moves a document together with its annotation sidecar.
Future<String> moveDocument(String from, String to) async {
  final sidecar = File(annotationPathFor(from));
  await _move(from, to);
  if (await sidecar.exists()) {
    final dest = File(annotationPathFor(to));
    await dest.parent.create(recursive: true);
    await _move(sidecar.path, dest.path);
  }
  return to;
}

Future<void> copyDocument(String from, String to) async {
  await File(from).copy(to);
  final sidecar = File(annotationPathFor(from));
  if (await sidecar.exists()) {
    final dest = File(annotationPathFor(to));
    await dest.parent.create(recursive: true);
    await sidecar.copy(dest.path);
  }
}

/// Runs a file operation, retrying for a few seconds while it fails.
///
/// On Windows, antivirus scanners, the search indexer, OneDrive and our own
/// thumbnail reader briefly hold files open right after they're written or
/// read; deleting or renaming during that window fails with a sharing
/// violation even though nothing is wrong.
@visibleForTesting
Future<T> retryFileOp<T>(Future<T> Function() op, {int attempts = 12}) async {
  for (var i = 1; ; i++) {
    try {
      return await op();
    } on FileSystemException catch (e) {
      if (i >= attempts) rethrow;
      debugPrint('file op failed (attempt $i), retrying: ${e.message} ${e.path}');
      await Future<void>.delayed(Duration(milliseconds: 100 * i));
    }
  }
}

/// Copies a document (with its annotations) or a whole binder folder.
Future<void> copyEntry(String from, String to) async {
  if (!await Directory(from).exists()) return copyDocument(from, to);
  await Directory(to).create(recursive: true);
  await for (final e in Directory(from).list(recursive: true)) {
    final dest = p.join(to, p.relative(e.path, from: from));
    if (e is Directory) {
      await Directory(dest).create(recursive: true);
    } else if (e is File) {
      await File(dest).parent.create(recursive: true);
      await e.copy(dest);
    }
  }
}

Future<void> deleteDocument(String path) async {
  if (await Directory(path).exists()) {
    await retryFileOp(() => Directory(path).delete(recursive: true));
  } else {
    await retryFileOp(() => File(path).delete());
  }
  final sidecar = File(annotationPathFor(path));
  if (await sidecar.exists()) await retryFileOp(sidecar.delete);
}

Future<void> _move(String from, String to) async {
  if (await Directory(from).exists()) {
    await retryFileOp(() => Directory(from).rename(to));
    return;
  }
  if (p.rootPrefix(p.absolute(from)).toLowerCase() == p.rootPrefix(p.absolute(to)).toLowerCase()) {
    await retryFileOp(() => File(from).rename(to));
  } else {
    // Different drive: copy then delete.
    await retryFileOp(() => File(from).copy(to));
    await retryFileOp(() => File(from).delete());
  }
}

Future<void> writeBytesAtomic(String path, List<int> bytes) => _writeAtomic(path, bytes);

Future<void> _writeAtomic(String path, List<int> bytes) async {
  final tmp = File('$path.tmp');
  await retryFileOp(() => tmp.writeAsBytes(bytes, flush: true));
  await retryFileOp(() async {
    try {
      // Replaces an existing file in one step on every platform.
      await tmp.rename(path);
    } on FileSystemException {
      if (!await File(path).exists()) rethrow;
      await File(path).delete();
      await tmp.rename(path);
    }
  });
}

/// Returns a path in [folder] named [base][ext] that doesn't exist yet,
/// appending " (2)", " (3)"… when needed.
String uniquePath(String folder, String base, String ext) {
  var candidate = p.join(folder, '$base$ext');
  var n = 2;
  while (File(candidate).existsSync() || Directory(candidate).existsSync()) {
    candidate = p.join(folder, '$base ($n)$ext');
    n++;
  }
  return candidate;
}

/// Characters Windows doesn't allow in file names.
String sanitizeFileName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

// ---------------------------------------------------------------------------
// Desk layout

class DeskLayout {
  DeskLayout({Map<String, Offset>? positions, this.thumbWidth = 140}) : positions = positions ?? {};

  /// File name → top-left position on the desk.
  final Map<String, Offset> positions;
  double thumbWidth;

  static Future<DeskLayout> load(String folder) async {
    final f = File(p.join(metaDirOf(folder), 'layout.json'));
    if (!await f.exists()) return DeskLayout();
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final pos = <String, Offset>{};
      (j['positions'] as Map<String, dynamic>).forEach((k, v) {
        pos[k] = Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
      });
      return DeskLayout(positions: pos, thumbWidth: (j['thumbWidth'] as num?)?.toDouble() ?? 140);
    } catch (_) {
      return DeskLayout();
    }
  }

  Future<void> save(String folder) async {
    final dir = Directory(metaDirOf(folder));
    await dir.create(recursive: true);
    await _writeAtomic(
      p.join(dir.path, 'layout.json'),
      utf8.encode(
        jsonEncode({
          'thumbWidth': thumbWidth,
          'positions': positions.map((k, v) => MapEntry(k, [v.dx.round(), v.dy.round()])),
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Binders

/// Documents in a binder, in binder order.
Future<List<String>> binderDocuments(String binderPath) async {
  final dir = Directory(binderPath);
  if (!await dir.exists()) return [];
  final files = <String>[
    await for (final e in dir.list())
      if (e is File && isPdf(e.path)) p.basename(e.path),
  ];
  var order = <String>[];
  final manifest = File(p.join(binderPath, binderManifest));
  if (await manifest.exists()) {
    try {
      order = List<String>.from((jsonDecode(await manifest.readAsString()) as Map)['order'] as List);
    } catch (_) {}
  }
  final result = [
    for (final n in order)
      if (files.contains(n)) n,
  ];
  final rest = files.where((f) => !result.contains(f)).toList()..sort();
  return [
    for (final n in [...result, ...rest]) p.join(binderPath, n),
  ];
}

Future<void> saveBinderOrder(String binderPath, List<String> docs) async {
  await _writeAtomic(
    p.join(binderPath, binderManifest),
    utf8.encode(
      jsonEncode({
        'order': [for (final d in docs) p.basename(d)],
      }),
    ),
  );
}
