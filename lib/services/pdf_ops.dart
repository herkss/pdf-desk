import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation.dart';
import 'flatten.dart';
import 'storage.dart';

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
  final bytes = await File(path).readAsBytes();
  return PdfDocument.openData(bytes, sourceName: '$path#${_uuid.v4()}');
}

Future<int> pageCountOf(String path) async {
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
Future<AssembleResult> assemble(List<PageRef> refs, {bool flatten = false}) async {
  final sources = <String, PdfDocument>{};
  final sourceAnnotations = <String, List<Annotation>>{};
  final out = await PdfDocument.createNew(sourceName: 'new#${_uuid.v4()}');
  try {
    for (final r in refs) {
      if (!sources.containsKey(r.path)) {
        sources[r.path] = await openPdfInMemory(r.path);
        sourceAnnotations[r.path] = await loadAnnotations(r.path);
      }
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
      final assembled = await PdfDocument.openData(bytes, sourceName: 'flat#${_uuid.v4()}');
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
    for (final d in sources.values) {
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
  if (pages.length >= n) throw StateError('모든 페이지를 삭제할 수는 없습니다.');
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
  final base = '${p.basenameWithoutExtension(path)}_발췌';
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

/// 분할: one document per page.
Future<List<String>> splitPages(String path, String folder) async {
  final n = await pageCountOf(path);
  final base = p.basenameWithoutExtension(path);
  final digits = math.max(2, '$n'.length);
  final outs = <String>[];
  for (var i = 0; i < n; i++) {
    final out = uniquePath(folder, '${base}_${'${i + 1}'.padLeft(digits, '0')}', '.pdf');
    await assembleTo([PageRef(path, i)], out);
    outs.add(out);
  }
  return outs;
}

/// Imports a PDF or image into [folder]; images become one-page PDFs.
Future<String?> importFile(String source, String folder) async {
  final ext = p.extension(source).toLowerCase();
  final base = sanitizeFileName(p.basenameWithoutExtension(source));
  if (ext == '.pdf') {
    final out = uniquePath(folder, base, '.pdf');
    await File(source).copy(out);
    return out;
  }
  if (!importableImageExts.contains(ext)) return null;
  final out = uniquePath(folder, base, '.pdf');
  await writeBytesAtomic(out, await imageToPdf(await File(source).readAsBytes(), source));
  return out;
}

/// Wraps an image in a single-page PDF sized to fit A4 (portrait or landscape).
Future<Uint8List> imageToPdf(Uint8List data, String name) async {
  final decoded = img.decodeImage(data);
  if (decoded == null) throw FormatException('이미지를 읽을 수 없습니다: $name');
  final isJpeg = data.length > 2 && data[0] == 0xFF && data[1] == 0xD8;
  final jpeg = isJpeg ? data : img.encodeJpg(decoded, quality: 92);
  final landscape = decoded.width > decoded.height;
  final boxW = landscape ? 842.0 : 595.0, boxH = landscape ? 595.0 : 842.0;
  final scale = math.min(boxW / decoded.width, boxH / decoded.height);
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
