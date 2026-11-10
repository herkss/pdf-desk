import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/annotation.dart';
import 'annotation_images.dart';

/// Font for annotation text, matching the font embedded when exporting.
const annotationFontFamily = 'Malgun Gothic';
const annotationFontFallback = ['Noto Sans KR', 'Noto Sans CJK KR', 'Apple SD Gothic Neo', 'sans-serif'];

TextStyle annotationTextStyle(double size, {Color? color, FontWeight? weight, String? family, bool italic = false}) =>
    TextStyle(
      fontSize: size,
      color: color,
      height: 1.25,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : null,
      fontFamily: family ?? annotationFontFamily,
      fontFamilyFallback: [if (family != null) annotationFontFamily, ...annotationFontFallback],
    );

/// The text style of a text box or sticky note.
TextStyle textStyleOf(Annotation a, {Color? color}) => annotationTextStyle(
  a.fontSize,
  color: color,
  family: a.fontFamily,
  weight: a.bold ? FontWeight.bold : null,
  italic: a.italic,
);

/// Dash pattern as multiples of the stroke width ([LineStyle.solid]: none).
/// A zero-length dash with a round cap draws a dot.
List<double> dashPattern(LineStyle style) => switch (style) {
  LineStyle.solid => const [],
  LineStyle.dashed => const [4, 3],
  LineStyle.dotted => const [0, 2.2],
  LineStyle.dashDot => const [6, 2.5, 0, 2.5],
};

/// [path] cut into dashes for [style] at stroke width [width].
Path dashedPath(Path path, LineStyle style, double width) {
  final pattern = dashPattern(style);
  if (pattern.isEmpty) return path;
  final w = math.max(width, 1.0);
  final out = Path();
  for (final m in path.computeMetrics()) {
    var d = 0.0, i = 0;
    while (d < m.length) {
      final len = pattern[i % pattern.length] * w;
      if (i.isEven) out.addPath(m.extractPath(d, d + math.max(len, 0.01)), Offset.zero);
      d += len;
      i++;
    }
  }
  return out;
}

/// Paints annotations of one page. Annotation coordinates are page points;
/// [scale] converts them to logical pixels.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.annotations,
    required this.scale,
    this.selectedIds = const {},
    this.draft,
    this.repaint,
  }) : super(repaint: Listenable.merge([repaint, AnnotationImages.instance]));

  final List<Annotation> annotations;
  final double scale;
  final Set<String> selectedIds;
  final Annotation? draft;
  final Listenable? repaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    for (final a in annotations) {
      paintAnnotation(canvas, a);
    }
    if (draft != null) paintAnnotation(canvas, draft!);
    for (final a in annotations) {
      if (selectedIds.contains(a.id)) _paintSelection(canvas, a);
    }
    canvas.restore();
  }

  void _paintSelection(Canvas canvas, Annotation a) {
    final r = a.bounds.inflate(4 + a.strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..color = const Color(0xFF1E88E5);
    canvas.drawRect(r, paint);
    final h = Paint()..color = const Color(0xFF1E88E5);
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawRect(Rect.fromCenter(center: c, width: 6 / scale, height: 6 / scale), h);
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter old) => true;
}

void paintAnnotation(Canvas canvas, Annotation a) {
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = a.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = a.color;
  void drawStroke(Path path) {
    if (a.strokeWidth <= 0) return;
    canvas.drawPath(dashedPath(path, a.lineStyle, a.strokeWidth), stroke);
  }

  switch (a.type) {
    case AnnotationType.pen:
    case AnnotationType.marker:
      if (a.points.isEmpty) return;
      if (a.type == AnnotationType.marker) {
        stroke
          ..color = a.color.withValues(alpha: 0.4)
          ..strokeCap = StrokeCap.butt
          ..blendMode = BlendMode.multiply;
      }
      final path = Path()..moveTo(a.points.first.dx, a.points.first.dy);
      for (final p in a.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (a.points.length == 1) path.lineTo(a.points.first.dx + 0.1, a.points.first.dy);
      a.type == AnnotationType.marker ? canvas.drawPath(path, stroke) : drawStroke(path);
    case AnnotationType.line:
    case AnnotationType.arrow:
      if (a.points.length < 2) return;
      final p1 = a.points[0], p2 = a.points[1];
      drawStroke(
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy),
      );
      // Heads are always solid.
      for (final (on, from, to) in [(a.startHead, p2, p1), (a.endHead, p1, p2)]) {
        if (!on) continue;
        for (final head in arrowHead(from, to, a.strokeWidth)) {
          canvas.drawLine(to, head, stroke);
        }
      }
    case AnnotationType.rect:
    case AnnotationType.ellipse:
      final r = a.bounds;
      final shape = a.type == AnnotationType.rect ? (Path()..addRect(r)) : (Path()..addOval(r));
      if (a.fill != null) canvas.drawPath(shape, Paint()..color = a.fill!);
      drawStroke(shape);
    case AnnotationType.text:
      final r = a.bounds;
      if (a.fill != null) canvas.drawRect(r, Paint()..color = a.fill!);
      _paintText(canvas, a, r.topLeft + const Offset(2, 2), r.width - 4);
    case AnnotationType.sticky:
      final r = a.bounds;
      canvas.drawRect(r.shift(const Offset(1.5, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.15));
      canvas.drawRect(r, Paint()..color = a.fill ?? const Color(0xFFFFF176));
      _paintText(canvas, a, r.topLeft + const Offset(4, 4), r.width - 8);
    case AnnotationType.stamp:
      paintStamp(canvas, a.bounds, a.text, a.color);
    case AnnotationType.image:
      final r = a.bounds;
      final img = a.image == null ? null : AnnotationImages.instance.get(a.image!);
      if (img == null) {
        canvas.drawRect(r, Paint()..color = const Color(0x22808080));
        return;
      }
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        r,
        Paint()..filterQuality = FilterQuality.medium,
      );
  }
}

/// Returns the two end points of an arrow head at [to].
List<Offset> arrowHead(Offset from, Offset to, double strokeWidth) {
  final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
  final len = 8 + strokeWidth * 3;
  return [
    to - Offset(math.cos(angle - 0.45), math.sin(angle - 0.45)) * len,
    to - Offset(math.cos(angle + 0.45), math.sin(angle + 0.45)) * len,
  ];
}

void _paintText(Canvas canvas, Annotation a, Offset at, double maxWidth) {
  final tp = TextPainter(
    text: TextSpan(
      text: a.text,
      style: textStyleOf(a, color: a.color),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, maxWidth));
  tp.paint(canvas, at);
}

/// DocuWorks-style date stamp: a circle split by two lines into
/// top label / date / name.
void paintStamp(Canvas canvas, Rect r, String text, Color color) {
  final lines = stampLines(text);
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, r.width / 40)
    ..color = color;
  canvas.drawOval(r, stroke);
  final third = r.height / 3;
  final y1 = r.top + third, y2 = r.top + third * 2;
  final halfChord = math.sqrt(math.max(0, 1 - math.pow((third / 2) / (r.height / 2), 2))) * r.width / 2;
  canvas.drawLine(Offset(r.center.dx - halfChord, y1), Offset(r.center.dx + halfChord, y1), stroke);
  canvas.drawLine(Offset(r.center.dx - halfChord, y2), Offset(r.center.dx + halfChord, y2), stroke);
  for (var i = 0; i < 3; i++) {
    final band = Rect.fromLTWH(r.left, r.top + third * i, r.width, third);
    final fontSize = i == 1 ? third * 0.5 : third * 0.42;
    final tp = TextPainter(
      text: TextSpan(
        text: lines[i],
        style: annotationTextStyle(fontSize, color: color, weight: FontWeight.w600).copyWith(height: 1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: r.width * 0.85);
    tp.paint(canvas, band.center - Offset(tp.width / 2, tp.height / 2));
  }
}

List<String> stampLines(String text) {
  final lines = text.split('\n');
  while (lines.length < 3) {
    lines.add('');
  }
  return lines;
}
