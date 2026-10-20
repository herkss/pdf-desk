import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/annotation.dart';
import 'pdf_ops.dart';
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
  static const _maxConcurrent = 2;
  static const renderWidth = 320;

  final _cache = <String, Thumbnail>{};
  final _pending = <String, Future<Thumbnail?>>{};
  int _running = 0;
  final _queue = Queue<Completer<void>>();

  /// Bumped whenever a document changes so widgets reload.
  final revision = ValueNotifier(0);

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
    final key = await _key(path);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    // The callback must not return the pending future, or whenComplete would
    // wait for itself.
    return _pending[key] ??= _render(path, key).whenComplete(() {
      _pending.remove(key);
    });
  }

  void invalidate() => revision.value++;

  Future<Thumbnail?> _render(String path, String key) async {
    await _acquire();
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
      final pdf = await openPdfInMemory(doc);
      try {
        if (pdf.pages.isEmpty) return null;
        final page = pdf.pages.first;
        final h = (renderWidth * page.height / page.width).round();
        final image = await page.render(
          fullWidth: renderWidth.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
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
        _cache[key] = thumb;
        while (_cache.length > _maxEntries) {
          _cache.remove(_cache.keys.first)?.image.dispose();
        }
        return thumb;
      } finally {
        await pdf.dispose();
      }
    } catch (e) {
      debugPrint('thumbnail failed for $path: $e');
      return null;
    } finally {
      _release();
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
