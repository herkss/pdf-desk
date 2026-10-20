import 'dart:ui';

import 'package:uuid/uuid.dart';

/// Kinds of annotation, modeled on DocuWorks' annotation tools.
enum AnnotationType {
  pen, // 펜 (freehand)
  marker, // 형광펜 (translucent freehand)
  line, // 직선
  arrow, // 화살표
  rect, // 사각형
  ellipse, // 타원
  text, // 텍스트
  sticky, // 부전 (sticky note)
  stamp, // 날짜 도장
}

const _uuid = Uuid();

/// One annotation on one page.
///
/// Coordinates are PDF points (1/72 inch) in the page's *displayed*
/// orientation, origin at the top-left corner, y growing downward.
class Annotation {
  Annotation({
    String? id,
    required this.type,
    required this.page,
    required this.points,
    this.color = const Color(0xFFE53935),
    this.strokeWidth = 2,
    this.text = '',
    this.fontSize = 14,
    this.fill,
  }) : id = id ?? _uuid.v4();

  final String id;
  final AnnotationType type;

  /// 0-based page index.
  int page;

  /// Freehand: all points. Shapes: [start, end]. Text/sticky/stamp: [topLeft, bottomRight].
  List<Offset> points;
  Color color;
  double strokeWidth;

  /// Text, sticky: the content. Stamp: three lines (top label, date, name).
  String text;
  double fontSize;
  Color? fill;

  bool get isBoxed => type == AnnotationType.text || type == AnnotationType.sticky || type == AnnotationType.stamp;

  bool get isFreehand => type == AnnotationType.pen || type == AnnotationType.marker;

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var l = points.first.dx, t = points.first.dy, r = l, b = t;
    for (final p in points) {
      if (p.dx < l) l = p.dx;
      if (p.dx > r) r = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dy > b) b = p.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Annotation copy() => Annotation(
    id: id,
    type: type,
    page: page,
    points: List.of(points),
    color: color,
    strokeWidth: strokeWidth,
    text: text,
    fontSize: fontSize,
    fill: fill,
  );

  void translate(Offset delta) {
    points = [for (final p in points) p + delta];
  }

  /// Hit test with a tolerance in page points.
  bool hitTest(Offset p, {double tolerance = 6}) {
    final tol = tolerance + strokeWidth / 2;
    switch (type) {
      case AnnotationType.pen:
      case AnnotationType.marker:
        for (var i = 1; i < points.length; i++) {
          if (_distToSegment(p, points[i - 1], points[i]) <= tol) return true;
        }
        return points.length == 1 && (points.first - p).distance <= tol;
      case AnnotationType.line:
      case AnnotationType.arrow:
        return points.length == 2 && _distToSegment(p, points[0], points[1]) <= tol;
      case AnnotationType.rect:
      case AnnotationType.ellipse:
        final r = bounds;
        if (fill != null) return r.inflate(tol).contains(p);
        return r.inflate(tol).contains(p) && !r.deflate(tol).contains(p);
      case AnnotationType.text:
      case AnnotationType.sticky:
      case AnnotationType.stamp:
        return bounds.inflate(2).contains(p);
    }
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'page': page,
    'points': [
      for (final p in points) [_r(p.dx), _r(p.dy)],
    ],
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    if (text.isNotEmpty) 'text': text,
    'fontSize': fontSize,
    if (fill != null) 'fill': fill!.toARGB32(),
  };

  static double _r(double v) => (v * 100).roundToDouble() / 100;

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
    id: j['id'] as String?,
    type: AnnotationType.values.byName(j['type'] as String),
    page: j['page'] as int,
    points: [for (final p in (j['points'] as List)) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())],
    color: Color(j['color'] as int),
    strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 2,
    text: j['text'] as String? ?? '',
    fontSize: (j['fontSize'] as num?)?.toDouble() ?? 14,
    fill: j['fill'] == null ? null : Color(j['fill'] as int),
  );
}

/// Maps a point when a page of displayed size [size] is rotated clockwise by
/// [quarterTurns] × 90°.
Offset rotatePoint(Offset p, Size size, int quarterTurns) {
  var pt = p;
  var s = size;
  for (var i = 0; i < quarterTurns % 4; i++) {
    pt = Offset(s.height - pt.dy, pt.dx);
    s = Size(s.height, s.width);
  }
  return pt;
}

/// Rotates an annotation together with its page. Boxed annotations keep their
/// upright orientation and size; only their anchor moves.
void rotateAnnotation(Annotation a, Size pageSize, int quarterTurns) {
  if (a.isBoxed) {
    final b = a.bounds;
    final center = rotatePoint(b.center, pageSize, quarterTurns);
    a.points = [center - Offset(b.width / 2, b.height / 2), center + Offset(b.width / 2, b.height / 2)];
  } else {
    a.points = [for (final p in a.points) rotatePoint(p, pageSize, quarterTurns)];
  }
}
