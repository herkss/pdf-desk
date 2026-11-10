import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../models/annotation.dart';
import '../../services/settings.dart';
import '../../services/stamps.dart';
import '../common/annotation_painter.dart';
import '../common/app_theme.dart';
import '../common/dialogs.dart';
import '../common/popover.dart';
import 'annotation_style.dart';
import 'tool_style.dart';
import 'viewer_controller.dart';

String toolLabel(Tool t) => switch (t) {
  Tool.select => tr('선택'),
  Tool.clip => tr('영역 복사'),
  Tool.pen => tr('펜'),
  Tool.marker => tr('형광펜'),
  Tool.line => tr('직선'),
  Tool.arrow => tr('화살표'),
  Tool.rect => tr('사각형'),
  Tool.ellipse => tr('타원'),
  Tool.text => tr('텍스트'),
  Tool.sticky => tr('부전'),
  Tool.stamp => tr('도장'),
  Tool.eraser => tr('지우개'),
};

/// Right-click on a viewer tool: its own settings, changed in place. The
/// tool is picked too, so the next stroke uses them.
Future<void> showToolSettings(BuildContext context, ViewerController c, Settings settings, Tool t, Rect anchor) {
  if (t != Tool.select) c.setTool(t);
  return showPopover(
    context,
    anchor: anchor,
    width: t == Tool.stamp ? 380 : 360,
    title: tr('{tool} 설정', {'tool': toolLabel(t)}),
    builder: (context, setState) {
      final st = toolStyles[t]!;
      void edit(void Function(ToolStyle) f) {
        c.editToolStyle(t, f);
        setState(() {});
      }

      Widget colors({bool sticky = false}) => ColorRow(
        controller: c,
        colors: sticky ? stickyColors : annotationColors.take(8).toList(),
        value: st.color,
        onChanged: (v) {
          if (v != null) edit((s) => s.color = v);
        },
      );
      Widget widths(List<double> options, {bool none = false}) => popChoices<double>(
        {
          for (final w in [if (none) 0.0, ...options]) w: w == 0 ? tr('없음') : '${w}pt'.replaceAll('.0pt', 'pt'),
        },
        st.width,
        (w) => edit((s) => s.width = w),
      );
      Widget lineStyles() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final ls in LineStyle.values)
            ChoiceChip(
              avatar: LineStyleSample(ls, width: 24),
              label: Text(lineStyleLabels[ls]!),
              showCheckmark: false,
              selected: st.lineStyle == ls,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => edit((s) => s.lineStyle = ls),
            ),
        ],
      );
      Widget font() => Column(
        children: [
          popRow(
            context,
            tr('글꼴'),
            Row(
              children: [
                Flexible(
                  child: fontFamilyMenu(value: st.fontFamily, onChanged: (f) => edit((s) => s.fontFamily = f)),
                ),
                const SizedBox(width: 8),
                fontSizeMenu(value: st.fontSize, onChanged: (v) => edit((s) => s.fontSize = v)),
              ],
            ),
          ),
          popRow(
            context,
            tr('모양'),
            Row(
              children: [
                FilterChip(
                  label: Text(tr('굵게')),
                  selected: st.bold,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => edit((s) => s.bold = v),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(tr('기울임')),
                  selected: st.italic,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => edit((s) => s.italic = v),
                ),
              ],
            ),
          ),
        ],
      );
      Widget background() => Column(
        children: [
          popRow(
            context,
            tr('배경색'),
            ColorRow(
              controller: c,
              colors: fillColors.take(5).toList(),
              allowNone: true,
              value: st.fill?.withValues(alpha: 1),
              onChanged: (v) => edit((s) => s.fill = v?.withValues(alpha: s.fill?.a ?? 1)),
            ),
          ),
          if (st.fill != null)
            popRow(
              context,
              tr('불투명도'),
              Slider(
                value: st.fill!.a,
                min: 0.1,
                divisions: 9,
                label: '${(st.fill!.a * 100).round()}%',
                onChanged: (v) => edit((s) => s.fill = s.fill!.withValues(alpha: v)),
              ),
            ),
        ],
      );
      Widget arrows() => popRow(
        context,
        tr('화살표'),
        Row(
          children: [
            FilterChip(
              label: Text(tr('시작점')),
              selected: st.heads & 1 != 0,
              visualDensity: VisualDensity.compact,
              onSelected: (on) => edit((s) => s.heads = (s.heads & 2) | (on ? 1 : 0)),
            ),
            const SizedBox(width: 6),
            FilterChip(
              label: Text(tr('끝점')),
              selected: st.heads & 2 != 0,
              visualDensity: VisualDensity.compact,
              onSelected: (on) => edit((s) => s.heads = (s.heads & 1) | (on ? 2 : 0)),
            ),
          ],
        ),
      );

      final body = switch (t) {
        Tool.select => <Widget>[
          Text(tr('선택한 주석은 우클릭 → 속성에서 바꿀 수 있습니다.'), style: TextStyle(fontSize: 12.5, color: context.ink2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(label: Text(tr('이 페이지의 주석 모두 선택')), onPressed: () => c.selectAllOnPage(c.currentPage)),
              ActionChip(label: Text(tr('선택 해제')), onPressed: () => c.select(null)),
              if (ViewerController.hasClipboard)
                ActionChip(label: Text(tr('붙여넣기')), onPressed: () => c.paste(c.currentPage)),
            ],
          ),
        ],
        Tool.clip => [
          popRow(
            context,
            tr('해상도'),
            popChoices<double>(
              {150: '150 dpi', 200: '200 dpi', 300: '300 dpi', 600: '600 dpi'},
              st.clipDpi,
              (v) => edit((s) => s.clipDpi = v),
            ),
          ),
          popSwitch(context, tr('영역 안의 주석도 함께 복사'), st.clipAnnotations, (v) => edit((s) => s.clipAnnotations = v)),
          popSwitch(context, tr('글자를 Windows 클립보드에도 복사'), st.clipText, (v) => edit((s) => s.clipText = v)),
        ],
        Tool.pen => [
          popRow(context, tr('색상'), colors()),
          popRow(context, tr('굵기'), widths(const [0.5, 1, 2, 3, 4, 6, 8, 12])),
          popRow(context, tr('선 종류'), lineStyles()),
        ],
        Tool.marker => [
          popRow(context, tr('색상'), colors()),
          popRow(context, tr('굵기'), widths(const [6, 8, 12, 16, 20, 28])),
        ],
        Tool.line || Tool.arrow => [
          popRow(context, tr('색상'), colors()),
          popRow(context, tr('굵기'), widths(const [0.5, 1, 2, 3, 4, 6, 8])),
          popRow(context, tr('선 종류'), lineStyles()),
          arrows(),
        ],
        Tool.rect || Tool.ellipse => [
          popRow(context, tr('선 색'), colors()),
          popRow(context, tr('굵기'), widths(const [0.5, 1, 2, 3, 4, 6, 8], none: true)),
          popRow(context, tr('선 종류'), lineStyles()),
          background(),
        ],
        Tool.text => [font(), popRow(context, tr('글자색'), colors()), background()],
        Tool.sticky => [popRow(context, tr('부전 색'), colors(sticky: true)), font()],
        Tool.eraser => [
          popSwitch(context, tr('펜·형광펜만 지우기 (도형·글자·도장은 남김)'), st.eraseInkOnly, (v) => edit((s) => s.eraseInkOnly = v)),
        ],
        Tool.stamp => [_StampList(settings: settings, onChanged: () => setState(() {}))],
      };
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body);
    },
  );
}

/// The registered stamps: pick the one to use, add date or image stamps,
/// change their size and text, delete them.
class _StampList extends StatefulWidget {
  const _StampList({required this.settings, required this.onChanged});
  final Settings settings;
  final VoidCallback onChanged;

  @override
  State<_StampList> createState() => _StampListState();
}

class _StampListState extends State<_StampList> {
  Settings get s => widget.settings;

  void _changed() {
    s.save();
    setState(() {});
    widget.onChanged();
  }

  Future<void> _addImage() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: tr('도장 이미지 선택'),
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
    );
    final path = picked.firstOrNull?.path;
    if (path == null || !mounted) return;
    final stamp = imageStamp(await File(path).readAsBytes(), name: p.basenameWithoutExtension(path));
    if (stamp == null) {
      if (mounted) showInfo(context, tr('이미지를 읽을 수 없습니다: {name}', {'name': p.basename(path)}));
      return;
    }
    s.currentStamp; // makes sure the default date stamp exists
    s.stamps.add(stamp);
    s.activeStamp = stamp.id;
    _changed();
  }

  void _addDate() {
    s.currentStamp;
    final stamp = StampDef.date(tr('확인'), s.stampName);
    s.stamps.add(stamp);
    s.activeStamp = stamp.id;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final current = s.currentStamp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('찍을 도장을 고르세요'), style: TextStyle(fontSize: 12.5, color: context.ink2)),
        const SizedBox(height: 6),
        for (final st in s.stamps)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              s.activeStamp = st.id;
              _changed();
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: st.id == current.id ? Theme.of(context).colorScheme.primary : context.palette.separator,
                  width: st.id == current.id ? 2 : 0.5,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(width: 52, height: 52, child: _StampPreview(st)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      st.isImage ? (st.name.isEmpty ? tr('이미지 도장') : st.name) : '${st.label} · ${st.name}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (s.stamps.length > 1)
                    IconButton(
                      tooltip: tr('삭제'),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        s.stamps.removeWhere((x) => x.id == st.id);
                        _changed();
                      },
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: _addImage,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(tr('이미지 도장 등록…')),
            ),
            OutlinedButton.icon(
              onPressed: _addDate,
              icon: const Icon(Icons.approval_outlined, size: 18),
              label: Text(tr('날짜 도장 추가')),
            ),
          ],
        ),
        const Divider(height: 20),
        popRow(
          context,
          tr('크기'),
          Slider(
            value: current.size.clamp(24, 200),
            min: 24,
            max: 200,
            divisions: 22,
            label: '${current.size.round()}pt',
            onChanged: (v) {
              current.size = v;
              _changed();
            },
          ),
        ),
        if (current.isImage)
          popRow(
            context,
            tr('이름'),
            TextFormField(
              key: ValueKey('name${current.id}'),
              initialValue: current.name,
              onChanged: (v) {
                current.name = v;
                s.save();
              },
            ),
          )
        else ...[
          popRow(
            context,
            tr('위쪽 문구'),
            TextFormField(
              key: ValueKey('label${current.id}'),
              initialValue: current.label,
              onChanged: (v) {
                current.label = v;
                _changed();
              },
            ),
          ),
          popRow(
            context,
            tr('이름'),
            TextFormField(
              key: ValueKey('who${current.id}'),
              initialValue: current.name,
              onChanged: (v) {
                current.name = v;
                _changed();
              },
            ),
          ),
          popRow(
            context,
            tr('색상'),
            Wrap(
              spacing: 4,
              children: [
                for (final col in const [0xFFD32F2F, 0xFF1E88E5, 0xFF212121, 0xFF43A047])
                  InkWell(
                    onTap: () {
                      current.color = col;
                      _changed();
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(col),
                        shape: BoxShape.circle,
                        border: Border.all(color: current.color == col ? context.ink : Colors.transparent, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StampPreview extends StatelessWidget {
  const _StampPreview(this.stamp);
  final StampDef stamp;

  @override
  Widget build(BuildContext context) {
    if (stamp.isImage && stamp.image != null) {
      return Image.memory(base64Decode(stamp.image!), fit: BoxFit.contain, gaplessPlayback: true);
    }
    return CustomPaint(painter: _DateStampPainter(stamp));
  }
}

class _DateStampPainter extends CustomPainter {
  _DateStampPainter(this.stamp);
  final StampDef stamp;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: d, height: d);
    paintStamp(canvas, r, '${stamp.label}\n26.01.01\n${stamp.name}', Color(stamp.color));
  }

  @override
  bool shouldRepaint(_DateStampPainter old) => true;
}
