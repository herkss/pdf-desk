import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:pdfrx/pdfrx.dart';

import '../../models/annotation.dart';
import '../../services/pdf_ops.dart';
import '../../services/storage.dart';
import '../common/annotation_painter.dart' show textStyleOf;

enum Tool { select, pen, marker, line, arrow, rect, ellipse, text, sticky, stamp, eraser }

const annotationColors = [
  Color(0xFFE53935), // red
  Color(0xFF1E88E5), // blue
  Color(0xFF212121), // black
  Color(0xFF43A047), // green
  Color(0xFFFB8C00), // orange
  Color(0xFF8E24AA), // purple
  Color(0xFFFDD835), // yellow
  Color(0xFFEC407A), // pink
  Color(0xFF00ACC1), // cyan
  Color(0xFF6D4C41), // brown
  Color(0xFF9E9E9E), // gray
  Color(0xFFFFFFFF), // white
];

const stickyColors = [Color(0xFFFFF176), Color(0xFFFFCC80), Color(0xFFA5D6A7), Color(0xFF90CAF9), Color(0xFFF48FB1)];

class SearchHit {
  SearchHit(this.page, this.rects);
  final int page;

  /// Display-space rects in page points.
  final List<Rect> rects;
}

/// State of one open document: pages, annotations, editing tool and history.
class ViewerController extends ChangeNotifier {
  ViewerController(this.path);

  final String path;
  PdfDocument? document;
  List<Annotation> annotations = [];
  Object? loadError;

  Tool tool = Tool.select;
  Color color = annotationColors.first;
  Color markerColor = const Color(0xFFFDD835);
  Color stickyColor = stickyColors.first;
  double strokeWidth = 2;
  double fontSize = 14;

  /// Style for new shapes and text boxes.
  Color? fill;
  LineStyle lineStyle = LineStyle.solid;
  String? fontFamily;
  bool bold = false;
  bool italic = false;

  /// Colors picked from the full palette, newest first.
  final recentColors = <Color>[];
  bool showAnnotations = true;

  final selectedIds = <String>{};

  /// Pages selected in the thumbnail sidebar (0-based).
  final selectedPages = <int>{};

  double zoom = 1.0;
  int currentPage = 0;

  final _undo = <String>[];
  final _redo = <String>[];
  Timer? _saveTimer;
  bool _dirty = false;
  List<Annotation> _clipboard = [];

  /// Repaints annotation layers without rebuilding widgets.
  final repaint = ValueNotifier(0);

  // Search
  String searchQuery = '';
  List<SearchHit> searchHits = [];
  int searchIndex = -1;
  bool searching = false;

  List<PdfPage> get pages => document?.pages ?? const [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> load() async {
    try {
      final old = document;
      document = await openPdfInMemory(path);
      await old?.dispose();
      annotations = await loadAnnotations(path);
      selectedIds.clear();
      selectedPages.removeWhere((p) => p >= pages.length);
      if (currentPage >= pages.length) currentPage = pages.isEmpty ? 0 : pages.length - 1;
      _clearSearch();
      loadError = null;
    } catch (e) {
      loadError = e;
    }
    notifyListeners();
  }

  List<Annotation> annotationsOn(int page) => [
    for (final a in annotations)
      if (a.page == page) a,
  ];

  Size pageSize(int index) => Size(pages[index].width, pages[index].height);

  // --- editing -------------------------------------------------------------

  String _snapshot() => jsonEncode([for (final a in annotations) a.toJson()]);

  void _restore(String snap) {
    annotations = [for (final j in jsonDecode(snap) as List) Annotation.fromJson(j as Map<String, dynamic>)];
    selectedIds.removeWhere((id) => !annotations.any((a) => a.id == id));
  }

  /// Call before any annotation change so it can be undone.
  void checkpoint() {
    _undo.add(_snapshot());
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
  }

  String? _editStart;

  /// Groups a series of [editSelected] calls into one undo step; nothing is
  /// recorded if nothing changed.
  void beginEdit() => _editStart = _snapshot();

  void endEdit() {
    final start = _editStart;
    _editStart = null;
    if (start == null || start == _snapshot()) return;
    _undo.add(start);
    _redo.clear();
  }

  void changed() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), save);
    repaint.value++;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    changed();
  }

  void add(Annotation a) {
    checkpoint();
    annotations.add(a);
    selectedIds
      ..clear()
      ..add(a.id);
    changed();
  }

  void deleteSelected() {
    if (selectedIds.isEmpty) return;
    checkpoint();
    annotations.removeWhere((a) => selectedIds.contains(a.id));
    selectedIds.clear();
    changed();
  }

  void deleteAnnotation(Annotation a) {
    checkpoint();
    annotations.removeWhere((x) => x.id == a.id);
    selectedIds.remove(a.id);
    changed();
  }

  List<Annotation> get selected => annotations.where((a) => selectedIds.contains(a.id)).toList();

  void select(Annotation? a, {bool additive = false}) {
    if (!additive) selectedIds.clear();
    if (a != null) {
      additive && selectedIds.contains(a.id) ? selectedIds.remove(a.id) : selectedIds.add(a.id);
    }
    repaint.value++;
    notifyListeners();
  }

  void selectAllOnPage(int page) {
    selectedIds
      ..clear()
      ..addAll(annotationsOn(page).map((a) => a.id));
    repaint.value++;
    notifyListeners();
  }

  void bringToFront() {
    final sel = selected;
    if (sel.isEmpty) return;
    checkpoint();
    annotations
      ..removeWhere((a) => selectedIds.contains(a.id))
      ..addAll(sel);
    changed();
  }

  void sendToBack() {
    final sel = selected;
    if (sel.isEmpty) return;
    checkpoint();
    annotations
      ..removeWhere((a) => selectedIds.contains(a.id))
      ..insertAll(0, sel);
    changed();
  }

  void copySelected() => _clipboard = [for (final a in selected) a.copy()];

  void paste(int page) {
    if (_clipboard.isEmpty) return;
    checkpoint();
    selectedIds.clear();
    for (final c in _clipboard) {
      final a = Annotation.fromJson(c.toJson()..remove('id'))..page = page;
      if (c.page == page) a.translate(const Offset(12, 12));
      annotations.add(a);
      selectedIds.add(a.id);
    }
    _clipboard = [for (final a in selected) a.copy()];
    changed();
  }

  void setTool(Tool t) {
    tool = t;
    if (t != Tool.select) selectedIds.clear();
    repaint.value++;
    notifyListeners();
  }

  /// Applies the color to the current tool and to selected annotations.
  void setColor(Color c) {
    if (tool == Tool.marker) {
      markerColor = c;
    } else if (tool == Tool.sticky) {
      stickyColor = c;
    } else {
      color = c;
    }
    _applyToSelection((a) {
      if (a.type == AnnotationType.sticky) {
        a.fill = c;
      } else {
        a.color = c;
      }
    });
    notifyListeners();
  }

  void setStrokeWidth(double w) {
    strokeWidth = w;
    _applyToSelection((a) {
      if (!a.isBoxed) a.strokeWidth = w;
    });
    notifyListeners();
  }

  void setFontSize(double s) {
    fontSize = s;
    _applyToSelection((a) {
      if (!a.hasText) return;
      a.fontSize = s;
      _fitText(a);
    });
    notifyListeners();
  }

  void setFill(Color? f) {
    fill = f;
    _applyToSelection((a) {
      if (a.canFill && a.type != AnnotationType.sticky) a.fill = f;
    });
    notifyListeners();
  }

  void setLineStyle(LineStyle s) {
    lineStyle = s;
    _applyToSelection((a) {
      if (!a.isBoxed && a.type != AnnotationType.marker) a.lineStyle = s;
    });
    notifyListeners();
  }

  void setFont({String? family, bool? bold, bool? italic}) {
    if (family != null) fontFamily = family;
    if (bold != null) this.bold = bold;
    if (italic != null) this.italic = italic;
    _applyToSelection((a) {
      if (!a.hasText) return;
      if (family != null) a.fontFamily = family;
      if (bold != null) a.bold = bold;
      if (italic != null) a.italic = italic;
      _fitText(a);
    });
    notifyListeners();
  }

  /// Text boxes grow or shrink to their text when the font changes.
  void _fitText(Annotation a) {
    if (a.type != AnnotationType.text) return;
    final size = measureText(a);
    a.points = [a.points.first, a.points.first + Offset(size.width, size.height)];
  }

  void rememberColor(Color c) {
    recentColors
      ..removeWhere((x) => x.toARGB32() == c.toARGB32())
      ..insert(0, c);
    if (recentColors.length > 10) recentColors.removeLast();
  }

  /// Changes selected annotations as the properties dialog is edited, between
  /// [beginEdit] and [endEdit].
  void editSelected(void Function(Annotation) f) {
    for (final a in selected) {
      f(a);
      _fitText(a);
    }
    changed();
  }

  void _applyToSelection(void Function(Annotation) f) {
    final sel = selected;
    if (sel.isEmpty) return;
    checkpoint();
    sel.forEach(f);
    changed();
  }

  Color get activeColor => switch (tool) {
    Tool.marker => markerColor,
    Tool.sticky => stickyColor,
    _ => color,
  };

  void toggleAnnotations() {
    showAnnotations = !showAnnotations;
    if (!showAnnotations) selectedIds.clear();
    repaint.value++;
    notifyListeners();
  }

  void setCurrentPage(int page) {
    if (page == currentPage) return;
    currentPage = page;
    notifyListeners();
  }

  void setZoom(double z) {
    zoom = z.clamp(0.1, 8.0);
    notifyListeners();
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    await saveAnnotations(path, annotations);
  }

  /// Saves, runs a page operation that rewrites the file, and reloads.
  Future<void> pageOperation(Future<void> Function() op) async {
    await save();
    await op();
    _undo.clear();
    _redo.clear();
    await load();
  }

  // --- search --------------------------------------------------------------

  void _clearSearch() {
    searchHits = [];
    searchIndex = -1;
  }

  Future<void> search(String query) async {
    searchQuery = query;
    _clearSearch();
    if (query.trim().isEmpty || document == null) {
      notifyListeners();
      return;
    }
    searching = true;
    notifyListeners();
    final q = query.toLowerCase();
    final doc = document!;
    for (var i = 0; i < doc.pages.length; i++) {
      if (searchQuery != query || document != doc) return;
      final page = doc.pages[i];
      final text = await page.loadText();
      if (text == null) continue;
      final full = text.fullText.toLowerCase();
      var from = 0;
      while (true) {
        final idx = full.indexOf(q, from);
        if (idx < 0) break;
        final rects = <Rect>[];
        for (var c = idx; c < idx + q.length && c < text.charRects.length; c++) {
          final r = text.charRects[c].toRect(page: page);
          if (r.width <= 0 && r.height <= 0) continue;
          if (rects.isNotEmpty && (rects.last.top - r.top).abs() < r.height / 2) {
            rects[rects.length - 1] = rects.last.expandToInclude(r);
          } else {
            rects.add(r);
          }
        }
        searchHits.add(SearchHit(i, rects));
        from = idx + q.length;
      }
    }
    searching = false;
    if (searchHits.isNotEmpty) searchIndex = 0;
    repaint.value++;
    notifyListeners();
  }

  SearchHit? nextHit(int delta) {
    if (searchHits.isEmpty) return null;
    searchIndex = (searchIndex + delta) % searchHits.length;
    repaint.value++;
    notifyListeners();
    return searchHits[searchIndex];
  }

  // --- creation helpers ----------------------------------------------------

  Annotation newStroke(AnnotationType type, int page, Offset at) => Annotation(
    type: type,
    page: page,
    points: [at],
    color: type == AnnotationType.marker ? markerColor : color,
    strokeWidth: type == AnnotationType.marker ? (strokeWidth * 6).clamp(8, 30).toDouble() : strokeWidth,
    lineStyle: type == AnnotationType.marker ? LineStyle.solid : lineStyle,
  );

  Annotation newShape(AnnotationType type, int page, Offset at) => Annotation(
    type: type,
    page: page,
    points: [at, at],
    color: color,
    strokeWidth: strokeWidth,
    lineStyle: lineStyle,
    fill: type == AnnotationType.rect || type == AnnotationType.ellipse ? fill : null,
  );

  Annotation newText(int page, Offset at, String text) {
    final a = Annotation(
      type: AnnotationType.text,
      page: page,
      points: [at, at],
      color: color,
      fill: fill,
      text: text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      bold: bold,
      italic: italic,
    );
    _fitText(a);
    return a;
  }

  Annotation newSticky(int page, Offset at, String text) {
    final a = Annotation(
      type: AnnotationType.sticky,
      page: page,
      points: [at, at],
      color: Colors.black87,
      fill: stickyColor,
      text: text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      bold: bold,
      italic: italic,
    );
    final h = _textHeight(text, 140 - 8, textStyleOf(a)) + 8;
    a.points = [at, at + Offset(140, h.clamp(40, 600))];
    return a;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    save();
    document?.dispose();
    repaint.dispose();
    super.dispose();
  }
}

TextPainter _layout(String text, TextStyle style, double maxWidth) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout(maxWidth: maxWidth);

double _textHeight(String text, double width, TextStyle style) {
  final tp = _layout(text, style, width);
  final h = tp.height;
  tp.dispose();
  return h;
}

/// Size of a text box that fits [a]'s text on one line per paragraph, capped
/// at [maxWidth].
Size measureText(Annotation a, {double maxWidth = 400}) {
  final tp = _layout(a.text, textStyleOf(a), maxWidth);
  final s = Size(tp.width.clamp(10, maxWidth) + 6, tp.height + 4);
  tp.dispose();
  return s;
}
