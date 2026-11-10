import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/annotation.dart';
import '../common/annotation_painter.dart';
import 'viewer_controller.dart';

/// Renders [region] (page points) of [page] with its annotations into an
/// image annotation of the same size and place, and collects the page text
/// inside it. Null if the page can't be rendered.
Future<(Annotation, String)?> copyPageRegion(ViewerController c, int page, Rect region) async {
  final pdfPage = c.pages[page];
  final size = c.pageSize(page);
  final r = region.intersect(Offset.zero & size);
  if (r.isEmpty) return null;
  // About 200 dpi, but no side over 3000 px.
  final scale = math.min(200 / 72, 3000 / math.max(r.width, r.height));
  final w = (r.width * scale).round(), h = (r.height * scale).round();
  final rendered = await pdfPage.render(
    x: (r.left * scale).round(),
    y: (r.top * scale).round(),
    width: w,
    height: h,
    fullWidth: size.width * scale,
    fullHeight: size.height * scale,
    backgroundColor: 0xFFFFFFFF,
  );
  if (rendered == null) return null;
  final pageImage = await rendered.createImage();
  rendered.dispose();

  // Page, then the annotations on it, as the user sees them.
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(pageImage, Offset.zero, ui.Paint());
  canvas
    ..scale(scale)
    ..translate(-r.left, -r.top);
  for (final a in c.annotationsOn(page)) {
    if (a.bounds.overlaps(r.inflate(a.strokeWidth))) paintAnnotation(canvas, a);
  }
  final picture = recorder.endRecording();
  final composed = await picture.toImage(w, h);
  picture.dispose();
  pageImage.dispose();
  final png = await composed.toByteData(format: ui.ImageByteFormat.png);
  composed.dispose();
  if (png == null) return null;

  final image = Annotation(
    type: AnnotationType.image,
    page: page,
    points: [r.topLeft, r.bottomRight],
    image: base64Encode(png.buffer.asUint8List()),
  );
  return (image, await _textIn(c, page, r));
}

/// Characters whose box centre lies in [r], with line breaks kept.
Future<String> _textIn(ViewerController c, int page, Rect r) async {
  try {
    final pdfPage = c.pages[page];
    final text = await pdfPage.loadText();
    if (text == null) return '';
    final out = StringBuffer();
    var lastTop = double.nan;
    for (var i = 0; i < text.charRects.length && i < text.fullText.length; i++) {
      final box = text.charRects[i].toRect(page: pdfPage);
      if (box.width <= 0 && box.height <= 0) continue;
      if (!r.contains(box.center)) continue;
      if (!lastTop.isNaN && (box.top - lastTop).abs() > box.height * 0.6) out.write('\n');
      lastTop = box.top;
      out.write(text.fullText[i]);
    }
    return out.toString();
  } catch (e) {
    debugPrint('region text: $e');
    return '';
  }
}
