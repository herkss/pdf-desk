import 'dart:ui';

import '../../models/annotation.dart';

/// The viewer's tools.
enum Tool { select, clip, pen, marker, line, arrow, rect, ellipse, text, sticky, stamp, eraser }

/// What a tool draws with. Every tool keeps its own, so e.g. the pen can be
/// red and thin while the highlighter stays yellow and wide; right-click a
/// tool's button to change it.
class ToolStyle {
  ToolStyle({
    required this.color,
    this.width = 2,
    this.lineStyle = LineStyle.solid,
    this.fill,
    this.fontSize = 14,
    this.fontFamily,
    this.bold = false,
    this.italic = false,
    this.heads = 0,
    this.stampSize = 64,
    this.clipDpi = 200,
    this.clipAnnotations = true,
    this.clipText = true,
    this.eraseInkOnly = false,
  });

  /// Line or text color; for the sticky note, the paper color.
  Color color;
  double width;
  LineStyle lineStyle;
  Color? fill;
  double fontSize;
  String? fontFamily;
  bool bold, italic;

  /// Arrow heads of lines: bit 0 start, bit 1 end.
  int heads;

  /// Stamp: diameter in points.
  double stampSize;

  /// Region copy: resolution, and whether the annotations and the text come
  /// along.
  double clipDpi;
  bool clipAnnotations, clipText;

  /// Eraser: only pen and highlighter strokes (leaves shapes, text, stamps).
  bool eraseInkOnly;

  static ToolStyle defaults(Tool t) => switch (t) {
    Tool.marker => ToolStyle(color: const Color(0xFFFDD835), width: 12),
    Tool.arrow => ToolStyle(color: const Color(0xFFE53935), heads: 2),
    Tool.sticky => ToolStyle(color: const Color(0xFFFFF176)),
    Tool.stamp => ToolStyle(color: const Color(0xFFD32F2F)),
    _ => ToolStyle(color: const Color(0xFFE53935)),
  };

  Map<String, dynamic> toJson() => {
    'color': color.toARGB32(),
    'width': width,
    'lineStyle': lineStyle.name,
    'fill': fill?.toARGB32(),
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'bold': bold,
    'italic': italic,
    'heads': heads,
    'stampSize': stampSize,
    'clipDpi': clipDpi,
    'clipAnnotations': clipAnnotations,
    'clipText': clipText,
    'eraseInkOnly': eraseInkOnly,
  };

  /// Reads [j] over the tool's defaults, so missing keys keep their default.
  static ToolStyle fromJson(Tool t, Map<String, dynamic> j) {
    final d = defaults(t);
    T get<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    double dbl(String k, double fallback) => j[k] is num ? (j[k] as num).toDouble() : fallback;
    return ToolStyle(
      color: j['color'] is int ? Color(j['color'] as int) : d.color,
      width: dbl('width', d.width),
      lineStyle: LineStyle.values.asNameMap()[j['lineStyle']] ?? d.lineStyle,
      fill: j['fill'] is int ? Color(j['fill'] as int) : null,
      fontSize: dbl('fontSize', d.fontSize),
      fontFamily: j['fontFamily'] as String?,
      bold: get('bold', d.bold),
      italic: get('italic', d.italic),
      heads: get('heads', d.heads),
      stampSize: dbl('stampSize', d.stampSize),
      clipDpi: dbl('clipDpi', d.clipDpi),
      clipAnnotations: get('clipAnnotations', d.clipAnnotations),
      clipText: get('clipText', d.clipText),
      eraseInkOnly: get('eraseInkOnly', d.eraseInkOnly),
    );
  }
}

/// Every tool's style, shared by all open documents and remembered between
/// runs (see [toolStylesChanged]).
final toolStyles = {for (final t in Tool.values) t: ToolStyle.defaults(t)};

/// Called after a style changes, to save them; set by the app.
void Function()? toolStylesChanged;

Map<String, dynamic> toolStylesToJson() => {for (final e in toolStyles.entries) e.key.name: e.value.toJson()};

void loadToolStyles(Map<String, dynamic>? j) {
  if (j == null) return;
  for (final t in Tool.values) {
    final v = j[t.name];
    if (v is Map<String, dynamic>) toolStyles[t] = ToolStyle.fromJson(t, v);
  }
}
