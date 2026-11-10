import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation.dart';
import 'flatten.dart';
import 'storage.dart';
import '../l10n/l10n.dart';

const _uuid = Uuid();

/// One page of a source PDF, optionally rotated clockwise by [rotate] quarter turns.
class PageRef {
  const PageRef(this.path, this.index, [this.rotate = 0]);
  final String path;

  /// 0-based page index.
  final int index;
  final int rotate;
}

class AssembleResult {
  AssembleResult(this.bytes, this.annotations);
  final Uint8List bytes;
  final List<Annotation> annotations;
}

Future<PdfDocument> openPdfInMemory(String path) async {
  // Reading into memory avoids holding a file lock on Windows, so the file can
  // be rewritten while it's open.
  final stat = await File(path).stat();
  final doc = await openPdfBytes(await File(path).readAsBytes(), '$path#${_uuid.v4()}');
  _pageCounts[path] = (_stampOf(stat), doc.pages.length);
  return doc;
}

/// Page counts by path, valid while the file's time and size stay the same:
/// operations used to open a whole document once just to count its pages
/// and then again to work on it.
final _pageCounts = <String, (String, int)>{};

String _stampOf(FileStat st) => '${st.modified.microsecondsSinceEpoch}|${st.size}';

/// Opens PDF bytes with PDFium holding all of them in memory.
///
/// pdfrx's `openData` does that only up to 1 MB; a bigger document is read
/// piece by piece through a callback that, on Windows, waits for the main
/// isolate on a condition variable with no time limit. A missed wake-up
/// there leaves the PDF worker stuck for good — every thumbnail, preview and
/// stack after it then spins for ever. Loading from memory never calls back.
Future<PdfDocument> openPdfBytes(Uint8List bytes, String sourceName) => PdfDocument.openCustom(
  read: (buffer, position, size) {
    final n = math.max(0, math.min(size, bytes.length - position));
    buffer.setRange(0, n, bytes, position);
    return n;
  },
  fileSize: bytes.length,
  sourceName: sourceName,
  maxSizeToCacheOnMemory: bytes.length,
);

Future<int> pageCountOf(String path) async {
  final known = _pageCounts[path];
  if (known != null && known.$1 == _stampOf(await File(path).stat())) return known.$2;
  final doc = await openPdfInMemory(path);
  try {
    return doc.pages.length;
  } finally {
    await doc.dispose();
  }
}

/// Builds a new PDF from [refs], carrying over (and rotating/renumbering) the
/// annotations of each source page. With [flatten], annotations are burned
/// into the page content instead of returned.
///
/// Documents already open can be passed in [opened] (they stay open).
Future<AssembleResult> assemble(
  List<PageRef> refs, {
  bool flatten = false,
  Map<String, PdfDocument> opened = const {},
}) async {
  final sources = <String, PdfDocument>{...opened};
  final sourceAnnotations = <String, List<Annotation>>{};
  final out = await PdfDocument.createNew(sourceName: 'new#${_uuid.v4()}');
  try {
    for (final r in refs) {
      if (!sources.containsKey(r.path)) sources[r.path] = await openPdfInMemory(r.path);
      if (!sourceAnnotations.containsKey(r.path)) sourceAnnotations[r.path] = await loadAnnotations(r.path);
    }
    final pages = <PdfPage>[];
    final annotations = <Annotation>[];
    for (var i = 0; i < refs.length; i++) {
      final r = refs[i];
      final src = sources[r.path]!.pages[r.index];
      pages.add(src.rotatedBy(PdfPageRotation.values[r.rotate & 3]));
      for (final a in sourceAnnotations[r.path]!.where((a) => a.page == r.index)) {
        final c = a.copy()..page = i;
        if (r.rotate & 3 != 0) rotateAnnotation(c, Size(src.width, src.height), r.rotate);
        annotations.add(Annotation.fromJson(c.toJson()..remove('id')));
      }
    }
    out.pages = pages;
    var bytes = await out.encodePdf();
    if (flatten && annotations.isNotEmpty) {
      // Edit a freshly opened copy: pdfrx re-imports foreign pages on every
      // encode, which would drop edits made to the assembled document.
      final assembled = await openPdfBytes(bytes, 'flat#${_uuid.v4()}');
      try {
        await flattenAnnotations(assembled, annotations);
        bytes = await assembled.encodePdf();
      } finally {
        await assembled.dispose();
      }
    }
    return AssembleResult(bytes, flatten ? [] : annotations);
  } finally {
    await out.dispose();
    for (final d in sources.entries.where((e) => !opened.containsKey(e.key)).map((e) => e.value)) {
      await d.dispose();
    }
  }
}

/// Assembles [refs] into [outPath] (which may be one of the sources) and
/// writes the matching annotation sidecar.
Future<void> assembleTo(List<PageRef> refs, String outPath) async {
  final result = await assemble(refs);
  await writeBytesAtomic(outPath, result.bytes);
  await saveAnnotations(outPath, result.annotations);
}

Future<List<PageRef>> allPages(String path) async {
  final n = await pageCountOf(path);
  return [for (var i = 0; i < n; i++) PageRef(path, i)];
}

/// All pages of a document or a binder.
Future<List<PageRef>> pagesOfEntry(String path) async {
  if (isBinderPath(path)) {
    return [for (final d in await binderDocuments(path)) ...await allPages(d)];
  }
  return allPages(path);
}

/// PDF with annotations burned in — for export, printing and sharing.
Future<Uint8List> exportFlattened(List<String> entries) async {
  final refs = [for (final e in entries) ...await pagesOfEntry(e)];
  return (await assemble(refs, flatten: true)).bytes;
}

// ---------------------------------------------------------------------------
// Page operations on a single document (in place).

Future<void> rotatePages(String path, Set<int> pages, int quarterTurns) async {
  final n = await pageCountOf(path);
  await assembleTo([for (var i = 0; i < n; i++) PageRef(path, i, pages.contains(i) ? quarterTurns : 0)], path);
}

Future<void> deletePages(String path, Set<int> pages) async {
  final n = await pageCountOf(path);
  if (pages.length >= n) throw StateError(tr('모든 페이지를 삭제할 수는 없습니다.'));
  await assembleTo([
    for (var i = 0; i < n; i++)
      if (!pages.contains(i)) PageRef(path, i),
  ], path);
}

/// [order] lists source page indices in their new order.
Future<void> reorderPages(String path, List<int> order) => assembleTo([for (final i in order) PageRef(path, i)], path);

/// Inserts all pages of [other] into [path] before page [at].
Future<void> insertDocument(String path, String other, int at) async {
  final n = await pageCountOf(path);
  final mine = [for (var i = 0; i < n; i++) PageRef(path, i)];
  await assembleTo([...mine.take(at), ...await allPages(other), ...mine.skip(at)], path);
}

/// Copies [pages] of [path] into a new document in [folder]; returns its path.
Future<String> extractPages(String path, List<int> pages, String folder) async {
  final base = tr('{path}_발췌', {'path': p.basenameWithoutExtension(path)});
  final out = uniquePath(folder, base, '.pdf');
  await assembleTo([for (final i in pages) PageRef(path, i)], out);
  return out;
}

// ---------------------------------------------------------------------------
// Desk operations

/// 묶기: combines documents/binders into one document.
Future<String> combine(List<String> entries, String folder, String name) async {
  final refs = [for (final e in entries) ...await pagesOfEntry(e)];
  final out = uniquePath(folder, sanitizeFileName(name), '.pdf');
  await assembleTo(refs, out);
  return out;
}

/// 겹치기: appends the pages of [sources] (documents or binders) to the end of
/// [target] in place and removes the sources, like dropping sheets onto a
/// pile on a real desk.
Future<void> stackOnto(String target, List<String> sources) async {
  final others = sources.where((s) => s != target).toList();
  if (others.isEmpty) return;
  await assembleTo([...await allPages(target), for (final s in others) ...await pagesOfEntry(s)], target);
  // Not waited for: a fresh sheet can be held by Windows for seconds.
  await Future.wait([for (final s in others) deleteSoon(s)]);
}

/// 겹치기 that can be undone, as fast as moving files: every document is
/// opened once, the merged result is written in the target's place, and the
/// originals are *moved* (renamed, not copied) into the undo folder — on the
/// same drive that is instant whatever their size, and it also takes them
/// off the desk. Returns the undo and the merged page count.
Future<(StackUndo, int)> stackWithUndo(String folder, String target, List<String> sources) async {
  final others = sources.where((s) => s != target).toList();
  final docs = <String>[target];
  for (final e in others) {
    docs.addAll(isBinderPath(e) ? await binderDocuments(e) : [e]);
  }
  final opened = <String, PdfDocument>{};
  final AssembleResult merged;
  final int pages;
  try {
    final refs = <PageRef>[];
    for (final d in docs) {
      final doc = opened[d] ??= await openPdfInMemory(d);
      refs.addAll([for (var i = 0; i < doc.pages.length; i++) PageRef(d, i)]);
    }
    pages = refs.length;
    merged = await assemble(refs, opened: opened);
  } finally {
    for (final d in opened.values) {
      await d.dispose();
    }
  }

  final dir = await StackUndo._freshDir(folder);
  final items = <(String, String)>[];
  Future<void> putAside(String original, int i) async {
    final backup = p.join(dir.path, '$i${p.extension(original)}');
    try {
      await moveDocument(original, backup, attempts: 3);
    } on FileSystemException {
      // Held by Windows: keep a copy and remove the original in the background.
      await copyEntry(original, backup);
      if (i > 0) await deleteSoon(original);
    }
    items.add((original, backup));
  }

  await putAside(target, 0);
  await writeBytesAtomic(target, merged.bytes);
  await saveAnnotations(target, merged.annotations);
  for (final (i, s) in others.indexed) {
    await putAside(s, i + 1);
  }
  return (StackUndo._latest = StackUndo._(dir, items), pages);
}

/// A copy of the documents involved in a 겹치기, so it can be undone. Only
/// the most recent one is kept, in the folder's hidden metadata directory
/// (same drive, so restoring is a rename).
class StackUndo {
  StackUndo._(this._dir, this._items);
  final Directory _dir;

  /// (original path, backup path)
  final List<(String, String)> _items;

  List<String> get paths => [for (final (o, _) in _items) o];

  static StackUndo? _latest;

  /// Only the latest 겹치기 can be undone; a newer one replaces its backup.
  bool get canRestore => identical(_latest, this) && _dir.existsSync();

  /// A new, empty undo folder; older ones are cleared as far as Windows lets.
  static Future<Directory> _freshDir(String folder) async {
    final root = Directory(p.join(metaDirOf(folder), 'undo'));
    if (await root.exists()) {
      await for (final old in root.list()) {
        await _deleteQuietly(old);
      }
    }
    return Directory(p.join(root.path, _uuid.v4())).create(recursive: true);
  }

  static Future<StackUndo> capture(String folder, List<String> paths) async {
    final root = Directory(p.join(metaDirOf(folder), 'undo'));
    // Old backups are only clutter. Windows may still hold their files (the
    // antivirus scanning fresh copies), so clearing them must never stop
    // the stack; whatever is left is cleared next time.
    if (await root.exists()) {
      await for (final old in root.list()) {
        await _deleteQuietly(old);
      }
    }
    final dir = await Directory(p.join(root.path, _uuid.v4())).create(recursive: true);
    final items = <(String, String)>[];
    for (final (i, path) in paths.indexed) {
      final backup = p.join(dir.path, '$i${p.extension(path)}');
      await copyEntry(path, backup);
      items.add((path, backup));
    }
    return _latest = StackUndo._(dir, items);
  }

  /// Puts every document back the way it was before the 겹치기.
  Future<void> restore() async {
    if (!canRestore) throw StateError(tr('이미 다른 작업을 해서 되돌릴 수 없습니다.'));
    _latest = null;
    for (final (i, (original, backup)) in _items.indexed) {
      final pending = pendingDeletes.remove(original);
      final exists = await File(original).exists() || await Directory(original).exists();
      // The stacked-onto document (first) changed; the others didn't, so
      // one Windows hasn't let go of yet can simply stay.
      if (exists && i > 0 && pending) continue;
      if (exists) await deleteDocument(original);
      await moveDocument(backup, original);
    }
    await discard();
  }

  Future<void> discard() => _deleteQuietly(_dir);
}

/// Deletes a backup, retrying while Windows holds it, and gives up silently.
Future<void> _deleteQuietly(FileSystemEntity e) async {
  try {
    if (await e.exists()) await retryFileOp(() => e.delete(recursive: true), attempts: 5);
  } on FileSystemException {
    // Left for the next cleanup.
  }
}

/// 펼치기: replaces a multi-page document with one document per page.
Future<List<String>> spreadPages(String path, String folder) async {
  final outs = await splitPages(path, folder);
  await deleteSoon(path);
  return outs;
}

/// 분할: one document per page.
Future<List<String>> splitPages(String path, String folder) async {
  // The source is opened once for all its pages (it used to be read again
  // for every page, which made big documents spread slowly).
  final source = await openPdfInMemory(path);
  try {
    final n = source.pages.length;
    final base = p.basenameWithoutExtension(path);
    final digits = math.max(2, '$n'.length);
    final outs = <String>[];
    for (var i = 0; i < n; i++) {
      final out = uniquePath(folder, '${base}_${'${i + 1}'.padLeft(digits, '0')}', '.pdf');
      final result = await assemble([PageRef(path, i)], opened: {path: source});
      await writeBytesAtomic(out, result.bytes);
      if (result.annotations.isNotEmpty) await saveAnnotations(out, result.annotations);
      outs.add(out);
    }
    return outs;
  } finally {
    await source.dispose();
  }
}

/// Imports a PDF or image into [folder]; images become one-page PDFs.
Future<String?> importFile(String source, String folder) async {
  final ext = p.extension(source).toLowerCase();
  final base = sanitizeFileName(p.basenameWithoutExtension(source));
  if (ext == '.pdf') {
    final out = uniquePath(folder, base, '.pdf');
    await File(source).copy(out);
    await restoreEditable(out);
    return out;
  }
  if (!importableImageExts.contains(ext)) return null;
  final out = uniquePath(folder, base, '.pdf');
  await writeBytesAtomic(out, await imageToPdf(await File(source).readAsBytes(), source));
  return out;
}

/// A PDF exported from a desk (copied to a folder, dragged out, 내보내기)
/// carries its annotations as data. Brought back, they become editable
/// again: the burned-in drawings are taken off the pages and the
/// annotations are saved as the document's layer. Returns whether it was
/// such a PDF; anything else is left as it is.
Future<bool> restoreEditable(String path) async {
  try {
    // Only PDFs a desk exported carry the data; don't open the others.
    if (!_mentions(await File(path).readAsBytes(), editDataName)) return false;
    final doc = await openPdfInMemory(path);
    try {
      final annotations = await takeBackAnnotations(doc);
      if (annotations == null) return false;
      final bytes = await doc.encodePdf();
      await writeBytesAtomic(path, bytes);
      await saveAnnotations(path, [...await loadAnnotations(path), ...annotations]);
      return true;
    } finally {
      await doc.dispose();
    }
  } catch (_) {
    return false;
  }
}

/// Imported images are fitted to an A4 page; otherwise they keep their size
/// at 96 dpi. Set from the 가져오기 button's settings.
var importImagesFitA4 = true;

/// Whether [bytes] contain [text] as ASCII or as UTF-16 (big-endian, as PDF
/// strings with non-Latin text are stored).
bool _mentions(Uint8List bytes, String text) {
  bool find(List<int> needle) {
    final first = needle.first;
    for (var i = bytes.indexOf(first); i >= 0 && i <= bytes.length - needle.length; i = bytes.indexOf(first, i + 1)) {
      var j = 1;
      while (j < needle.length && bytes[i + j] == needle[j]) {
        j++;
      }
      if (j == needle.length) return true;
    }
    return false;
  }

  final ascii = text.codeUnits;
  return find(ascii) || find([for (final c in ascii) ...[0, c]]);
}

/// Wraps an image in a single-page PDF sized to fit A4 (portrait or landscape).
Future<Uint8List> imageToPdf(Uint8List data, String name) async {
  final decoded = img.decodeImage(data);
  if (decoded == null) throw FormatException(tr('이미지를 읽을 수 없습니다: {name}', {'name': name}));
  final isJpeg = data.length > 2 && data[0] == 0xFF && data[1] == 0xD8;
  final jpeg = isJpeg ? data : img.encodeJpg(decoded, quality: 92);
  final landscape = decoded.width > decoded.height;
  final boxW = landscape ? 842.0 : 595.0, boxH = landscape ? 595.0 : 842.0;
  final scale = importImagesFitA4 ? math.min(boxW / decoded.width, boxH / decoded.height) : 72 / 96;
  final doc = await PdfDocument.createFromJpegData(
    jpeg,
    width: decoded.width * scale,
    height: decoded.height * scale,
    sourceName: 'img#${_uuid.v4()}',
  );
  try {
    return await doc.encodePdf();
  } finally {
    await doc.dispose();
  }
}

/// Paper sizes for new blank documents, portrait, in points.
const paperSizes = {
  'A3': Size(841.89, 1190.55),
  'A4': Size(595.28, 841.89),
  'A5': Size(419.53, 595.28),
  'B4': Size(728.5, 1031.81), // JIS B4, 257 × 364 mm
  'B5': Size(515.91, 728.5), // JIS B5, 182 × 257 mm
  'Letter': Size(612, 792),
  'Legal': Size(612, 1008),
};

/// Creates a blank document of [pages] pages of [size] points in [folder].
Future<String> createBlank(String folder, String name, Size size, {int pages = 1}) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(pageFormat: PdfPageFormat(size.width, size.height), build: (_) => pw.SizedBox()));
  }
  final out = uniquePath(folder, sanitizeFileName(name), '.pdf');
  await writeBytesAtomic(out, await doc.save());
  return out;
}

// ---------------------------------------------------------------------------
// Binders

Future<String> createBinder(List<String> docs, String folder, String name) async {
  final binder = uniquePath(folder, sanitizeFileName(name), binderExt);
  await Directory(binder).create();
  final moved = <String>[];
  for (final d in docs) {
    if (isBinderPath(d)) {
      for (final inner in await binderDocuments(d)) {
        moved.add(await moveDocument(inner, uniquePath(binder, p.basenameWithoutExtension(inner), '.pdf')));
      }
      await deleteDocument(d);
    } else {
      moved.add(await moveDocument(d, uniquePath(binder, p.basenameWithoutExtension(d), '.pdf')));
    }
  }
  await saveBinderOrder(binder, moved);
  return binder;
}

Future<void> addToBinder(String binder, List<String> docs) async {
  final order = await binderDocuments(binder);
  for (final d in docs) {
    if (d == binder) continue;
    if (isBinderPath(d)) {
      for (final inner in await binderDocuments(d)) {
        order.add(await moveDocument(inner, uniquePath(binder, p.basenameWithoutExtension(inner), '.pdf')));
      }
      await deleteDocument(d);
    } else {
      order.add(await moveDocument(d, uniquePath(binder, p.basenameWithoutExtension(d), '.pdf')));
    }
  }
  await saveBinderOrder(binder, order);
}

/// Moves a document out of its binder into the binder's parent folder.
Future<String> removeFromBinder(String doc) async {
  final binder = p.dirname(doc);
  final out = await moveDocument(doc, uniquePath(p.dirname(binder), p.basenameWithoutExtension(doc), '.pdf'));
  final rest = await binderDocuments(binder);
  await saveBinderOrder(binder, rest);
  return out;
}

/// 바인더 해제: moves all documents out and removes the binder.
Future<List<String>> unbind(String binder) async {
  final outs = <String>[];
  for (final d in await binderDocuments(binder)) {
    outs.add(await moveDocument(d, uniquePath(p.dirname(binder), p.basenameWithoutExtension(d), '.pdf')));
  }
  await deleteDocument(binder);
  return outs;
}
