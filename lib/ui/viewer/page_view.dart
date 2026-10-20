import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/annotation.dart';
import '../../services/settings.dart';
import '../common/annotation_painter.dart';
import '../common/dialogs.dart';
import 'viewer_controller.dart';

/// One PDF page with its annotation layer. Handles drawing and editing input
/// for the current tool; coordinates are converted to page points.
class AnnotatedPage extends StatefulWidget {
  const AnnotatedPage({
    super.key,
    required this.controller,
    required this.index,
    required this.scale,
    required this.settings,
  });

  final ViewerController controller;
  final int index;

  /// Logical pixels per PDF point.
  final double scale;
  final Settings settings;

  @override
  State<AnnotatedPage> createState() => _AnnotatedPageState();
}

enum _Drag { none, draw, move, resize, endpoint0, endpoint1 }

class _AnnotatedPageState extends State<AnnotatedPage> {
  Annotation? _draft;
  _Drag _drag = _Drag.none;
  Offset? _dragStart;
  List<Annotation> _dragOriginals = [];
  bool _checkpointed = false;
  DateTime _lastTap = DateTime(0);

  ViewerController get c => widget.controller;
  int get page => widget.index;

  Offset _toPage(Offset local) => local / widget.scale;

  Annotation? _hit(Offset p) {
    final list = c.annotationsOn(page);
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].hitTest(p, tolerance: 5 / widget.scale + 2)) return list[i];
    }
    return null;
  }

  double get _handleTol => 8 / widget.scale;

  void _onDown(PointerDownEvent e) {
    if (e.buttons == kSecondaryMouseButton) {
      _contextMenu(e.position, _toPage(e.localPosition));
      return;
    }
    if (e.buttons != kPrimaryMouseButton || !c.showAnnotations) return;
    final p = _toPage(e.localPosition);
    c.currentPage = page;
    _checkpointed = false;
    final now = DateTime.now();
    final doubleTap = now.difference(_lastTap) < const Duration(milliseconds: 400);
    _lastTap = now;

    switch (c.tool) {
      case Tool.select:
        _selectDown(p, doubleTap);
      case Tool.pen:
        _draft = c.newStroke(AnnotationType.pen, page, p);
        _drag = _Drag.draw;
      case Tool.marker:
        _draft = c.newStroke(AnnotationType.marker, page, p);
        _drag = _Drag.draw;
      case Tool.line:
      case Tool.arrow:
      case Tool.rect:
      case Tool.ellipse:
        _draft = Annotation(
          type: switch (c.tool) {
            Tool.line => AnnotationType.line,
            Tool.arrow => AnnotationType.arrow,
            Tool.rect => AnnotationType.rect,
            _ => AnnotationType.ellipse,
          },
          page: page,
          points: [p, p],
          color: c.color,
          strokeWidth: c.strokeWidth,
        );
        _drag = _Drag.draw;
      case Tool.text:
        _createText(p);
      case Tool.sticky:
        _createSticky(p);
      case Tool.stamp:
        _createStamp(p);
      case Tool.eraser:
        _drag = _Drag.draw;
        _erase(p);
    }
    c.repaint.value++;
  }

  void _selectDown(Offset p, bool doubleTap) {
    final shift = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isControlPressed;
    // Resize/endpoint handles of a single selection take priority.
    final sel = c.selected.where((a) => a.page == page).toList();
    if (sel.length == 1 && c.selectedIds.length == 1) {
      final a = sel.first;
      if (a.type == AnnotationType.line || a.type == AnnotationType.arrow) {
        if ((a.points[0] - p).distance <= _handleTol) return _startDrag(_Drag.endpoint0, p, [a]);
        if ((a.points[1] - p).distance <= _handleTol) return _startDrag(_Drag.endpoint1, p, [a]);
      } else if (!a.isFreehand) {
        final corner = a.bounds.inflate(4 + a.strokeWidth / 2).bottomRight;
        if ((corner - p).distance <= _handleTol) return _startDrag(_Drag.resize, p, [a]);
      }
    }
    final hit = _hit(p);
    if (hit == null) {
      if (!shift) c.select(null);
      return;
    }
    if (doubleTap && (hit.isBoxed)) {
      _editText(hit);
      return;
    }
    if (shift) {
      c.select(hit, additive: true);
    } else if (!c.selectedIds.contains(hit.id)) {
      c.select(hit);
    }
    _startDrag(_Drag.move, p, c.selected.where((a) => a.page == page).toList());
  }

  void _startDrag(_Drag kind, Offset p, List<Annotation> targets) {
    _drag = kind;
    _dragStart = p;
    _dragOriginals = [for (final a in targets) a.copy()];
  }

  void _onMove(PointerMoveEvent e) {
    if (_drag == _Drag.none) return;
    final p = _toPage(e.localPosition);
    final size = c.pageSize(page);
    final clamped = Offset(p.dx.clamp(0, size.width), p.dy.clamp(0, size.height));
    switch (_drag) {
      case _Drag.draw:
        if (c.tool == Tool.eraser) {
          _erase(p);
        } else if (_draft != null) {
          if (_draft!.isFreehand) {
            if ((_draft!.points.last - clamped).distance * widget.scale >= 1.5) _draft!.points.add(clamped);
          } else {
            var end = clamped;
            if (HardwareKeyboard.instance.isShiftPressed) end = _constrain(_draft!.points.first, end, _draft!.type);
            _draft!.points[1] = end;
          }
        }
      case _Drag.move:
      case _Drag.resize:
      case _Drag.endpoint0:
      case _Drag.endpoint1:
        _applyDrag(p - _dragStart!);
      case _Drag.none:
        break;
    }
    c.repaint.value++;
  }

  /// Shift-drag: horizontal/vertical/45° lines, squares and circles.
  Offset _constrain(Offset start, Offset end, AnnotationType type) {
    final d = end - start;
    if (type == AnnotationType.line || type == AnnotationType.arrow) {
      final angle = (math.atan2(d.dy, d.dx) / (math.pi / 4)).round() * (math.pi / 4);
      return start + Offset(math.cos(angle), math.sin(angle)) * d.distance;
    }
    final s = math.max(d.dx.abs(), d.dy.abs());
    return start + Offset(s * d.dx.sign, s * d.dy.sign);
  }

  void _applyDrag(Offset delta) {
    if (!_checkpointed) {
      if (delta.distance < 0.5) return;
      c.checkpoint();
      _checkpointed = true;
    }
    for (final orig in _dragOriginals) {
      final a = c.annotations.where((x) => x.id == orig.id).firstOrNull;
      if (a == null) continue;
      switch (_drag) {
        case _Drag.move:
          a.points = [for (final pt in orig.points) pt + delta];
        case _Drag.endpoint0:
          a.points = [orig.points[0] + delta, orig.points[1]];
        case _Drag.endpoint1:
          a.points = [orig.points[0], orig.points[1] + delta];
        case _Drag.resize:
          final b = orig.bounds;
          final nw = math.max(8.0, b.width + delta.dx), nh = math.max(8.0, b.height + delta.dy);
          if (orig.type == AnnotationType.stamp) {
            final s = math.max(nw, nh);
            a.points = [b.topLeft, b.topLeft + Offset(s, s)];
          } else {
            a.points = [b.topLeft, b.topLeft + Offset(nw, nh)];
          }
        default:
          break;
      }
    }
  }

  void _onUp(PointerUpEvent e) {
    if (_draft != null) {
      final d = _draft!;
      _draft = null;
      final r = d.bounds;
      final big = d.isFreehand ? d.points.isNotEmpty : (r.width + r.height) * widget.scale > 4;
      if (big) {
        if (!d.isFreehand && (d.type == AnnotationType.rect || d.type == AnnotationType.ellipse)) {
          d.points = [r.topLeft, r.bottomRight];
        }
        c.add(d);
        c.selectedIds.clear();
      }
    } else if (_checkpointed) {
      c.changed();
    }
    _drag = _Drag.none;
    _dragOriginals = [];
    c.repaint.value++;
  }

  void _erase(Offset p) {
    final hit = _hit(p);
    if (hit == null) return;
    c.deleteAnnotation(hit);
  }

  Future<void> _createText(Offset p) async {
    final text = await promptText(context, title: '텍스트 주석', maxLines: 5);
    if (text == null || text.trim().isEmpty) return;
    final size = measureText(text, c.fontSize);
    c.add(
      Annotation(
        type: AnnotationType.text,
        page: page,
        points: [p, p + Offset(size.width, size.height)],
        color: c.color,
        text: text,
        fontSize: c.fontSize,
      ),
    );
  }

  Future<void> _createSticky(Offset p) async {
    final text = await promptText(context, title: '부전 (스티커 메모)', maxLines: 5);
    if (text == null) return;
    c.add(c.newSticky(page, p, text));
  }

  void _createStamp(Offset p) {
    final s = widget.settings;
    final date = DateFormat('yy.MM.dd').format(DateTime.now());
    const size = 64.0;
    c.add(
      Annotation(
        type: AnnotationType.stamp,
        page: page,
        points: [p - const Offset(size / 2, size / 2), p + const Offset(size / 2, size / 2)],
        color: const Color(0xFFD32F2F),
        text: '${s.stampLabel}\n$date\n${s.stampName}',
      ),
    );
  }

  Future<void> _editText(Annotation a) async {
    final String? text;
    if (a.type == AnnotationType.stamp) {
      text = await promptText(context, title: '도장 편집 (윗줄/날짜/이름)', initial: a.text, maxLines: 3);
    } else {
      text = await promptText(context, title: '텍스트 편집', initial: a.text, maxLines: 5);
    }
    if (text == null) return;
    c.checkpoint();
    a.text = text;
    if (a.type == AnnotationType.text) {
      final size = measureText(text, a.fontSize);
      a.points = [a.points.first, a.points.first + Offset(size.width, size.height)];
    }
    c.changed();
  }

  Future<void> _contextMenu(Offset global, Offset p) async {
    final hit = _hit(p);
    if (hit != null && !c.selectedIds.contains(hit.id)) c.select(hit);
    final hasSel = c.selectedIds.isNotEmpty;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        if (hit != null && hit.isBoxed) const PopupMenuItem(value: 'edit', child: Text('텍스트 편집')),
        if (hasSel) ...const [
          PopupMenuItem(value: 'copy', child: Text('복사')),
          PopupMenuItem(value: 'front', child: Text('맨 앞으로')),
          PopupMenuItem(value: 'back', child: Text('맨 뒤로')),
          PopupMenuItem(
            value: 'delete',
            child: Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
        const PopupMenuItem(value: 'paste', child: Text('붙여넣기')),
        const PopupMenuItem(value: 'selectAll', child: Text('이 페이지의 주석 모두 선택')),
      ],
    );
    switch (choice) {
      case 'edit':
        await _editText(hit!);
      case 'copy':
        c.copySelected();
      case 'front':
        c.bringToFront();
      case 'back':
        c.sendToBack();
      case 'delete':
        c.deleteSelected();
      case 'paste':
        c.paste(page);
      case 'selectAll':
        c.selectAllOnPage(page);
    }
  }

  MouseCursor get _cursor => switch (c.tool) {
    Tool.select => SystemMouseCursors.basic,
    Tool.text || Tool.sticky => SystemMouseCursors.text,
    Tool.eraser => SystemMouseCursors.disappearing,
    _ => SystemMouseCursors.precise,
  };

  @override
  Widget build(BuildContext context) {
    final doc = c.document!;
    final size = c.pageSize(page) * widget.scale;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PdfPageView(
            document: doc,
            pageNumber: page + 1,
            maximumDpi: 400,
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
          ),
          MouseRegion(
            cursor: _cursor,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              child: ValueListenableBuilder(
                valueListenable: c.repaint,
                builder: (context, _, _) => CustomPaint(
                  painter: _PageOverlayPainter(
                    scale: widget.scale,
                    annotations: c.showAnnotations ? c.annotationsOn(page) : const [],
                    selectedIds: c.selectedIds,
                    draft: _draft,
                    hits: [
                      for (var i = 0; i < c.searchHits.length; i++)
                        if (c.searchHits[i].page == page) (c.searchHits[i], i == c.searchIndex),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageOverlayPainter extends CustomPainter {
  _PageOverlayPainter({
    required this.scale,
    required this.annotations,
    required this.selectedIds,
    required this.draft,
    required this.hits,
  });

  final double scale;
  final List<Annotation> annotations;
  final Set<String> selectedIds;
  final Annotation? draft;
  final List<(SearchHit, bool)> hits;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (hit, current) in hits) {
      final paint = Paint()
        ..color = (current ? const Color(0xFFFF9800) : const Color(0xFF42A5F5)).withValues(alpha: 0.35);
      for (final r in hit.rects) {
        canvas.drawRect(Rect.fromLTRB(r.left * scale, r.top * scale, r.right * scale, r.bottom * scale), paint);
      }
    }
    AnnotationPainter(
      annotations: annotations,
      scale: scale,
      selectedIds: selectedIds,
      draft: draft,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
