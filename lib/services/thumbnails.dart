import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../models/annotation.dart';
import 'pdf_ops.dart';
import 'perf_log.dart';
import 'storage.dart';

class Thumbnail {
  Thumbnail(this.image, this.pageSize, this.pageCount, this.annotations);
  final ui.Image image;

  /// First page size in points.
  final ui.Size pageSize;
  final int pageCount;

  /// First-page annotations, drawn over the image like DocuWorks does.
  final List<Annotation> annotations;
}

/// Renders first-page thumbnails with a small LRU cache and a concurrency
/// limit, so a desk with many documents stays responsive.
class ThumbnailService {
  ThumbnailService._();
  static final instance = ThumbnailService._();

  static const _maxEntries = 300;
  // Two at a time, as in the builds where thumbnails always appeared; with
  // three they all stopped on a Windows PC.
  static const _maxConcurrent = 2;

  /// How long a thumbnail may take to open or draw before it's given up
  /// (null: no limit, for tests whose clock is fake).
  static Duration? timeLimit = const Duration(seconds: 15);

  static Future<T> limited<T>(Future<T> f) => timeLimit == null ? f : f.timeout(timeLimit!);
  static const renderWidth = 400;

  final _cache = <String, Thumbnail>{};
  final _pending = <String, Future<Thumbnail?>>{};
  int _running = 0;
  final _queue = Queue<Completer<void>>();

  /// Bumped whenever a document changes so widgets reload.
  final revision = ValueNotifier(0);

  /// First-page size and page count of the last thumbnail of each path, so
  /// the desk knows how big each sheet is drawn without waiting for a render.
  final _known = <String, (ui.Size, int)>{};

  (ui.Size, int)? knownPageOf(String path) => _known[path];

  Future<String> _key(String path) async {
    if (isBinderPath(path)) {
      final docs = await binderDocuments(path);
      if (docs.isEmpty) return '$path|empty';
      return '$path|${await _key(docs.first)}|${docs.length}';
    }
    final stat = await File(path).stat();
    final side = File(annotationPathFor(path));
    final sideStamp = await side.exists() ? (await side.stat()).modified.millisecondsSinceEpoch : 0;
    return '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}|$sideStamp';
  }

  Future<Thumbnail?> get(String path) async {
    final t = await _get(path);
    if (t != null) _known[path] = (t.pageSize, t.pageCount);
    return t;
  }

  Future<Thumbnail?> _get(String path) async {
    final key = await _key(path);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    // The callback must not return the pending future, or whenComplete would
    // wait for itself.
    Future<Thumbnail?> load() async => await _fromDisk(path, key) ?? await _render(path, key);
    return _pending[key] ??= load().whenComplete(() {
      _pending.remove(key);
    });
  }

  // --- disk cache ----------------------------------------------------------
  // Rendered thumbnails are kept as PNGs in the folder's .pdfdesk/thumbs, so
  // opening a desk again shows them at once instead of rendering each page.

  static String _hash(String key) {
    var h = 0xcbf29ce484222325;
    for (final c in key.codeUnits) {
      h = (h ^ c) * 0x100000001b3 & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  static String _cacheDir(String path) => p.join(metaDirOf(p.dirname(path)), 'thumbs');

  Future<Thumbnail?> _fromDisk(String path, String key) async {
    try {
      final base = p.join(_cacheDir(path), _hash(key));
      final meta = File('$base.json'), png = File('$base.png');
      if (!await meta.exists() || !await png.exists()) return null;
      final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final codec = await ui.instantiateImageCodec(await png.readAsBytes());
      final image = (await codec.getNextFrame()).image;
      final doc = isBinderPath(path) ? (await binderDocuments(path)).firstOrNull ?? path : path;
      final thumb = Thumbnail(
        image,
        ui.Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
        j['pages'] as int,
        (await loadAnnotations(doc)).where((a) => a.page == 0).toList(),
      );
      _remember(key, thumb);
      return thumb;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toDisk(String path, String key, Thumbnail t) async {
    try {
      final dir = Directory(_cacheDir(path));
      await dir.create(recursive: true);
      final base = p.join(dir.path, _hash(key));
      final png = await t.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      await File('$base.png').writeAsBytes(png.buffer.asUint8List());
      await File(
        '$base.json',
      ).writeAsString(jsonEncode({'w': t.pageSize.width, 'h': t.pageSize.height, 'pages': t.pageCount}));
      // Old versions pile up as documents change; keep the newest.
      final files = await dir.list().where((e) => e is File).cast<File>().toList();
      if (files.length > 800) {
        final stats = {for (final f in files) f: (await f.stat()).modified};
        files.sort((a, b) => stats[a]!.compareTo(stats[b]!));
        for (final f in files.take(files.length - 600)) {
          await f.delete().catchError((Object _) => f);
        }
      }
    } catch (_) {
      // Only a cache.
    }
  }

  void _remember(String key, Thumbnail t) {
    _cache[key] = t;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first)?.image.dispose();
    }
  }

  void invalidate() => revision.value++;

  Future<Thumbnail?> _render(String path, String key) async {
    final waited = Stopwatch()..start();
    await _acquire();
    final wait = waited.elapsedMilliseconds;
    final took = Stopwatch()..start();
    var step = 'start';
    try {
      String doc = path;
      var pageCount = 0;
      if (isBinderPath(path)) {
        final docs = await binderDocuments(path);
        if (docs.isEmpty) return null;
        doc = docs.first;
        for (final d in docs) {
          pageCount += await pageCountOf(d);
        }
      }
      // A PDF that never finishes opening or drawing must not hold one of
      // the few render slots for ever (every later thumbnail would wait).
      step = 'open';
      final pdf = await limited(openPdfInMemory(doc));
      try {
        if (pdf.pages.isEmpty) return null;
        final page = pdf.pages.first;
        final h = (renderWidth * page.height / page.width).round();
        step = 'render';
        final image = await limited(
          page.render(fullWidth: renderWidth.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xFFFFFFFF),
        );
        step = 'image';
        if (image == null) return null;
        final uiImage = await image.createImage();
        image.dispose();
        final annotations = (await loadAnnotations(doc)).where((a) => a.page == 0).toList();
        final thumb = Thumbnail(
          uiImage,
          ui.Size(page.width, page.height),
          pageCount == 0 ? pdf.pages.length : pageCount,
          annotations,
        );
        _remember(key, thumb);
        unawaited(_toDisk(path, key, thumb));
        return thumb;
      } finally {
        await pdf.dispose();
      }
    } catch (e) {
      debugPrint('thumbnail failed for $path: $e');
      PerfLog.write('thumbnail ${p.basename(path)} failed at $step: $e');
      return null;
    } finally {
      _release();
      if (wait + took.elapsedMilliseconds >= 300) {
        PerfLog.write('thumbnail ${p.basename(path)}: waited $wait ms, rendered in ${took.elapsedMilliseconds} ms');
      }
    }
  }

  Future<void> _acquire() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
