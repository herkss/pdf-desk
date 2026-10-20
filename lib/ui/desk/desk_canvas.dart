import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/desk_controller.dart';
import 'desk_actions.dart';
import 'desk_item.dart';

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
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && _ctrl) {
            GestureBinding.instance.pointerSignalResolver.register(e, (_) {
              final w = (desk.thumbWidth * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(70.0, 400.0);
              desk.setThumbWidth(w);
            });
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFDDE3EA),
            border: _osDragOver ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null,
          ),
          child: LayoutBuilder(builder: (context, viewport) => _buildScrollable(context, viewport)),
        ),
      ),
    );
  }

  Widget _buildScrollable(BuildContext context, BoxConstraints viewport) {
    final entries = desk.visibleEntries;
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
                desk.movePathsBy(d.data.paths, delta);
                desk.endMove();
              },
              builder: (context, _, _) => SizedBox(
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
              desk.filter.isEmpty ? 'PDF나 이미지 파일을 여기로 끌어다 놓으세요' : "'${desk.filter}'에 해당하는 문서가 없습니다",
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
      items: const [
        PopupMenuItem(value: 'import', child: Text('파일 가져오기…')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'arrangeName', child: Text('이름순으로 정렬')),
        PopupMenuItem(value: 'arrangeDate', child: Text('수정일순으로 정렬')),
        PopupMenuItem(value: 'selectAll', child: Text('모두 선택')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'refresh', child: Text('새로 고침')),
        PopupMenuItem(value: 'explorer', child: Text('탐색기에서 열기')),
      ],
    );
    switch (choice) {
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
    desk.select(entry, toggle: ctrl || shift);
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
        const PopupMenuItem(value: 'open', child: Text('열기')),
        const PopupMenuDivider(),
        if (multi) const PopupMenuItem(value: 'combine', child: Text('문서 묶기')),
        if (!multi && !binder) const PopupMenuItem(value: 'split', child: Text('페이지별로 분할')),
        const PopupMenuItem(value: 'binder', child: Text('바인더 만들기')),
        if (!multi && binder) const PopupMenuItem(value: 'unbind', child: Text('바인더 해제')),
        if (!binder) ...const [
          PopupMenuItem(value: 'rotR', child: Text('오른쪽으로 회전')),
          PopupMenuItem(value: 'rotL', child: Text('왼쪽으로 회전')),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'export', child: Text('PDF로 내보내기 (주석 포함)…')),
        const PopupMenuItem(value: 'print', child: Text('인쇄…')),
        const PopupMenuDivider(),
        if (!multi) const PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
        const PopupMenuItem(value: 'duplicate', child: Text('복제')),
        if (!multi) const PopupMenuItem(value: 'reveal', child: Text('탐색기에서 보기')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('삭제', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
    switch (choice) {
      case 'open':
        await a.open(entry);
      case 'combine':
        await a.combine();
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

  /// Dropping documents onto a binder adds them; onto a document asks
  /// whether to combine or make a binder.
  Future<void> _onDropOnto(List<String> paths) async {
    final a = widget.actions(context);
    if (entry.isBinder) {
      await a.addToBinder(entry, paths);
      return;
    }
    final others = [for (final p in paths) ...desk.entries.where((e) => e.path == p)];
    final targets = [entry, ...others];
    final rect = (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(rect.dx + 40, rect.dy + 40, rect.dx + 40, rect.dy + 40),
      items: const [
        PopupMenuItem(value: 'combine', child: Text('문서 묶기')),
        PopupMenuItem(value: 'binder', child: Text('바인더 만들기')),
        PopupMenuItem(value: 'cancel', child: Text('취소')),
      ],
    );
    if (choice == 'combine') await a.combine(targets);
    if (choice == 'binder') await a.makeBinder(targets);
  }

  @override
  Widget build(BuildContext context) {
    final size = desk.itemSize;
    final selected = desk.isSelected(entry);
    final paths = [entry.path, ...desk.selection.where((s) => s != entry.path)];
    return DragTarget<DeskDragData>(
      onWillAcceptWithDetails: (d) => !d.data.paths.contains(entry.path),
      onAcceptWithDetails: (d) => _onDropOnto(d.data.paths),
      builder: (context, candidates, _) => Listener(
        onPointerDown: _onPointerDown,
        child: Draggable<DeskDragData>(
          data: DeskDragData(selected ? paths : [entry.path]),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.8,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  DeskItemCard(entry: entry, size: size, selected: true),
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
              child: DeskItemCard(entry: entry, size: size, selected: selected, highlighted: candidates.isNotEmpty),
            ),
          ),
        ),
      ),
    );
  }
}
