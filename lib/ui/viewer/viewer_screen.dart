import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../services/pdf_ops.dart' as ops;
import '../../services/settings.dart';
import '../../services/storage.dart';
import '../common/dialogs.dart';
import '../common/toolbar.dart';
import '../../models/annotation.dart';
import 'annotation_style.dart';
import 'page_sidebar.dart';
import 'pages_view.dart';
import 'viewer_controller.dart';
import '../common/ios_theme.dart';
import '../../l10n/l10n.dart';

/// Viewer/editor for a document, or for each document of a binder (tabs).
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.path, required this.settings});
  final String path;
  final Settings settings;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  List<String> _docs = [];
  int _docIndex = 0;
  ViewerController? _c;
  final _pagesKey = GlobalKey<PagesViewState>();
  final _focus = FocusNode();
  final _searchFocus = FocusNode();
  final _search = TextEditingController();
  bool _sidebar = true;

  bool get isBinder => isBinderPath(widget.path);
  String get title => p.basenameWithoutExtension(widget.path);

  /// Where extracted pages go: the desk folder containing the document/binder.
  String get deskFolder => p.dirname(widget.path);

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs({int select = 0}) async {
    _docs = isBinder ? await binderDocuments(widget.path) : [widget.path];
    if (_docs.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await _openDoc(select.clamp(0, _docs.length - 1));
  }

  Future<void> _openDoc(int index) async {
    final old = _c;
    final c = ViewerController(_docs[index]);
    await c.load();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() {
      _docIndex = index;
      _c = c;
      _search.clear();
    });
    old?.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pagesKey.currentState?.fitWidth());
  }

  @override
  void dispose() {
    _c?.dispose();
    _focus.dispose();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  PagesViewState? get _pages => _pagesKey.currentState;

  Set<int> get _targetPages {
    final c = _c!;
    return c.selectedPages.isEmpty ? {c.currentPage} : Set.of(c.selectedPages);
  }

  // --- page operations -------------------------------------------------------

  Future<void> _rotatePages(int turns) async {
    final c = _c!;
    final pages = _targetPages;
    await runBusy(context, tr('페이지 회전 중…'), () async {
      await c.pageOperation(() => ops.rotatePages(c.path, pages, turns));
      return true;
    });
    setState(() {});
  }

  Future<void> _deletePages() async {
    final c = _c!;
    final pages = _targetPages;
    if (pages.length >= c.pages.length) {
      showInfo(context, tr('모든 페이지를 삭제할 수는 없습니다. 데스크에서 문서를 삭제하세요.'));
      return;
    }
    final ok = await confirm(
      context,
      title: tr('페이지 삭제'),
      message: tr('{n}개 페이지를 삭제할까요? 이 작업은 되돌릴 수 없습니다.', {'n': pages.length}),
      okLabel: tr('삭제'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    c.selectedPages.clear();
    await runBusy(context, tr('페이지 삭제 중…'), () async {
      await c.pageOperation(() => ops.deletePages(c.path, pages));
      return true;
    });
    setState(() {});
  }

  Future<void> _extractPages() async {
    final c = _c!;
    final pages = _targetPages.toList()..sort();
    final out = await runBusy(context, tr('페이지 추출 중…'), () async {
      await c.save();
      return ops.extractPages(c.path, pages, deskFolder);
    });
    if (out != null && mounted) {
      showInfo(context, tr("데스크에 '{out}' 문서를 만들었습니다.", {'out': p.basenameWithoutExtension(out)}));
    }
  }

  Future<void> _insertFile({required bool after}) async {
    final c = _c!;
    final picked = await FilePicker.pickFile(
      dialogTitle: tr('삽입할 파일 선택'),
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp', 'tif', 'tiff'],
    );
    final src = picked?.path;
    if (src == null || !mounted) return;
    final at = after
        ? (_targetPages.reduce((a, b) => a > b ? a : b) + 1)
        : _targetPages.reduce((a, b) => a < b ? a : b);
    await runBusy(context, tr('페이지 삽입 중…'), () async {
      final tmpDir = await Directory.systemTemp.createTemp('pdfdesk');
      try {
        final imported = await ops.importFile(src, tmpDir.path);
        if (imported == null) throw StateError(tr('지원하지 않는 파일입니다.'));
        await c.pageOperation(() => ops.insertDocument(c.path, imported, at));
      } finally {
        await tmpDir.delete(recursive: true);
      }
      return true;
    });
    setState(() {});
  }

  Future<void> _reorder(List<int> order) async {
    final c = _c!;
    c.selectedPages.clear();
    await runBusy(context, tr('페이지 순서 변경 중…'), () async {
      await c.pageOperation(() => ops.reorderPages(c.path, order));
      return true;
    });
    setState(() {});
  }

  Future<void> _pageMenu(Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'rotR', child: Text(tr('오른쪽으로 회전'))),
        PopupMenuItem(value: 'rotL', child: Text(tr('왼쪽으로 회전'))),
        PopupMenuItem(value: 'rot180', child: Text(tr('180° 회전'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'extract', child: Text(tr('페이지 추출 (새 문서)'))),
        PopupMenuItem(value: 'insertBefore', child: Text(tr('앞에 파일 삽입…'))),
        PopupMenuItem(value: 'insertAfter', child: Text(tr('뒤에 파일 삽입…'))),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(tr('페이지 삭제'), style: TextStyle(color: Colors.red)),
        ),
      ],
    );
    switch (choice) {
      case 'rotR':
        await _rotatePages(1);
      case 'rotL':
        await _rotatePages(3);
      case 'rot180':
        await _rotatePages(2);
      case 'extract':
        await _extractPages();
      case 'insertBefore':
        await _insertFile(after: false);
      case 'insertAfter':
        await _insertFile(after: true);
      case 'delete':
        await _deletePages();
    }
  }

  // --- binder tabs -----------------------------------------------------------

  Future<void> _tabMenu(int index, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (index > 0) PopupMenuItem(value: 'left', child: Text(tr('왼쪽으로 이동'))),
        if (index < _docs.length - 1) PopupMenuItem(value: 'right', child: Text(tr('오른쪽으로 이동'))),
        PopupMenuItem(value: 'rename', child: Text(tr('이름 바꾸기'))),
        PopupMenuItem(value: 'remove', child: Text(tr('바인더에서 꺼내기'))),
      ],
    );
    await _c?.save();
    if (!mounted) return;
    switch (choice) {
      case 'left':
      case 'right':
        final to = choice == 'left' ? index - 1 : index + 1;
        final d = _docs.removeAt(index);
        _docs.insert(to, d);
        await saveBinderOrder(widget.path, _docs);
        setState(() => _docIndex = _docIndex == index ? to : (_docIndex == to ? index : _docIndex));
      case 'rename':
        final name = await promptText(context, title: tr('이름 바꾸기'), initial: p.basenameWithoutExtension(_docs[index]));
        if (name == null || name.trim().isEmpty || !mounted) return;
        final target = p.join(widget.path, '${sanitizeFileName(name)}.pdf');
        if (File(target).existsSync()) return;
        _c?.dispose();
        _c = null;
        await moveDocument(_docs[index], target);
        _docs[index] = target;
        await saveBinderOrder(widget.path, _docs);
        await _openDoc(_docIndex);
      case 'remove':
        if (_docIndex == index) {
          _c?.dispose();
          setState(() => _c = null);
        }
        await ops.removeFromBinder(_docs[index]);
        if (!mounted) return;
        await _loadDocs(select: index > 0 ? index - 1 : 0);
    }
  }

  Future<void> _addToBinder() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: tr('바인더에 추가'),
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp', 'tif', 'tiff'],
    );
    final files = picked.map((f) => f.path).whereType<String>().toList();
    if (files.isEmpty || !mounted) return;
    await runBusy(context, tr('바인더에 추가하는 중…'), () async {
      for (final f in files) {
        final out = await ops.importFile(f, widget.path);
        if (out != null) _docs.add(out);
      }
      await saveBinderOrder(widget.path, _docs);
      return true;
    });
    setState(() {});
  }

  // --- export ----------------------------------------------------------------

  Future<void> _export() async {
    final c = _c!;
    await c.save();
    if (!mounted) return;
    final bytes = await runBusy(context, tr('PDF로 내보내는 중…'), () => ops.exportFlattened([c.path]));
    if (bytes == null) return;
    final saved = await FilePicker.saveFile(
      dialogTitle: tr('PDF로 내보내기 (주석 포함)'),
      fileName: '${p.basenameWithoutExtension(c.path)}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (saved != null && mounted) showInfo(context, tr('내보냈습니다.'));
  }

  Future<void> _print() async {
    final c = _c!;
    await c.save();
    if (!mounted) return;
    final bytes = await runBusy(context, tr('인쇄 준비 중…'), () => ops.exportFlattened([c.path]));
    if (bytes == null) return;
    await Printing.layoutPdf(name: p.basenameWithoutExtension(c.path), onLayout: (_) async => bytes);
  }

  Future<void> _runSearch(String q) async {
    final c = _c!;
    await c.search(q);
    final hit = c.searchHits.isEmpty ? null : c.searchHits[c.searchIndex];
    if (hit != null) _pages?.goToPage(hit.page, reveal: hit.rects.firstOrNull);
    if (q.isNotEmpty && c.searchHits.isEmpty && mounted) showInfo(context, tr("'{q}'을(를) 찾을 수 없습니다.", {'q': q}));
  }

  void _nextHit(int delta) {
    final hit = _c?.nextHit(delta);
    if (hit != null) _pages?.goToPage(hit.page, reveal: hit.rects.firstOrNull);
  }

  // --- UI --------------------------------------------------------------------

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final c = _c!;
    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): c.redo,
      const SingleActivator(LogicalKeyboardKey.delete): c.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): c.copySelected,
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => c.paste(c.currentPage),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => c.selectAllOnPage(c.currentPage),
      const SingleActivator(LogicalKeyboardKey.escape): () => c.setTool(Tool.select),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): c.save,
      const SingleActivator(LogicalKeyboardKey.keyP, control: true): _print,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () => c.setZoom(c.zoom * 1.2),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () => c.setZoom(c.zoom / 1.2),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => _pages?.fitWidth(),
      const SingleActivator(LogicalKeyboardKey.pageDown): () => _pages?.goToPage(c.currentPage + 1),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _pages?.goToPage(c.currentPage - 1),
      const SingleActivator(LogicalKeyboardKey.home, control: true): () => _pages?.goToPage(0),
      const SingleActivator(LogicalKeyboardKey.end, control: true): () => _pages?.goToPage(c.pages.length - 1),
      const SingleActivator(LogicalKeyboardKey.f3): () => _nextHit(1),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): () => _nextHit(-1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) => Column(
                children: [
                  _toolbar(c),
                  _propertyBar(c),
                  const Divider(height: 1),
                  if (isBinder) _binderTabs(),
                  Expanded(child: _body(c)),
                  _statusBar(c),
                ],
              ),
            ),
    );
  }

  Widget _body(ViewerController c) {
    if (c.loadError != null) {
      return Center(
        child: Text(tr('문서를 열 수 없습니다.\n{loadError}', {'loadError': c.loadError}), textAlign: TextAlign.center),
      );
    }
    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Listener(
          onPointerDown: (_) => _focus.requestFocus(),
          child: Row(
            children: [
              if (_sidebar)
                SizedBox(
                  width: 150,
                  child: PageSidebar(
                    controller: c,
                    onGoTo: (i) => _pages?.goToPage(i),
                    onReorder: _reorder,
                    onMenu: _pageMenu,
                  ),
                ),
              if (_sidebar) const VerticalDivider(width: 1),
              Expanded(
                child: PagesView(key: _pagesKey, controller: c, settings: widget.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(ViewerController c) {
    Widget tool(Tool t, IconData icon, String label, String tip) =>
        ToolButton(icon: icon, label: label, tooltip: tip, active: c.tool == t, onPressed: () => c.setTool(t));
    return ToolbarRow(
      items: [
        ToolButton(icon: Icons.arrow_back, label: tr('데스크'), onPressed: () => Navigator.pop(context)),
        ToolButton(
          icon: Icons.view_sidebar_outlined,
          label: tr('페이지'),
          active: _sidebar,
          onPressed: () => setState(() => _sidebar = !_sidebar),
        ),
        const ToolSeparator(),
        tool(Tool.select, Icons.near_me_outlined, tr('선택'), tr('선택/이동 (Esc)')),
        tool(Tool.pen, Icons.edit_outlined, tr('펜'), tr('자유선')),
        tool(Tool.marker, Icons.brush_outlined, tr('형광펜'), tr('형광펜')),
        tool(Tool.line, Icons.horizontal_rule, tr('직선'), tr('Shift: 45° 단위')),
        tool(Tool.arrow, Icons.arrow_right_alt, tr('화살표'), tr('Shift: 45° 단위')),
        tool(Tool.rect, Icons.crop_square, tr('사각형'), tr('Shift: 정사각형')),
        tool(Tool.ellipse, Icons.circle_outlined, tr('타원'), tr('Shift: 정원')),
        tool(Tool.text, Icons.title, tr('텍스트'), tr('클릭한 위치에 텍스트')),
        tool(Tool.sticky, Icons.sticky_note_2_outlined, tr('부전'), tr('스티커 메모')),
        tool(Tool.stamp, Icons.approval_outlined, tr('도장'), tr('날짜 도장')),
        tool(Tool.eraser, Icons.auto_fix_normal_outlined, tr('지우개'), tr('주석 지우기')),
        const ToolSeparator(),
        ToolButton(icon: Icons.undo, label: tr('실행 취소'), onPressed: c.canUndo ? c.undo : null),
        ToolButton(icon: Icons.redo, label: tr('다시 실행'), onPressed: c.canRedo ? c.redo : null),
        ToolButton(
          icon: c.showAnnotations ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          label: tr('주석 표시'),
          active: c.showAnnotations,
          onPressed: c.toggleAnnotations,
        ),
        const ToolSeparator(),
        ToolButton(icon: Icons.rotate_left, label: tr('왼쪽 회전'), onPressed: () => _rotatePages(3)),
        ToolButton(icon: Icons.rotate_right, label: tr('오른쪽 회전'), onPressed: () => _rotatePages(1)),
        const ToolSeparator(),
        ToolButton(icon: Icons.picture_as_pdf_outlined, label: tr('PDF 내보내기'), onPressed: _export),
        ToolButton(icon: Icons.print_outlined, label: tr('인쇄'), onPressed: _print),
      ],
      trailing: [
        const SizedBox(width: 8),
        SizedBox(
          width: 190,
          height: 34,
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            style: const TextStyle(fontSize: 13),
            onSubmitted: (q) => q == c.searchQuery && c.searchHits.isNotEmpty ? _nextHit(1) : _runSearch(q),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: c.searching
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : const Icon(Icons.search, size: 18),
              hintText: tr('문서 내 검색'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (c.searchHits.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('${c.searchIndex + 1}/${c.searchHits.length}', style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: tr('이전 (Shift+F3)'),
            onPressed: () => _nextHit(-1),
          ),
          IconButton(icon: const Icon(Icons.keyboard_arrow_down), tooltip: tr('다음 (F3)'), onPressed: () => _nextHit(1)),
        ],
      ],
    );
  }

  Widget _propertyBar(ViewerController c) {
    final sticky = c.tool == Tool.sticky;
    final showStroke = const {
      Tool.pen,
      Tool.marker,
      Tool.line,
      Tool.arrow,
      Tool.rect,
      Tool.ellipse,
      Tool.select,
    }.contains(c.tool);
    final showDash = showStroke && c.tool != Tool.marker;
    final showFill = const {Tool.rect, Tool.ellipse, Tool.text, Tool.select}.contains(c.tool);
    final showFont = const {Tool.text, Tool.sticky, Tool.select}.contains(c.tool);
    const label = TextStyle(fontSize: 12, color: Colors.black54);
    const gap = SizedBox(width: 16);
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: IosColors.bar,
        border: Border(bottom: iosHairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(sticky ? tr('부전 색') : tr('색상'), style: label),
                  const SizedBox(width: 4),
                  ColorRow(
                    controller: c,
                    colors: sticky ? stickyColors : annotationColors.take(8).toList(),
                    value: c.activeColor,
                    onChanged: (v) {
                      if (v != null) c.setColor(v);
                    },
                  ),
                  if (showStroke) ...[
                    gap,
                    Text(tr('굵기'), style: label),
                    const SizedBox(width: 4),
                    for (final w in const [1.0, 2.0, 4.0, 8.0])
                      InkWell(
                        onTap: () => c.setStrokeWidth(w),
                        child: Container(
                          width: 30,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.strokeWidth == w ? Theme.of(context).colorScheme.primaryContainer : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Container(width: 18, height: w.clamp(1, 6), color: Colors.black87),
                        ),
                      ),
                  ],
                  if (showDash) ...[
                    gap,
                    Text(tr('선 종류'), style: label),
                    const SizedBox(width: 4),
                    DropdownButton<LineStyle>(
                      value: c.lineStyle,
                      isDense: true,
                      underline: const SizedBox(),
                      items: [
                        for (final s in LineStyle.values)
                          DropdownMenuItem(
                            value: s,
                            child: Row(
                              children: [
                                LineStyleSample(s),
                                const SizedBox(width: 6),
                                Text(lineStyleLabels[s]!, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => c.setLineStyle(v!),
                    ),
                  ],
                  if (showFill) ...[
                    gap,
                    Text(tr('배경'), style: label),
                    const SizedBox(width: 4),
                    ColorRow(
                      controller: c,
                      colors: fillColors.take(5).toList(),
                      allowNone: true,
                      value: c.fill,
                      onChanged: c.setFill,
                    ),
                  ],
                  if (showFont) ...[
                    gap,
                    Text(tr('글꼴'), style: label),
                    const SizedBox(width: 4),
                    fontFamilyMenu(
                      value: c.fontFamily,
                      onChanged: (f) => c.setFont(family: f),
                    ),
                    const SizedBox(width: 8),
                    fontSizeMenu(value: c.fontSize, onChanged: c.setFontSize),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: tr('굵게'),
                      isSelected: c.bold,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.format_bold),
                      onPressed: () => c.setFont(bold: !c.bold),
                    ),
                    IconButton(
                      tooltip: tr('기울임'),
                      isSelected: c.italic,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.format_italic),
                      onPressed: () => c.setFont(italic: !c.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (c.selectedIds.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => showAnnotationStyleDialog(context, c),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(tr('속성…')),
            ),
            TextButton.icon(
              onPressed: c.deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(tr('삭제 ({n})', {'n': c.selectedIds.length})),
            ),
          ],
        ],
      ),
    );
  }

  Widget _binderTabs() => Container(
    height: 36,
    color: const Color(0xFFE8EAF6),
    child: Row(
      children: [
        const SizedBox(width: 8),
        const Icon(Icons.collections_bookmark, size: 18, color: IosColors.blue),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _docs.length,
            itemBuilder: (context, i) {
              final active = i == _docIndex;
              return GestureDetector(
                onSecondaryTapUp: (d) => _tabMenu(i, d.globalPosition),
                child: InkWell(
                  onTap: active
                      ? null
                      : () async {
                          await _c?.save();
                          await _openDoc(i);
                        },
                  child: Container(
                    margin: const EdgeInsets.only(top: 5, right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : const Color(0xFFC5CAE9),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                    child: Text(
                      p.basenameWithoutExtension(_docs[i]),
                      style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w600 : null),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        IconButton(tooltip: tr('바인더에 문서 추가'), icon: const Icon(Icons.add, size: 20), onPressed: _addToBinder),
      ],
    ),
  );

  Widget _statusBar(ViewerController c) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    color: const Color(0xFFF0F2F5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            isBinder ? '$title › ${p.basenameWithoutExtension(c.path)}' : title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        IconButton(
          iconSize: 18,
          tooltip: tr('이전 페이지'),
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _pages?.goToPage(c.currentPage - 1),
        ),
        Text('${c.pages.isEmpty ? 0 : c.currentPage + 1} / ${c.pages.length}', style: const TextStyle(fontSize: 12)),
        IconButton(
          iconSize: 18,
          tooltip: tr('다음 페이지'),
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _pages?.goToPage(c.currentPage + 1),
        ),
        const SizedBox(width: 16),
        IconButton(
          iconSize: 18,
          tooltip: tr('축소'),
          icon: const Icon(Icons.zoom_out),
          onPressed: () => c.setZoom(c.zoom / 1.2),
        ),
        SizedBox(
          width: 48,
          child: Text('${(c.zoom * 100).round()}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ),
        IconButton(
          iconSize: 18,
          tooltip: tr('확대'),
          icon: const Icon(Icons.zoom_in),
          onPressed: () => c.setZoom(c.zoom * 1.2),
        ),
        TextButton(
          onPressed: () => _pages?.fitWidth(),
          child: Text(tr('폭 맞춤'), style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => _pages?.fitPage(),
          child: Text(tr('전체 페이지'), style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}
