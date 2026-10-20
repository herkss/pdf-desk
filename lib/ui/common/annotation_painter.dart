import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/annotation.dart';

/// Font for annotation text, matching the font embedded when exporting.
const annotationFontFamily = 'Malgun Gothic';
const annotationFontFallback = ['Noto Sans KR', 'Noto Sans CJK KR', 'Apple SD Gothic Neo', 'sans-serif'];

TextStyle annotationTextStyle(double size, {Color? color, FontWeight? weight}) => TextStyle(
  fontSize: size,
  color: color,
  height: 1.25,
  fontWeight: weight,
  fontFamily: annotationFontFamily,
  fontFamilyFallback: annotationFontFallback,
);

/// Paints annotations of one page. Annotation coordinates are page points;
/// [scale] converts them to logical pixels.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.annotations,
    required this.scale,
    this.selectedIds = const {},
    this.draft,
    this.repaint,
  }) : super(repaint: repaint);

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
      canvas.drawPath(path, stroke);
    case AnnotationType.line:
    case AnnotationType.arrow:
      if (a.points.length < 2) return;
      final p1 = a.points[0], p2 = a.points[1];
      canvas.drawLine(p1, p2, stroke);
      if (a.type == AnnotationType.arrow) {
        for (final head in arrowHead(p1, p2, a.strokeWidth)) {
          canvas.drawLine(p2, head, stroke);
        }
      }
    case AnnotationType.rect:
    case AnnotationType.ellipse:
      final r = a.bounds;
      if (a.fill != null) {
        final f = Paint()..color = a.fill!;
        a.type == AnnotationType.rect ? canvas.drawRect(r, f) : canvas.drawOval(r, f);
      }
      a.type == AnnotationType.rect ? canvas.drawRect(r, stroke) : canvas.drawOval(r, stroke);
    case AnnotationType.text:
      final r = a.bounds;
      if (a.fill != null) canvas.drawRect(r, Paint()..color = a.fill!);
      _paintText(canvas, a.text, r.topLeft + const Offset(2, 2), r.width - 4, a.fontSize, a.color);
    case AnnotationType.sticky:
      final r = a.bounds;
      canvas.drawRect(r.shift(const Offset(1.5, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.15));
      canvas.drawRect(r, Paint()..color = a.fill ?? const Color(0xFFFFF176));
      _paintText(canvas, a.text, r.topLeft + const Offset(4, 4), r.width - 8, a.fontSize, a.color);
    case AnnotationType.stamp:
      paintStamp(canvas, a.bounds, a.text, a.color);
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

void _paintText(Canvas canvas, String text, Offset at, double maxWidth, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: annotationTextStyle(size, color: color),
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
