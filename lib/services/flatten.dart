import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import '../models/annotation.dart';
import '../ui/common/annotation_painter.dart' show annotationTextStyle, arrowHead, stampLines;

/// Per-isolate; only used on pdfrx's worker isolate.
pdfium_bindings.PDFium? _pdfium;

/// Fonts that can render Korean/Japanese/Chinese text. PDFium can only embed
/// single-face TrueType files (not .ttc collections).
const _cjkFontCandidates = [
  r'C:\Windows\Fonts\malgun.ttf',
  r'C:\Windows\Fonts\NanumGothic.ttf',
  '/usr/share/fonts/truetype/nanum/NanumGothic.ttf',
  '/Library/Fonts/AppleGothic.ttf',
  '/System/Library/Fonts/Supplemental/AppleGothic.ttf',
];

Uint8List? _fontCache;

/// The first available font; `PDFDESK_FONT` (a .ttf path) overrides the list.
Future<Uint8List?> _loadCjkFont() async {
  if (_fontCache != null) return _fontCache;
  for (final path in [?Platform.environment['PDFDESK_FONT'], ..._cjkFontCandidates]) {
    final f = File(path);
    if (await f.exists()) return _fontCache = await f.readAsBytes();
  }
  return null;
}

/// One line of text laid out in display space; computed with [TextPainter] so
/// line breaks match what the user saw on screen.
class _TextLine {
  _TextLine(this.text, this.x, this.baseline, this.size, this.align);
  final String text;
  final double x;
  final double baseline;
  final double size;

  /// 0 = left-aligned at x, 1 = centered on x.
  final int align;
}

List<_TextLine> _layoutText(String text, Offset at, double maxWidth, double size) {
  if (text.isEmpty) return [];
  final tp = TextPainter(
    text: TextSpan(text: text, style: annotationTextStyle(size)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, maxWidth));
  final lines = <_TextLine>[];
  for (final m in tp.computeLineMetrics()) {
    final pos = tp.getPositionForOffset(Offset(1, m.baseline - m.ascent / 2));
    final range = tp.getLineBoundary(pos);
    final s = text.substring(range.start, range.end).replaceAll('\n', '');
    if (s.trim().isEmpty) continue;
    lines.add(_TextLine(s, at.dx + m.left, at.dy + m.baseline, size, 0));
  }
  tp.dispose();
  return lines;
}

List<_TextLine> _textLinesFor(Annotation a) {
  final r = a.bounds;
  switch (a.type) {
    case AnnotationType.text:
      return _layoutText(a.text, r.topLeft + const Offset(2, 2), r.width - 4, a.fontSize);
    case AnnotationType.sticky:
      return _layoutText(a.text, r.topLeft + const Offset(4, 4), r.width - 8, a.fontSize);
    case AnnotationType.stamp:
      final lines = stampLines(a.text);
      final third = r.height / 3;
      return [
        for (var i = 0; i < 3; i++)
          if (lines[i].isNotEmpty)
            _TextLine(
              lines[i],
              r.center.dx,
              r.top + third * i + third / 2 + (i == 1 ? third * 0.5 : third * 0.42) * 0.35,
              i == 1 ? third * 0.5 : third * 0.42,
              1,
            ),
      ];
    default:
      return [];
  }
}

/// Affine transform from display space (top-left origin, y down, page
/// rotation applied) to PDF user space. PDF convention:
/// X = a·x + c·y + e, Y = b·x + d·y + f.
class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  final double a, b, c, d, e, f;

  Offset map(Offset p) => Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  /// this ∘ other
  _Affine compose(_Affine o) => _Affine(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  /// [rotation] is the page's /Rotate in quarter turns; [w]×[h] the unrotated
  /// crop box size, offset by ([l], [bt]).
  factory _Affine.forPage(int rotation, double w, double h, double l, double bt) {
    switch (rotation & 3) {
      case 1:
        return _Affine(0, 1, 1, 0, l, bt);
      case 2:
        return _Affine(-1, 0, 0, 1, w + l, bt);
      case 3:
        return _Affine(0, -1, -1, 0, w + l, h + bt);
      default:
        return _Affine(1, 0, 0, -1, l, h + bt);
    }
  }
}

/// Burns [annotations] into [doc]'s page content as regular PDF vector/text
/// objects, so any PDF reader shows them and they print.
Future<void> flattenAnnotations(PdfDocument doc, List<Annotation> annotations) async {
  if (annotations.isEmpty) return;
  final params = _FlattenParams(
    handle: await doc.useNativeDocumentHandle((h) => h),
    annotations: annotations,
    // Text layout needs dart:ui, so it is done here, not in the worker.
    textLines: {for (final a in annotations) a.id: _textLinesFor(a)},
    fontBytes: await _loadCjkFont(),
    modulePath: Pdfrx.pdfiumModulePath,
  );
  // PDFium may call back into pdfrx's font mapper, which only works on
  // pdfrx's worker isolate, so the editing must run there.
  await PdfrxEntryFunctions.instance.compute(_flattenOnWorker, params);
}

class _FlattenParams {
  _FlattenParams({
    required this.handle,
    required this.annotations,
    required this.textLines,
    required this.fontBytes,
    required this.modulePath,
  });
  final int handle;
  final List<Annotation> annotations;
  final Map<String, List<_TextLine>> textLines;
  final Uint8List? fontBytes;
  final String? modulePath;
}

void _flattenOnWorker(_FlattenParams params) {
  final lib = _pdfium ??= pdfium_bindings.getPdfium(modulePath: params.modulePath);
  final fdoc = pdfium_bindings.FPDF_DOCUMENT.fromAddress(params.handle);
  final fontBytes = params.fontBytes;
  final arena = Arena();
  try {
    pdfium_bindings.FPDF_FONT font;
    if (fontBytes != null) {
      final buf = arena<Uint8>(fontBytes.length);
      buf.asTypedList(fontBytes.length).setAll(0, fontBytes);
      font = lib.FPDFText_LoadFont(fdoc, buf, fontBytes.length, pdfium_bindings.FPDF_FONT_TRUETYPE, 1);
    } else {
      font = lib.FPDFText_LoadStandardFont(fdoc, 'Helvetica'.toNativeUtf8(allocator: arena).cast());
    }

    final byPage = <int, List<Annotation>>{};
    for (final a in params.annotations) {
      byPage.putIfAbsent(a.page, () => []).add(a);
    }
    final pageCount = lib.FPDF_GetPageCount(fdoc);
    for (final entry in byPage.entries) {
      if (entry.key < 0 || entry.key >= pageCount) continue;
      final page = lib.FPDF_LoadPage(fdoc, entry.key);
      if (page == nullptr) continue;
      final l = arena<Float>(), b = arena<Float>(), r = arena<Float>(), t = arena<Float>();
      if (lib.FPDFPage_GetCropBox(page, l, b, r, t) == 0 && lib.FPDFPage_GetMediaBox(page, l, b, r, t) == 0) {
        l.value = 0;
        b.value = 0;
        r.value = lib.FPDF_GetPageWidthF(page);
        t.value = lib.FPDF_GetPageHeightF(page);
      }
      final m = _Affine.forPage(lib.FPDFPage_GetRotation(page), r.value - l.value, t.value - b.value, l.value, b.value);
      final w = _Writer(lib, fdoc, page, font, m, arena);
      for (final a in entry.value) {
        w.draw(a, params.textLines[a.id]!);
      }
      lib.FPDFPage_GenerateContent(page);
      lib.FPDF_ClosePage(page);
    }
    if (font != nullptr) lib.FPDFFont_Close(font);
  } finally {
    arena.releaseAll();
  }
}

class _Writer {
  _Writer(this.lib, this.doc, this.page, this.font, this.m, this.arena);
  final pdfium_bindings.PDFium lib;
  final pdfium_bindings.FPDF_DOCUMENT doc;
  final pdfium_bindings.FPDF_PAGE page;
  final pdfium_bindings.FPDF_FONT font;
  final _Affine m;
  final Arena arena;

  int _c(double v) => (v * 255).round().clamp(0, 255);

  void _strokeStyle(pdfium_bindings.FPDF_PAGEOBJECT o, Color c, double width, {double alpha = 1}) {
    lib.FPDFPageObj_SetStrokeColor(o, _c(c.r), _c(c.g), _c(c.b), _c(c.a * alpha));
    lib.FPDFPageObj_SetStrokeWidth(o, width);
    lib.FPDFPageObj_SetLineCap(o, 1); // round
    lib.FPDFPageObj_SetLineJoin(o, 1); // round
  }

  void _fillStyle(pdfium_bindings.FPDF_PAGEOBJECT o, Color c) {
    lib.FPDFPageObj_SetFillColor(o, _c(c.r), _c(c.g), _c(c.b), _c(c.a));
  }

  pdfium_bindings.FPDF_PAGEOBJECT _polyline(List<Offset> pts, {bool close = false}) {
    final first = m.map(pts.first);
    final o = lib.FPDFPageObj_CreateNewPath(first.dx, first.dy);
    for (final pt in pts.skip(1)) {
      final q = m.map(pt);
      lib.FPDFPath_LineTo(o, q.dx, q.dy);
    }
    if (close) lib.FPDFPath_Close(o);
    return o;
  }

  pdfium_bindings.FPDF_PAGEOBJECT _ellipse(Rect r) {
    const k = 0.5522847498;
    final cx = r.center.dx, cy = r.center.dy, rx = r.width / 2, ry = r.height / 2;
    final start = m.map(Offset(cx + rx, cy));
    final o = lib.FPDFPageObj_CreateNewPath(start.dx, start.dy);
    void curve(Offset c1, Offset c2, Offset end) {
      final a = m.map(c1), b = m.map(c2), e = m.map(end);
      lib.FPDFPath_BezierTo(o, a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
    }

    curve(Offset(cx + rx, cy + ry * k), Offset(cx + rx * k, cy + ry), Offset(cx, cy + ry));
    curve(Offset(cx - rx * k, cy + ry), Offset(cx - rx, cy + ry * k), Offset(cx - rx, cy));
    curve(Offset(cx - rx, cy - ry * k), Offset(cx - rx * k, cy - ry), Offset(cx, cy - ry));
    curve(Offset(cx + rx * k, cy - ry), Offset(cx + rx, cy - ry * k), Offset(cx + rx, cy));
    lib.FPDFPath_Close(o);
    return o;
  }

  List<Offset> _rectPts(Rect r) => [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

  void _insert(pdfium_bindings.FPDF_PAGEOBJECT o) => lib.FPDFPage_InsertObject(page, o);

  void _stroke(pdfium_bindings.FPDF_PAGEOBJECT o, Color c, double width, {double alpha = 1}) {
    _strokeStyle(o, c, width, alpha: alpha);
    lib.FPDFPath_SetDrawMode(o, 0, 1);
    _insert(o);
  }

  void _fill(pdfium_bindings.FPDF_PAGEOBJECT o, Color c) {
    _fillStyle(o, c);
    lib.FPDFPath_SetDrawMode(o, pdfium_bindings.FPDF_FILLMODE_ALTERNATE, 0);
    _insert(o);
  }

  void draw(Annotation a, List<_TextLine> lines) {
    switch (a.type) {
      case AnnotationType.pen:
        if (a.points.isNotEmpty) _stroke(_polyline(a.points), a.color, a.strokeWidth);
      case AnnotationType.marker:
        if (a.points.isEmpty) return;
        final o = _polyline(a.points);
        lib.FPDFPageObj_SetBlendMode(o, 'Multiply'.toNativeUtf8(allocator: arena).cast());
        _strokeStyle(o, a.color, a.strokeWidth, alpha: 0.4);
        lib.FPDFPageObj_SetLineCap(o, 0);
        lib.FPDFPath_SetDrawMode(o, 0, 1);
        _insert(o);
      case AnnotationType.line:
      case AnnotationType.arrow:
        if (a.points.length < 2) return;
        _stroke(_polyline(a.points), a.color, a.strokeWidth);
        if (a.type == AnnotationType.arrow) {
          for (final h in arrowHead(a.points[0], a.points[1], a.strokeWidth)) {
            _stroke(_polyline([a.points[1], h]), a.color, a.strokeWidth);
          }
        }
      case AnnotationType.rect:
        if (a.fill != null) _fill(_polyline(_rectPts(a.bounds), close: true), a.fill!);
        _stroke(_polyline(_rectPts(a.bounds), close: true), a.color, a.strokeWidth);
      case AnnotationType.ellipse:
        if (a.fill != null) _fill(_ellipse(a.bounds), a.fill!);
        _stroke(_ellipse(a.bounds), a.color, a.strokeWidth);
      case AnnotationType.text:
        if (a.fill != null) _fill(_polyline(_rectPts(a.bounds), close: true), a.fill!);
        _text(lines, a.color);
      case AnnotationType.sticky:
        _fill(_polyline(_rectPts(a.bounds), close: true), a.fill ?? const Color(0xFFFFF176));
        _text(lines, a.color);
      case AnnotationType.stamp:
        final r = a.bounds;
        final sw = math.max(1.0, r.width / 40);
        _stroke(_ellipse(r), a.color, sw);
        final third = r.height / 3;
        final halfChord = math.sqrt(1 - math.pow((third / 2) / (r.height / 2), 2)) * r.width / 2;
        for (final y in [r.top + third, r.top + third * 2]) {
          _stroke(_polyline([Offset(r.center.dx - halfChord, y), Offset(r.center.dx + halfChord, y)]), a.color, sw);
        }
        _text(lines, a.color);
    }
  }

  void _text(List<_TextLine> lines, Color color) {
    if (font == nullptr) return;
    for (final line in lines) {
      final o = lib.FPDFPageObj_CreateTextObj(doc, font, line.size);
      if (o == nullptr) continue;
      final units = line.text.codeUnits;
      final ws = arena<Uint16>(units.length + 1);
      ws.asTypedList(units.length + 1)
        ..setAll(0, units)
        ..[units.length] = 0;
      lib.FPDFText_SetText(o, ws.cast());
      _fillStyle(o, color);

      var x = line.x;
      if (line.align == 1) {
        final l = arena<Float>(), b = arena<Float>(), r = arena<Float>(), t = arena<Float>();
        if (lib.FPDFPageObj_GetBounds(o, l, b, r, t) != 0) x -= (r.value - l.value) / 2;
      }
      // Text space has y up; flip into display space at the baseline, then map
      // to user space.
      final tm = m.compose(_Affine(1, 0, 0, -1, x, line.baseline));
      lib.FPDFPageObj_Transform(o, tm.a, tm.b, tm.c, tm.d, tm.e, tm.f);
      _insert(o);
    }
  }
}
