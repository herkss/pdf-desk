import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/annotation.dart';
import '../../services/fonts.dart';
import '../common/annotation_painter.dart';
import 'viewer_controller.dart';
import '../../l10n/l10n.dart';

/// Result of the color picker: a color, or none (no background).
class ColorChoice {
  const ColorChoice(this.color);
  final Color? color;
}

const _hues = [
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.deepPurple,
  Colors.indigo,
  Colors.blue,
  Colors.lightBlue,
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.lightGreen,
  Colors.lime,
  Colors.yellow,
  Colors.amber,
  Colors.orange,
  Colors.deepOrange,
  Colors.brown,
  Colors.blueGrey,
];
const _shades = [50, 100, 200, 300, 500, 700, 900];
const _grays = [
  Color(0xFF000000),
  Color(0xFF212121),
  Color(0xFF424242),
  Color(0xFF616161),
  Color(0xFF9E9E9E),
  Color(0xFFBDBDBD),
  Color(0xFFE0E0E0),
  Color(0xFFEEEEEE),
  Color(0xFFF5F5F5),
  Color(0xFFFFFFFF),
];

bool _same(Color? a, Color? b) => a?.toARGB32() == b?.toARGB32();

String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

Widget _swatch(Color? color, {required bool selected, required VoidCallback onTap, double size = 22}) => InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(size),
  child: Container(
    width: size,
    height: size,
    margin: const EdgeInsets.all(1.5),
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: selected ? Colors.black87 : Colors.black26, width: selected ? 2.5 : 1),
    ),
    // No color: a red slash, like "none" in drawing programs.
    child: color == null ? CustomPaint(painter: _NonePainter()) : null,
  ),
);

class _NonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.8),
      Offset(size.width * 0.8, size.height * 0.2),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_NonePainter old) => false;
}

/// The full palette: 18 hues in 7 shades, grays, recently used colors and a
/// hex code field.
Future<ColorChoice?> showColorPicker(
  BuildContext context, {
  Color? initial,
  bool allowNone = false,
  List<Color> recent = const [],
}) {
  var current = initial;
  final hex = TextEditingController(text: initial == null ? '' : _hex(initial));
  return showDialog<ColorChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void pick(Color? c) => setState(() {
          current = c;
          hex.text = c == null ? '' : _hex(c);
        });
        Widget cell(Color c) => _swatch(c, selected: _same(c, current), onTap: () => pick(c), size: 20);
        return AlertDialog(
          title: Text(tr('색 선택')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final shade in _shades) Row(children: [for (final h in _hues) cell(h[shade]!)]),
                const SizedBox(height: 6),
                Row(children: [for (final g in _grays) cell(g)]),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(tr('최근 사용한 색'), style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Row(children: [for (final c in recent) cell(c)]),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (allowNone) ...[
                      _swatch(null, selected: current == null, onTap: () => pick(null)),
                      Text(tr(' 없음'), style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 16),
                    ],
                    const Text('#', style: TextStyle(fontSize: 14)),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: hex,
                        maxLength: 6,
                        decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'FF0000'),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
                        onChanged: (v) {
                          if (v.length == 6) setState(() => current = Color(0xFF000000 | int.parse(v, radix: 16)));
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 48,
                      height: 26,
                      decoration: BoxDecoration(
                        color: current ?? Colors.white,
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('취소'))),
            FilledButton(onPressed: () => Navigator.pop(context, ColorChoice(current)), child: Text(tr('확인'))),
          ],
        );
      },
    ),
  );
}

/// A few quick colors plus a button that opens the full palette.
class ColorRow extends StatelessWidget {
  const ColorRow({
    super.key,
    required this.colors,
    required this.value,
    required this.onChanged,
    required this.controller,
    this.allowNone = false,
  });

  final List<Color> colors;
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final ViewerController controller;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final quick = [
      ...colors,
      for (final r in controller.recentColors.take(4))
        if (!colors.any((c) => _same(c, r))) r,
    ];
    final custom = value != null && !quick.any((c) => _same(c, value));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (allowNone)
          Tooltip(
            message: tr('없음'),
            child: _swatch(null, selected: value == null, onTap: () => onChanged(null)),
          ),
        for (final c in quick) _swatch(c, selected: _same(c, value), onTap: () => onChanged(c)),
        if (custom) _swatch(value, selected: true, onTap: () {}),
        IconButton(
          tooltip: tr('다른 색…'),
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon: const Icon(Icons.palette_outlined),
          onPressed: () async {
            final r = await showColorPicker(
              context,
              initial: value,
              allowNone: allowNone,
              recent: controller.recentColors,
            );
            if (r == null) return;
            if (r.color != null) controller.rememberColor(r.color!);
            onChanged(r.color);
          },
        ),
      ],
    );
  }
}

/// Fill colors offered first: light tints that keep the page readable.
const fillColors = [
  Color(0xFFFFFFFF),
  Color(0xFFFFF59D),
  Color(0xFFFFCDD2),
  Color(0xFFBBDEFB),
  Color(0xFFC8E6C9),
  Color(0xFFE1BEE7),
  Color(0xFFE0E0E0),
];

Map<LineStyle, String> get lineStyleLabels => {
  LineStyle.solid: tr('실선'),
  LineStyle.dashed: tr('파선'),
  LineStyle.dotted: tr('점선'),
  LineStyle.dashDot: tr('일점쇄선'),
};

/// A short sample of a line style, for menus.
class LineStyleSample extends StatelessWidget {
  const LineStyleSample(this.style, {super.key, this.width = 36});
  final LineStyle style;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, 10), painter: _LineSamplePainter(style));
}

class _LineSamplePainter extends CustomPainter {
  _LineSamplePainter(this.style);
  final LineStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, size.height / 2)
      ..lineTo(size.width - 1, size.height / 2);
    canvas.drawPath(
      dashedPath(path, style, 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.black87,
    );
  }

  @override
  bool shouldRepaint(_LineSamplePainter old) => old.style != style;
}

const fontSizes = [8.0, 9.0, 10.0, 11.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0, 60.0, 72.0];

/// Font family menu with each name drawn in its own font.
Widget fontFamilyMenu({required String? value, required ValueChanged<String> onChanged}) => DropdownButton<String>(
  value: fontChoiceOf(value).family,
  isDense: true,
  underline: const SizedBox(),
  items: [
    for (final f in fontChoices)
      DropdownMenuItem(
        value: f.family,
        child: Text(
          appLanguage.value == AppLanguage.ko ? f.label : f.family,
          style: annotationTextStyle(13, family: f.family),
        ),
      ),
  ],
  onChanged: (v) => onChanged(v!),
);

Widget fontSizeMenu({required double value, required ValueChanged<double> onChanged}) => DropdownButton<double>(
  value: fontSizes.contains(value) ? value : null,
  hint: Text('${value.round()}pt', style: const TextStyle(fontSize: 13)),
  isDense: true,
  underline: const SizedBox(),
  items: [
    for (final s in fontSizes)
      DropdownMenuItem(
        value: s,
        child: Text('${s.toInt()}pt', style: const TextStyle(fontSize: 13)),
      ),
  ],
  onChanged: (v) => onChanged(v!),
);

/// 속성: line color, width and style, arrow heads, background and opacity,
/// font — whatever applies to the selected annotations. Changes show live
/// and undo as one step.
Future<void> showAnnotationStyleDialog(BuildContext context, ViewerController c) async {
  final sel = c.selected;
  if (sel.isEmpty) return;
  c.beginEdit();
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black12,
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final items = c.selected;
        if (items.isEmpty) return const SizedBox();
        final first = items.first;
        final lines = items.where((a) => a.isLine).toList();
        final stroked = items.where((a) => !a.isBoxed).toList();
        final shapesOnly = stroked.isNotEmpty && stroked.every((a) => a.isShape);
        final fillable = items.where((a) => a.canFill).toList();
        final texts = items.where((a) => a.hasText).toList();
        final stamps = items.any((a) => a.type == AnnotationType.stamp);
        final dashable = stroked.where((a) => a.type != AnnotationType.marker).toList();

        Widget section(String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              ...rows,
            ],
          ),
        );
        Widget row(String label, Widget child) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              ),
              Flexible(child: child),
            ],
          ),
        );

        final lineRef = stroked.isNotEmpty ? stroked.first : null;
        final fillRef = fillable.isNotEmpty ? fillable.first : null;
        final textRef = texts.isNotEmpty ? texts.first : null;
        return AlertDialog(
          title: Text(items.length == 1 ? tr('주석 속성') : tr('주석 속성 ({n}개)', {'n': items.length})),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lineRef != null || stamps)
                    section(tr('선'), [
                      row(
                        tr('선 색'),
                        ColorRow(
                          controller: c,
                          colors: annotationColors,
                          value: (lineRef ?? first).color,
                          onChanged: (v) => c.editSelected((a) {
                            if (!a.hasText && v != null) a.color = v;
                          }),
                        ),
                      ),
                      if (lineRef != null)
                        row(
                          tr('굵기'),
                          Wrap(
                            spacing: 4,
                            children: [
                              for (final w in [if (shapesOnly) 0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0])
                                ChoiceChip(
                                  label: Text(w == 0 ? tr('없음') : '${w}pt'.replaceAll('.0pt', 'pt')),
                                  selected: lineRef.strokeWidth == w,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) => c.editSelected((a) {
                                    if (!a.isBoxed && (w > 0 || a.isShape)) a.strokeWidth = w;
                                  }),
                                ),
                            ],
                          ),
                        ),
                      if (dashable.isNotEmpty)
                        row(
                          tr('선 종류'),
                          Wrap(
                            spacing: 4,
                            children: [
                              for (final s in LineStyle.values)
                                ChoiceChip(
                                  avatar: LineStyleSample(s, width: 26),
                                  label: Text(lineStyleLabels[s]!),
                                  showCheckmark: false,
                                  selected: dashable.first.lineStyle == s,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (_) => c.editSelected((a) {
                                    if (!a.isBoxed && a.type != AnnotationType.marker) a.lineStyle = s;
                                  }),
                                ),
                            ],
                          ),
                        ),
                      if (lines.isNotEmpty)
                        row(
                          tr('화살표'),
                          Wrap(
                            spacing: 4,
                            children: [
                              FilterChip(
                                label: Text(tr('시작점')),
                                selected: lines.first.startHead,
                                visualDensity: VisualDensity.compact,
                                onSelected: (on) => c.editSelected((a) {
                                  if (a.isLine) a.heads = (on ? 1 : 0) | (a.endHead ? 2 : 0);
                                }),
                              ),
                              FilterChip(
                                label: Text(tr('끝점')),
                                selected: lines.first.endHead,
                                visualDensity: VisualDensity.compact,
                                onSelected: (on) => c.editSelected((a) {
                                  if (a.isLine) a.heads = (a.startHead ? 1 : 0) | (on ? 2 : 0);
                                }),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  if (fillRef != null)
                    section(tr('배경'), [
                      row(
                        tr('배경색'),
                        ColorRow(
                          controller: c,
                          colors: fillRef.type == AnnotationType.sticky ? stickyColors : fillColors,
                          allowNone: fillRef.type != AnnotationType.sticky,
                          value: fillRef.fill?.withValues(alpha: 1),
                          onChanged: (v) => c.editSelected((a) {
                            if (!a.canFill) return;
                            if (v == null && a.type == AnnotationType.sticky) return;
                            // Keep the opacity already set.
                            a.fill = v?.withValues(alpha: a.fill?.a ?? 1);
                          }),
                        ),
                      ),
                      if (fillRef.fill != null)
                        row(
                          tr('불투명도'),
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: fillRef.fill!.a,
                                  min: 0.1,
                                  divisions: 9,
                                  label: '${(fillRef.fill!.a * 100).round()}%',
                                  onChanged: (v) => c.editSelected((a) {
                                    if (a.fill != null) a.fill = a.fill!.withValues(alpha: v);
                                  }),
                                ),
                              ),
                              Text('${(fillRef.fill!.a * 100).round()}%', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                    ]),
                  if (textRef != null)
                    section(tr('글꼴'), [
                      row(
                        tr('글꼴'),
                        fontFamilyMenu(
                          value: textRef.fontFamily,
                          onChanged: (f) => c.editSelected((a) {
                            if (a.hasText) a.fontFamily = f == defaultFontFamily ? null : f;
                          }),
                        ),
                      ),
                      row(
                        tr('크기'),
                        Row(
                          children: [
                            fontSizeMenu(
                              value: textRef.fontSize,
                              onChanged: (s) => c.editSelected((a) {
                                if (a.hasText) a.fontSize = s;
                              }),
                            ),
                            const SizedBox(width: 12),
                            ToggleButtons(
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 30),
                              borderRadius: BorderRadius.circular(4),
                              isSelected: [textRef.bold, textRef.italic],
                              onPressed: (i) => c.editSelected((a) {
                                if (!a.hasText) return;
                                i == 0 ? a.bold = !textRef.bold : a.italic = !textRef.italic;
                              }),
                              children: [
                                Tooltip(message: tr('굵게'), child: Icon(Icons.format_bold, size: 18)),
                                Tooltip(message: tr('기울임'), child: Icon(Icons.format_italic, size: 18)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      row(
                        tr('글자색'),
                        ColorRow(
                          controller: c,
                          colors: annotationColors,
                          value: textRef.color,
                          onChanged: (v) => c.editSelected((a) {
                            if (a.hasText && v != null) a.color = v;
                          }),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('닫기')))],
        );
      },
    ),
  );
  c.endEdit();
}
