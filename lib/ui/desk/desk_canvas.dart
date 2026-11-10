import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/desk_controller.dart';
import 'desk_actions.dart';
import 'desk_item.dart';
import '../common/ios_theme.dart';
import '../../l10n/l10n.dart';

/// Payload of an internal drag: the grabbed item first, then the rest of the
/// selection.
class DeskDragData {
  DeskDragData(this.paths);
  final List<String> paths;
}

class DeskCanvas extends StatefulWidget {
  const DeskCanvas({super.key, required this.desk, required this.actions});
  final DeskController desk;
  final DeskActions Function(BuildContext) actions;

  @override
  State<DeskCanvas> createState() => _DeskCanvasState();
}

class _DeskCanvasState extends State<DeskCanvas> {
  final _contentKey = GlobalKey();
  final _vScroll = ScrollController();
  final _hScroll = ScrollController();
  Offset? _bandStart;
  Rect? _band;
  Set<String> _bandKeep = {};
  bool _osDragOver = false;
  bool _panning = false;

  DeskController get desk => widget.desk;

  bool get _ctrl => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  @override
  void dispose() {
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  Offset _toContent(Offset global) {
    final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
    return box.globalToLocal(global);
  }

  /// Scales the desk by [factor] around [at] (desk coordinates), keeping the
  /// spot under the mouse in place.
  void _zoomAt(Offset at, double factor) {
    final old = desk.thumbWidth;
    final w = (old * factor).clamp(DeskController.minThumbWidth, DeskController.maxThumbWidth);
    if (w == old) return;
    final ratio = w / old;
    final shift = at * (ratio - 1);
    desk.setThumbWidth(w);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final (c, d) in [(_hScroll, shift.dx), (_vScroll, shift.dy)]) {
        if (!c.hasClients) continue;
        c.jumpTo((c.offset + d).clamp(0.0, c.position.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _osDragOver = true),
      onDragExited: (_) => setState(() => _osDragOver = false),
      onDragDone: (d) {
        setState(() => _osDragOver = false);
        final at = _toContent(d.globalPosition);
        widget.actions(context).importFiles([for (final f in d.files) f.path], at);
      },
      child: Listener(
        // Middle-button drag pans the desk, like sliding paper around.
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) setState(() => _panning = true);
        },
        onPointerMove: (e) {
          if (!_panning) return;
          for (final (c, d) in [(_hScroll, e.delta.dx), (_vScroll, e.delta.dy)]) {
            if (!c.hasClients) continue;
            c.jumpTo((c.offset - d).clamp(0.0, c.position.maxScrollExtent));
          }
        },
        onPointerUp: (_) {
          if (_panning) setState(() => _panning = false);
        },
        onPointerCancel: (_) {
          if (_panning) setState(() => _panning = false);
        },
        child: Container(
          decoration: BoxDecoration(
            color: IosColors.desk,
            border: _osDragOver ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null,
          ),
          child: MouseRegion(
            cursor: _panning ? SystemMouseCursors.grabbing : MouseCursor.defer,
            child: LayoutBuilder(builder: (context, viewport) => _buildScrollable(context, viewport)),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollable(BuildContext context, BoxConstraints viewport) {
    final entries = desk.stackedEntries;
    var w = viewport.maxWidth, h = viewport.maxHeight;
    for (final e in entries) {
      final r = desk.rectOf(e);
      w = math.max(w, r.right + 40);
      h = math.max(h, r.bottom + 40);
    }
    return Scrollbar(
      controller: _vScroll,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        notificationPredicate: (n) => n.depth == 1,
        child: SingleChildScrollView(
          controller: _vScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: DragTarget<DeskDragData>(
              onAcceptWithDetails: (d) {
                final grabbed = desk.entries.where((e) => e.path == d.data.paths.first).firstOrNull;
                if (grabbed == null) return;
                final delta = _toContent(d.offset) - desk.positionOf(grabbed);
                // Ctrl + drag leaves the originals and lays down copies.
                if (_ctrl) {
                  widget.actions(context).copyDragged(d.data.paths, delta);
                  return;
                }
                desk.movePathsBy(d.data.paths, delta);
                desk.bringToFront(d.data.paths.reversed.toList());
                desk.endMove();
              },
              // Ctrl + wheel zooms the desk. The listener sits inside the
              // scroll views so it gets the wheel before they scroll.
              builder: (context, _, _) => Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent && _ctrl && e.scrollDelta.dy != 0) {
                    GestureBinding.instance.pointerSignalResolver.register(
                      e,
                      (_) => _zoomAt(e.localPosition, math.pow(0.9, e.scrollDelta.dy / 100).toDouble()),
                    );
                  }
                },
                child: SizedBox(
                  key: _contentKey,
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _background(context)),
                      for (final e in entries)
                        Positioned(
                          left: desk.positionOf(e).dx,
                          top: desk.positionOf(e).dy,
                          child: _DeskItem(key: ValueKey(e.path), entry: e, desk: desk, actions: widget.actions),
                        ),
                      if (_band == null) ?_selectionBar(context, entries),
                      if (_band != null)
                        Positioned.fromRect(
                          rect: _band!,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                border: Border.all(color: Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ),
                        ),
                      if (entries.isEmpty) _emptyHint(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Quick actions floating just above a multi-selection (e.g. right after
  /// band-selecting sheets): stack them, spread them, or bind them.
  Widget? _selectionBar(BuildContext context, List<DeskEntry> entries) {
    final sel = entries.where(desk.isSelected).toList();
    if (sel.length < 2) return null;
    final bounds = sel.map(desk.sheetRectOf).reduce((a, b) => a.expandToInclude(b));
    const barH = 38.0;
    final top = bounds.top >= barH + 6 ? bounds.top - barH - 6 : bounds.bottom + 6;
    final a = widget.actions(context);
    Widget button(IconData icon, String label, String tip, VoidCallback onPressed) => Tooltip(
      message: tip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      ),
    );
    return Positioned(
      left: bounds.left,
      top: top,
      height: barH,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  tr('{n}개 선택', {'n': sel.length}),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              button(Icons.layers_outlined, tr('겹치기'), tr('선택한 순서대로 하나의 문서로 합칩니다'), a.stackSelection),
              button(Icons.view_carousel_outlined, tr('펼치기'), tr('각 문서를 낱장으로 펼칩니다'), () => a.spread()),
              button(Icons.collections_bookmark_outlined, tr('바인더'), tr('바인더로 묶습니다'), () => a.makeBinder()),
              IconButton(
                tooltip: tr('선택 해제'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: desk.clearSelection,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download_outlined, size: 56, color: Colors.black.withValues(alpha: 0.25)),
            const SizedBox(height: 8),
            Text(
              desk.filter.isEmpty
                  ? tr('PDF나 이미지 파일을 여기로 끌어다 놓으세요')
                  : tr("'{filter}'에 해당하는 문서가 없습니다", {'filter': desk.filter}),
              style: TextStyle(color: Colors.black.withValues(alpha: 0.45), fontSize: 15),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _background(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      if (!_ctrl && !_shift) desk.clearSelection();
    },
    onSecondaryTapUp: (d) => _backgroundMenu(context, d.globalPosition, d.localPosition),
    onPanStart: (d) {
      _bandStart = d.localPosition;
      _bandKeep = (_ctrl || _shift) ? desk.selection.toSet() : {};
      setState(() => _band = Rect.fromPoints(_bandStart!, _bandStart!));
    },
    onPanUpdate: (d) {
      if (_bandStart == null) return;
      setState(() => _band = Rect.fromPoints(_bandStart!, d.localPosition));
      desk.selectInRect(_band!, keep: _bandKeep);
    },
    onPanEnd: (_) => setState(() {
      _band = null;
      _bandStart = null;
    }),
  );

  Future<void> _backgroundMenu(BuildContext context, Offset global, Offset local) async {
    final a = widget.actions(context);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        PopupMenuItem(value: 'new', child: Text(tr('새 문서 작성…'))),
        PopupMenuItem(value: 'import', child: Text(tr('파일 가져오기…'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'arrangeName', child: Text(tr('이름순으로 정렬'))),
        PopupMenuItem(value: 'arrangeDate', child: Text(tr('수정일순으로 정렬'))),
        PopupMenuItem(value: 'selectAll', child: Text(tr('모두 선택'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'refresh', child: Text(tr('새로 고침'))),
        PopupMenuItem(value: 'explorer', child: Text(tr('탐색기에서 열기'))),
      ],
    );
    switch (choice) {
      case 'new':
        await a.newDocument(local);
      case 'import':
        await a.importFiles(null, local);
      case 'arrangeName':
        await desk.arrange(SortMode.name);
      case 'arrangeDate':
        await desk.arrange(SortMode.modified);
      case 'selectAll':
        desk.selectAll();
      case 'refresh':
        await desk.refresh();
      case 'explorer':
        desk.clearSelection();
        await a.revealInExplorer();
    }
  }
}

class _DeskItem extends StatefulWidget {
  const _DeskItem({super.key, required this.entry, required this.desk, required this.actions});
  final DeskEntry entry;
  final DeskController desk;
  final DeskActions Function(BuildContext) actions;

  @override
  State<_DeskItem> createState() => _DeskItemState();
}

class _DeskItemState extends State<_DeskItem> {
  DateTime _lastDown = DateTime(0);
  bool _pendingDeselect = false;

  void _onPointerUp(PointerUpEvent e) {
    if (!_pendingDeselect) return;
    _pendingDeselect = false;
    desk.select(entry, toggle: true);
  }

  DeskEntry get entry => widget.entry;
  DeskController get desk => widget.desk;

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons == kSecondaryMouseButton) {
      if (!desk.isSelected(entry)) desk.selectOnly(entry);
      _contextMenu(e.position);
      return;
    }
    if (e.buttons != kPrimaryMouseButton) return;
    final now = DateTime.now();
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    // Ctrl/Shift-clicking a selected sheet deselects it on release, unless it
    // is dragged: Ctrl + drag copies the whole selection.
    _pendingDeselect = (ctrl || shift) && desk.isSelected(entry);
    if (!_pendingDeselect) desk.select(entry, toggle: ctrl || shift);
    // Clicking a sheet lifts it (and the rest of the selection) to the top.
    if (desk.isSelected(entry)) desk.bringToFront([...desk.selection.where((s) => s != entry.path), entry.path]);
    if (now.difference(_lastDown) < const Duration(milliseconds: 400) && !ctrl && !shift) {
      _lastDown = DateTime(0);
      widget.actions(context).open(entry);
      return;
    }
    _lastDown = now;
  }

  Future<void> _contextMenu(Offset global) async {
    final a = widget.actions(context);
    final multi = desk.selection.length > 1;
    final binder = entry.isBinder;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        PopupMenuItem(value: 'open', child: Text(tr('열기'))),
        const PopupMenuDivider(),
        if (multi) PopupMenuItem(value: 'stack', child: Text(tr('겹치기 (첫 문서 뒤에 붙이기)'))),
        if (multi) PopupMenuItem(value: 'combine', child: Text(tr('새 문서로 묶기…'))),
        PopupMenuItem(
          value: 'spread',
          child: Text(multi ? tr('모두 낱장으로 펼치기') : (binder ? tr('풀어서 펼치기') : tr('낱장으로 펼치기'))),
        ),
        if (!multi && !binder) PopupMenuItem(value: 'split', child: Text(tr('페이지별로 분할 (원본 유지)…'))),
        PopupMenuItem(value: 'binder', child: Text(tr('바인더 만들기'))),
        if (!multi && binder) PopupMenuItem(value: 'unbind', child: Text(tr('바인더 해제'))),
        if (!binder) ...[
          PopupMenuItem(value: 'rotR', child: Text(tr('오른쪽으로 회전'))),
          PopupMenuItem(value: 'rotL', child: Text(tr('왼쪽으로 회전'))),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(value: 'export', child: Text(tr('PDF로 내보내기 (주석 포함)…'))),
        PopupMenuItem(value: 'print', child: Text(tr('인쇄…'))),
        const PopupMenuDivider(),
        if (!multi) PopupMenuItem(value: 'rename', child: Text(tr('이름 바꾸기'))),
        PopupMenuItem(value: 'duplicate', child: Text(tr('복제'))),
        if (!multi) PopupMenuItem(value: 'reveal', child: Text(tr('탐색기에서 보기'))),
        PopupMenuItem(
          value: 'delete',
          child: Text(tr('삭제'), style: TextStyle(color: Colors.red)),
        ),
      ],
    );
    switch (choice) {
      case 'open':
        await a.open(entry);
      case 'stack':
        await a.stackSelection();
      case 'combine':
        await a.combine();
      case 'spread':
        await (multi ? a.spread() : a.spread(entry));
      case 'split':
        await a.split(entry);
      case 'binder':
        await a.makeBinder();
      case 'unbind':
        await a.unbind(entry);
      case 'rotR':
        await a.rotate(1);
      case 'rotL':
        await a.rotate(3);
      case 'export':
        await a.exportPdf();
      case 'print':
        await a.printDocs();
      case 'rename':
        await a.rename(entry);
      case 'duplicate':
        await a.duplicate();
      case 'reveal':
        await a.revealInExplorer(entry);
      case 'delete':
        await a.delete();
    }
  }

  /// Dropping documents onto a document stacks them on it right away (겹치기),
  /// so sheets can be gathered one after another; onto a binder adds them.
  /// Holding Shift just lays them on top without combining; Ctrl lays copies
  /// there instead.
  Future<void> _onDropOnto(DragTargetDetails<DeskDragData> d) async {
    final paths = d.data.paths;
    final keys = HardwareKeyboard.instance;
    final copy = keys.isControlPressed || keys.isMetaPressed;
    if (copy || keys.isShiftPressed) {
      final grabbed = desk.entries.where((e) => e.path == paths.first).firstOrNull;
      if (grabbed == null) return;
      final origin = (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero);
      final target = desk.positionOf(entry) + (d.offset - origin);
      if (copy) {
        await widget.actions(context).copyDragged(paths, target - desk.positionOf(grabbed));
        return;
      }
      desk.movePathsBy(paths, target - desk.positionOf(grabbed));
      desk.bringToFront(paths.reversed.toList());
      desk.endMove();
      return;
    }
    await widget.actions(context).stackOnto(entry, paths);
  }

  @override
  Widget build(BuildContext context) {
    final size = desk.itemSize;
    final selected = desk.isSelected(entry);
    final paths = [entry.path, ...desk.selection.where((s) => s != entry.path)];
    return DragTarget<DeskDragData>(
      onWillAcceptWithDetails: (d) => !d.data.paths.contains(entry.path),
      onAcceptWithDetails: _onDropOnto,
      builder: (context, candidates, _) => Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: Draggable<DeskDragData>(
          onDragStarted: () => _pendingDeselect = false,
          data: DeskDragData(selected ? paths : [entry.path]),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.8,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DeskItemCard(entry: entry, size: size, selected: true),
                  Positioned(
                    left: -6,
                    top: -6,
                    child: _ModifierBuilder(
                      builder: (copy, _) => copy
                          ? const CircleAvatar(
                              radius: 12,
                              backgroundColor: Color(0xFF2E7D32),
                              child: Icon(Icons.add, size: 16, color: Colors.white),
                            )
                          : const SizedBox(),
                    ),
                  ),
                  if (desk.selection.length > 1)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Text(
                          '${desk.selection.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: DeskItemCard(entry: entry, size: size, selected: selected),
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Tooltip(
              message: entry.fileName,
              waitDuration: const Duration(milliseconds: 900),
              child: candidates.isEmpty
                  ? DeskItemCard(entry: entry, size: size, selected: selected)
                  : _ModifierBuilder(
                      builder: (copy, shift) => DeskItemCard(
                        entry: entry,
                        size: size,
                        selected: selected,
                        highlighted: true,
                        dropLabel: copy
                            ? tr('여기에 복사')
                            : shift
                            ? tr('위에 놓기')
                            : entry.isBinder
                            ? tr('바인더에 넣기')
                            : tr('겹치기'),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rebuilds when Ctrl (copy) or Shift is pressed or released, so drag
/// feedback can show what a drop will do.
class _ModifierBuilder extends StatefulWidget {
  const _ModifierBuilder({required this.builder});
  final Widget Function(bool copy, bool shift) builder;

  @override
  State<_ModifierBuilder> createState() => _ModifierBuilderState();
}

class _ModifierBuilderState extends State<_ModifierBuilder> {
  bool _onKey(KeyEvent _) {
    if (mounted) setState(() {});
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = HardwareKeyboard.instance;
    return widget.builder(k.isControlPressed || k.isMetaPressed, k.isShiftPressed);
  }
}
