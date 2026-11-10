import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/annotation.dart';
import '../../services/desk_controller.dart';
import '../../services/pdf_ops.dart' as ops;
import '../../services/storage.dart';
import '../../services/thumbnails.dart';
import '../common/annotation_painter.dart';
import '../common/app_theme.dart';
import '../../l10n/l10n.dart';

/// Right-hand preview of the clicked document: one page at a time with its
/// annotations, ◀ ▶ (or ←/→, PageUp/PageDown, the mouse wheel) to page
/// through. Binders page through all their documents in order.
class PreviewPane extends StatefulWidget {
  const PreviewPane({super.key, required this.entry, required this.onOpen});
  final DeskEntry? entry;
  final void Function(DeskEntry) onOpen;

  @override
  State<PreviewPane> createState() => PreviewPaneState();
}

class _Doc {
  _Doc(this.path, this.pdf, this.annotations);
  final String path;
  final PdfDocument pdf;
  final List<Annotation> annotations;
}

class PreviewPaneState extends State<PreviewPane> {
  /// Documents of the entry (one, or each document of a binder).
  List<_Doc> _docs = [];

  /// (document index, page index) for every page.
  List<(int, int)> _pages = [];
  int _page = 0;
  bool _loading = false;
  int _generation = 0;

  int get pageCount => _pages.length;

  @override
  void initState() {
    super.initState();
    ThumbnailService.instance.revision.addListener(_reload);
    _load();
  }

  @override
  void didUpdateWidget(PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry?.path != widget.entry?.path) {
      _page = 0;
      _load();
    }
  }

  @override
  void dispose() {
    ThumbnailService.instance.revision.removeListener(_reload);
    _disposeDocs(_docs);
    super.dispose();
  }

  /// The document changed on disk: reload but stay on the same page.
  void _reload() => _load();

  Future<void> _load() async {
    final gen = ++_generation;
    final entry = widget.entry;
    if (entry == null) {
      _disposeDocs(_docs);
      setState(() {
        _docs = [];
        _pages = [];
      });
      return;
    }
    setState(() => _loading = true);
    final docs = <_Doc>[];
    try {
      final paths = entry.isBinder ? await binderDocuments(entry.path) : [entry.path];
      for (final path in paths) {
        docs.add(_Doc(path, await ops.openPdfInMemory(path), await loadAnnotations(path)));
      }
    } catch (e) {
      debugPrint('preview failed for ${entry.path}: $e');
    }
    if (!mounted || gen != _generation) {
      _disposeDocs(docs);
      return;
    }
    final old = _docs;
    setState(() {
      _docs = docs;
      _pages = [
        for (final (d, doc) in docs.indexed)
          for (var i = 0; i < doc.pdf.pages.length; i++) (d, i),
      ];
      _page = _page.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
      _loading = false;
    });
    // After the next frame, once nothing shows the old pages any more.
    WidgetsBinding.instance.addPostFrameCallback((_) => _disposeDocs(old));
  }

  void _disposeDocs(List<_Doc> docs) {
    for (final d in docs) {
      d.pdf.dispose();
    }
  }

  void goTo(int page) {
    if (_pages.isEmpty) return;
    final p = page.clamp(0, _pages.length - 1);
    if (p != _page) setState(() => _page = p);
  }

  void next() => goTo(_page + 1);
  void previous() => goTo(_page - 1);

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Container(
      color: context.palette.pane,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(border: Border(bottom: context.hairline)),
            child: Row(
              children: [
                Icon(Icons.preview_outlined, size: 16, color: context.ink2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry == null ? tr('미리보기') : entry.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (entry != null) TextButton(onPressed: () => widget.onOpen(entry), child: Text(tr('열기'))),
              ],
            ),
          ),
          Expanded(child: _body(entry)),
          if (_pages.length > 1) _pager(),
        ],
      ),
    );
  }

  Widget _body(DeskEntry? entry) {
    if (entry == null) {
      return Center(
        child: Text(tr('문서를 클릭하면 여기에 표시됩니다'), style: TextStyle(color: context.ink3, fontSize: 13)),
      );
    }
    if (_pages.isEmpty) {
      return Center(
        child: _loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(tr('미리 볼 수 없습니다'), style: TextStyle(color: context.ink3)),
      );
    }
    final (d, i) = _pages[_page];
    final doc = _docs[d];
    final page = doc.pdf.pages[i];
    final annotations = doc.annotations.where((a) => a.page == i).toList();
    return Listener(
      // Wheel pages through the document, like flipping sheets.
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) e.scrollDelta.dy > 0 ? next() : previous();
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                fit: StackFit.expand,
                children: [
                  PdfPageView(
                    key: ValueKey('${doc.path}#$i'),
                    document: doc.pdf,
                    pageNumber: i + 1,
                    maximumDpi: 200,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                  ),
                  if (annotations.isNotEmpty)
                    CustomPaint(
                      painter: AnnotationPainter(annotations: annotations, scale: c.maxWidth / page.width),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pager() {
    final (d, _) = _pages[_page];
    final binderDoc = _docs.length > 1 ? _docs[d].path.split(RegExp(r'[\\/]')).last : null;
    return Container(
      height: 44,
      decoration: BoxDecoration(border: Border(top: context.hairline)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: tr('첫 페이지'),
            onPressed: _page > 0 ? () => goTo(0) : null,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: tr('이전 페이지 (←)'),
            onPressed: _page > 0 ? previous : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${_page + 1} / ${_pages.length}', style: const TextStyle(fontSize: 13)),
              if (binderDoc != null) Text(binderDoc, style: TextStyle(fontSize: 10.5, color: context.ink3)),
            ],
          ),
          IconButton(
            tooltip: tr('다음 페이지 (→)'),
            onPressed: _page < _pages.length - 1 ? next : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: tr('마지막 페이지'),
            onPressed: _page < _pages.length - 1 ? () => goTo(_pages.length - 1) : null,
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }
}
