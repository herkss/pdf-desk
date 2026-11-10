import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/desk_controller.dart';
import '../../services/print_inbox.dart';
import '../../services/settings.dart';
import '../../services/storage.dart';
import '../../services/virtual_printer.dart';
import '../common/dialogs.dart';
import '../common/toolbar.dart';
import 'desk_actions.dart';
import 'desk_canvas.dart';
import 'disk_tree.dart';
import 'folder_tree.dart';
import 'preview_pane.dart';
import '../common/app_theme.dart';
import '../common/language_menu.dart';
import '../../l10n/l10n.dart';

class DeskScreen extends StatefulWidget {
  const DeskScreen({super.key, required this.settings});
  final Settings settings;

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> {
  late final desk = DeskController(widget.settings);
  final _focus = FocusNode();
  final _search = TextEditingController();
  late final PrintInbox _inbox;
  double _treeWidth = 240;

  /// Share of the sidebar height given to the desk folders (the rest is 내 PC).
  double _treeSplit = 0.45;
  bool _diskOpen = true;
  double _previewWidth = 380;
  final _preview = GlobalKey<PreviewPaneState>();
  int _treeKey = 0;

  DeskActions _actions(BuildContext context) => DeskActions(context, desk);

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    final start =
        s.lastFolder.isNotEmpty &&
            Directory(s.lastFolder).existsSync() &&
            (s.lastFolder == s.rootPath || p.isWithin(s.rootPath, s.lastFolder))
        ? s.lastFolder
        : s.rootPath;
    desk.openFolder(start);
    _inbox = PrintInbox(
      s.inboxPath,
      deskFolder: () => desk.folder,
      onReceived: (paths) async {
        if (mounted) await _actions(context).receivePrinted(paths);
      },
    )..start();
    _offerPrinter();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerLeaveCloud());
  }

  /// The desk folder is inside OneDrive: offer to move it to a local folder,
  /// since syncing holds files open and makes merging fail.
  Future<void> _offerLeaveCloud() async {
    final s = widget.settings;
    if (!Settings.isCloudSynced(s.rootPath) || !mounted) return;
    final target = await Settings.defaultRootPath();
    if (Settings.isCloudSynced(target) || p.equals(target, s.rootPath) || !mounted) return;
    final ok = await confirm(
      context,
      title: tr('데스크 폴더 옮기기'),
      message: tr(
        '데스크 폴더가 OneDrive 안에 있습니다:\n{from}\n\nOneDrive가 동기화하는 동안 파일을 잡고 있어서 겹치기·저장이 "사용 중" 오류로 실패할 수 있습니다. 문서를 모두 아래 폴더로 옮길까요?\n{to}',
        {'from': s.rootPath, 'to': target},
      ),
      okLabel: tr('옮기기'),
    );
    if (!ok || !mounted) return;
    await desk.stopWatching();
    if (!mounted) return;
    final moved = await runBusy(context, tr('이동하는 중…'), () => moveDeskRoot(s.rootPath, target));
    if (moved == null || !mounted) return;
    s
      ..rootPath = moved
      ..lastFolder = moved;
    await s.save();
    await desk.openFolder(moved);
    setState(() => _treeKey++);
    if (mounted) showInfo(context, tr('데스크 폴더를 옮겼습니다: {path}', {'path': moved}));
  }

  /// Once, on Windows: offer the PDF Desk printer so printing from any
  /// program puts the document on the desk.
  Future<void> _offerPrinter() async {
    final s = widget.settings;
    if (!VirtualPrinter.supported || s.printerPrompted || await VirtualPrinter.isInstalled()) return;
    s.printerPrompted = true;
    unawaited(s.save());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 20),
        content: Text(tr("'PDF Desk' 프린터를 설치하면 어떤 프로그램에서 인쇄하든 데스크에 바로 놓입니다.")),
        action: SnackBarAction(label: tr('설치'), onPressed: () => installDeskPrinter(context, s)),
      ),
    );
  }

  @override
  void dispose() {
    _inbox.stop();
    desk.dispose();
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _newFolder() async {
    final name = await promptText(context, title: tr('새 폴더'), initial: tr('새 폴더'));
    if (name == null || name.trim().isEmpty) return;
    await Directory(uniquePath(desk.folder, sanitizeFileName(name), '')).create();
    desk.treeRevision.value++;
  }

  Future<void> _settingsDialog() async {
    final s = widget.settings;
    final label = TextEditingController(text: s.stampLabel);
    final name = TextEditingController(text: s.stampName);
    var root = s.rootPath;
    var spreadPrinted = s.spreadPrinted;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(tr('환경 설정')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('데스크 폴더 (문서 보관 위치)'), style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text(root, style: const TextStyle(fontSize: 13))),
                    TextButton(
                      onPressed: () async {
                        final dir = await FilePicker.getDirectoryPath(dialogTitle: tr('데스크 폴더 선택'));
                        if (dir != null) setLocal(() => root = dir);
                      },
                      child: Text(tr('변경…')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(tr('날짜 도장'), style: TextStyle(fontWeight: FontWeight.w600)),
                TextField(
                  controller: label,
                  decoration: InputDecoration(labelText: tr('위쪽 문구 (예: 승인, 확인)')),
                ),
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('이름')),
                ),
                const SizedBox(height: 16),
                Text(tr('PDF Desk 프린터'), style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  tr("다른 프로그램에서 'PDF Desk' 프린터로 인쇄하면 문서가 이 데스크에 바로 놓입니다."),
                  style: TextStyle(fontSize: 12.5, color: context.ink2),
                ),
                _PrinterSetup(settings: s),
                RadioGroup<bool>(
                  groupValue: spreadPrinted,
                  onChanged: (v) => setLocal(() => spreadPrinted = v ?? false),
                  child: Column(
                    children: [
                      RadioListTile(dense: true, value: false, title: Text(tr('인쇄물을 한 문서로 놓기'))),
                      RadioListTile(dense: true, value: true, title: Text(tr('인쇄물을 낱장으로 펼쳐 놓기'))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('취소'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('저장'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    s.stampLabel = label.text;
    s.stampName = name.text;
    s.spreadPrinted = spreadPrinted;
    final rootChanged = root != s.rootPath;
    s.rootPath = root;
    await s.save();
    if (rootChanged) {
      await desk.openFolder(root);
      setState(() => _treeKey++);
    }
  }

  void _togglePreview() {
    setState(() => widget.settings.showPreview = !widget.settings.showPreview);
    widget.settings.save();
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(BuildContext context) {
    final a = _actions(context);
    void prev() => _preview.currentState?.previous();
    void next() => _preview.currentState?.next();
    return {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): prev,
      const SingleActivator(LogicalKeyboardKey.pageUp): prev,
      const SingleActivator(LogicalKeyboardKey.arrowRight): next,
      const SingleActivator(LogicalKeyboardKey.pageDown): next,
      const SingleActivator(LogicalKeyboardKey.delete): a.delete,
      const SingleActivator(LogicalKeyboardKey.f2): a.rename,
      const SingleActivator(LogicalKeyboardKey.enter): a.open,
      const SingleActivator(LogicalKeyboardKey.f5): desk.refresh,
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): desk.selectAll,
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): a.duplicate,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => a.importFiles(),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => a.newDocument(),
      const SingleActivator(LogicalKeyboardKey.keyP, control: true): a.printDocs,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
    };
  }

  final _searchFocus = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            _menuBar(context),
            _toolbar(context),
            const Divider(height: 1),
            Expanded(
              // Shortcuts only apply inside the work area, so typing in the
              // search box isn't intercepted.
              child: CallbackShortcuts(
                bindings: _shortcuts(context),
                child: Focus(
                  focusNode: _focus,
                  autofocus: true,
                  child: Listener(
                    onPointerDown: (_) => _focus.requestFocus(),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _treeWidth,
                          child: Container(color: context.palette.sidebar, child: _sidebar()),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (d) =>
                                setState(() => _treeWidth = (_treeWidth + d.delta.dx).clamp(140, 480)),
                            child: Container(
                              width: 5,
                              decoration: BoxDecoration(
                                color: context.palette.sidebar,
                                border: Border(right: context.hairline),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: desk,
                            builder: (context, _) => DeskCanvas(desk: desk, actions: _actions),
                          ),
                        ),
                        if (widget.settings.showPreview) ...[
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              onHorizontalDragUpdate: (d) =>
                                  setState(() => _previewWidth = (_previewWidth - d.delta.dx).clamp(240, 900)),
                              child: Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  color: context.palette.sidebar,
                                  border: Border(right: context.hairline),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: _previewWidth,
                            child: ListenableBuilder(
                              listenable: desk,
                              builder: (context, _) => PreviewPane(
                                key: _preview,
                                entry: desk.selectedEntries.lastOrNull,
                                onOpen: (e) => _actions(context).open(e),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _statusBar(),
          ],
        ),
      ),
    );
  }

  /// Classic Windows-style menu bar; every command is also on the toolbar or
  /// a context menu.
  Widget _menuBar(BuildContext context) {
    final a = _actions(context);
    MenuItemButton item(String label, VoidCallback? onPressed, {MenuSerializableShortcut? shortcut}) =>
        MenuItemButton(onPressed: onPressed, shortcut: shortcut, child: Text(label));
    return ListenableBuilder(
      listenable: desk,
      builder: (context, _) {
        final sel = desk.selectedEntries;
        final any = sel.isNotEmpty, one = sel.length == 1, multi = sel.length > 1;
        final docs = sel.where((e) => !e.isBinder).isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: context.palette.bar,
            border: Border(bottom: context.hairline),
          ),
          child: Row(
            children: [
              MenuBar(
                style: MenuStyle(
                  elevation: WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(context.palette.bar),
                  padding: WidgetStatePropertyAll(EdgeInsets.zero),
                ),
                children: [
                  SubmenuButton(
                    menuChildren: [
                      item(
                        tr('파일 가져오기…'),
                        () => a.importFiles(),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true),
                      ),
                      item(
                        tr('새 문서 작성…'),
                        () => a.newDocument(),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true),
                      ),
                      item(tr('새 폴더'), _newFolder),
                      const Divider(height: 1),
                      item(tr('PDF로 내보내기 (주석 포함)…'), any ? () => a.exportPdf() : null),
                      item(
                        tr('인쇄…'),
                        any ? () => a.printDocs() : null,
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyP, control: true),
                      ),
                      const Divider(height: 1),
                      if (VirtualPrinter.supported) item(tr("'PDF Desk' 프린터 설치/설정…"), _settingsDialog),
                      const Divider(height: 1),
                      item(tr('휴지통…'), () => a.openTrash()),
                      item(tr('탐색기에서 열기'), () => a.revealInExplorer()),
                      item(tr('환경 설정…'), _settingsDialog),
                    ],
                    child: Text(tr('파일')),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        tr('모두 선택'),
                        desk.selectAll,
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyA, control: true),
                      ),
                      item(
                        tr('복제'),
                        any ? a.duplicate : null,
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyD, control: true),
                      ),
                      item(
                        tr('이름 바꾸기'),
                        one ? () => a.rename() : null,
                        shortcut: const SingleActivator(LogicalKeyboardKey.f2),
                      ),
                      item(tr('삭제'), any ? a.delete : null, shortcut: const SingleActivator(LogicalKeyboardKey.delete)),
                    ],
                    child: Text(tr('편집')),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(
                        tr('열기'),
                        one ? () => a.open() : null,
                        shortcut: const SingleActivator(LogicalKeyboardKey.enter),
                      ),
                      const Divider(height: 1),
                      item(tr('겹치기'), multi ? a.stackSelection : null),
                      item(tr('낱장으로 펼치기'), any ? () => a.spread() : null),
                      item(tr('새 문서로 묶기…'), multi ? () => a.combine() : null),
                      item(tr('페이지별로 분할 (원본 유지)…'), one && !sel.first.isBinder ? () => a.split() : null),
                      const Divider(height: 1),
                      item(tr('바인더 만들기…'), any ? () => a.makeBinder() : null),
                      item(tr('바인더 해제'), one && sel.first.isBinder ? () => a.unbind() : null),
                      const Divider(height: 1),
                      item(tr('왼쪽으로 회전'), docs ? () => a.rotate(3) : null),
                      item(tr('오른쪽으로 회전'), docs ? () => a.rotate(1) : null),
                    ],
                    child: Text(tr('문서')),
                  ),
                  SubmenuButton(
                    menuChildren: [
                      item(tr('이름순으로 정렬'), () => desk.arrange(SortMode.name)),
                      item(tr('수정일순으로 정렬'), () => desk.arrange(SortMode.modified)),
                      const Divider(height: 1),
                      item(
                        tr('크게 보기'),
                        () => desk.setThumbWidth(
                          (desk.thumbWidth * 1.2).clamp(DeskController.minThumbWidth, DeskController.maxThumbWidth),
                        ),
                      ),
                      item(
                        tr('작게 보기'),
                        () => desk.setThumbWidth(
                          (desk.thumbWidth / 1.2).clamp(DeskController.minThumbWidth, DeskController.maxThumbWidth),
                        ),
                      ),
                      const Divider(height: 1),
                      CheckboxMenuButton(
                        value: widget.settings.showPreview,
                        onChanged: (_) => _togglePreview(),
                        child: Text(tr('미리보기 창')),
                      ),
                      const Divider(height: 1),
                      item(tr('새로 고침'), desk.refresh, shortcut: const SingleActivator(LogicalKeyboardKey.f5)),
                    ],
                    child: Text(tr('표시')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar(BuildContext context) {
    final a = _actions(context);
    return ListenableBuilder(
      listenable: desk,
      builder: (context, _) {
        final sel = desk.selectedEntries;
        final one = sel.length == 1;
        final docs = sel.where((e) => !e.isBinder).toList();
        return ToolbarRow(
          items: [
            ToolButton(icon: Icons.file_download_outlined, label: tr('가져오기'), onPressed: () => a.importFiles()),
            ToolButton(icon: Icons.create_new_folder_outlined, label: tr('새 폴더'), onPressed: _newFolder),
            const ToolSeparator(),
            ToolButton(icon: Icons.menu_book_outlined, label: tr('열기'), onPressed: one ? () => a.open() : null),
            ToolButton(
              icon: Icons.layers_outlined,
              label: tr('겹치기'),
              tooltip: tr('선택한 문서를 첫 문서 뒤에 겹쳐 하나로 만듭니다 (문서를 다른 문서 위에 끌어다 놓아도 됩니다)'),
              onPressed: sel.length > 1 ? a.stackSelection : null,
            ),
            ToolButton(
              icon: Icons.view_carousel_outlined,
              label: tr('펼치기'),
              tooltip: tr('문서를 한 장씩 낱장으로 데스크에 펼칩니다'),
              onPressed: sel.isNotEmpty ? () => a.spread() : null,
            ),
            ToolButton(
              icon: Icons.note_add_outlined,
              label: tr('새로 묶기'),
              tooltip: tr('선택한 문서들로 새 문서를 만듭니다'),
              onPressed: sel.length > 1 ? () => a.combine() : null,
            ),
            ToolButton(
              icon: Icons.collections_bookmark_outlined,
              label: tr('바인더'),
              onPressed: sel.isNotEmpty ? () => a.makeBinder() : null,
            ),
            ToolButton(
              icon: Icons.unarchive_outlined,
              label: tr('해제'),
              onPressed: one && sel.first.isBinder ? () => a.unbind() : null,
            ),
            const ToolSeparator(),
            ToolButton(
              icon: Icons.rotate_left,
              label: tr('왼쪽 회전'),
              onPressed: docs.isNotEmpty ? () => a.rotate(3) : null,
            ),
            ToolButton(
              icon: Icons.rotate_right,
              label: tr('오른쪽 회전'),
              onPressed: docs.isNotEmpty ? () => a.rotate(1) : null,
            ),
            const ToolSeparator(),
            ToolButton(
              icon: Icons.picture_as_pdf_outlined,
              label: tr('PDF 내보내기'),
              onPressed: sel.isNotEmpty ? () => a.exportPdf() : null,
            ),
            ToolButton(
              icon: Icons.print_outlined,
              label: tr('인쇄'),
              onPressed: sel.isNotEmpty ? () => a.printDocs() : null,
            ),
            ToolButton(icon: Icons.delete_outline, label: tr('삭제'), onPressed: sel.isNotEmpty ? a.delete : null),
            const ToolSeparator(),
            PopupMenuButton<SortMode>(
              tooltip: tr('정렬'),
              onSelected: desk.arrange,
              itemBuilder: (_) => [
                PopupMenuItem(value: SortMode.name, child: Text(tr('이름순'))),
                PopupMenuItem(value: SortMode.modified, child: Text(tr('수정일순'))),
              ],
              child: ToolButtonFace(icon: Icons.grid_view, label: tr('정렬')),
            ),
            ToolButton(
              icon: Icons.preview_outlined,
              label: tr('미리보기'),
              tooltip: tr('오른쪽에 미리보기 창을 표시합니다 (←/→로 페이지 넘기기)'),
              active: widget.settings.showPreview,
              onPressed: _togglePreview,
            ),
          ],
          trailing: [
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              height: 34,
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: (v) {
                  desk.filter = v;
                  desk.clearSelection();
                  setState(() {});
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: tr('문서 이름 검색'),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _search.clear();
                            desk.filter = '';
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: tr('환경 설정'), icon: const Icon(Icons.settings_outlined), onPressed: _settingsDialog),
            ThemeMenu(settings: widget.settings),
            LanguageMenu(settings: widget.settings),
          ],
        );
      },
    );
  }

  /// Left side: the desk's folders on top, the computer's drives below.
  Widget _sidebar() => LayoutBuilder(
    builder: (context, c) {
      Widget header(String label, IconData icon, {Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Theme.of(context).hintColor),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
      final top = _diskOpen ? (c.maxHeight * _treeSplit).clamp(80.0, c.maxHeight - 120) : c.maxHeight - 30;
      return Column(
        children: [
          SizedBox(
            height: top,
            child: FolderTree(key: ValueKey(_treeKey), desk: desk, actions: _actions),
          ),
          // Drag the 내 PC header up or down to share the height.
          GestureDetector(
            onVerticalDragUpdate: _diskOpen
                ? (d) => setState(() => _treeSplit = (_treeSplit + d.delta.dy / c.maxHeight).clamp(0.15, 0.85))
                : null,
            child: MouseRegion(
              cursor: _diskOpen ? SystemMouseCursors.resizeRow : MouseCursor.defer,
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border(top: context.hairline)),
                child: header(
                  tr('내 PC'),
                  Icons.computer,
                  trailing: Icon(_diskOpen ? Icons.expand_more : Icons.chevron_right, size: 16),
                  onTap: () => setState(() => _diskOpen = !_diskOpen),
                ),
              ),
            ),
          ),
          if (_diskOpen)
            Expanded(
              child: DiskTree(desk: desk, actions: _actions),
            ),
        ],
      );
    },
  );

  Widget _statusBar() => ListenableBuilder(
    listenable: desk,
    builder: (context, _) => Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: context.palette.bar,
      child: Row(
        children: [
          Expanded(
            child: Text(
              desk.folder,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.ink2),
            ),
          ),
          Text(
            tr('{n}개 항목', {'n': desk.entries.length}) +
                (desk.selection.isEmpty ? '' : tr(' · {n}개 선택', {'n': desk.selection.length})),
            style: TextStyle(fontSize: 12, color: context.ink2),
          ),
          const SizedBox(width: 16),
          Icon(Icons.photo_size_select_large, size: 14, color: context.ink3),
          SizedBox(
            width: 140,
            child: Slider(
              value: desk.thumbWidth.clamp(DeskController.minThumbWidth, DeskController.maxThumbWidth),
              min: DeskController.minThumbWidth,
              max: DeskController.maxThumbWidth,
              onChanged: desk.setThumbWidth,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Installs the "PDF Desk" printer and makes it the default, so whatever is
/// printed from any program lands on the desk. Returns whether it worked.
Future<bool> installDeskPrinter(BuildContext context, Settings settings) async {
  final err = await VirtualPrinter.install(printerOutputFile(settings.inboxPath));
  if (!context.mounted) return false;
  if (err != null) {
    showInfo(context, err);
    return false;
  }
  final defErr = await VirtualPrinter.setDefault();
  if (!context.mounted) return true;
  showInfo(
    context,
    defErr == null
        ? tr("'PDF Desk' 프린터를 설치하고 기본 프린터로 지정했습니다. 이제 인쇄하면 데스크에 바로 놓입니다.")
        : tr("'PDF Desk' 프린터를 설치했습니다. (기본 프린터 지정 실패: {defErr})", {'defErr': defErr}),
  );
  return true;
}

/// Install/remove buttons for the "PDF Desk" printer, with its current state.
class _PrinterSetup extends StatefulWidget {
  const _PrinterSetup({required this.settings});
  final Settings settings;

  @override
  State<_PrinterSetup> createState() => _PrinterSetupState();
}

class _PrinterSetupState extends State<_PrinterSetup> {
  bool? _installed;
  bool _isDefault = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final v = await VirtualPrinter.isInstalled();
    final d = v && await VirtualPrinter.isDefault();
    if (mounted) {
      setState(() {
        _installed = v;
        _isDefault = d;
      });
    }
  }

  Future<void> _busy(Future<void> Function() work) async {
    setState(() => _working = true);
    await work();
    if (!mounted) return;
    setState(() => _working = false);
    await _check();
  }

  Future<void> _install() => _busy(() => installDeskPrinter(context, widget.settings));

  Future<void> _uninstall() => _busy(() async {
    final err = await VirtualPrinter.uninstall(printerOutputFile(widget.settings.inboxPath));
    if (mounted) showInfo(context, err ?? tr("'PDF Desk' 프린터를 제거했습니다."));
  });

  Future<void> _makeDefault() => _busy(() async {
    final err = await VirtualPrinter.setDefault();
    if (mounted) showInfo(context, err ?? tr("'PDF Desk'를 기본 프린터로 지정했습니다."));
  });

  @override
  Widget build(BuildContext context) {
    if (!VirtualPrinter.supported) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(tr('Windows에서만 사용할 수 있습니다.'), style: TextStyle(fontSize: 12.5)),
      );
    }
    final installed = _installed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            installed == true ? Icons.check_circle : Icons.print_disabled_outlined,
            size: 18,
            color: installed == true ? Colors.green : context.ink3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              installed == null
                  ? tr('확인 중…')
                  : !installed
                  ? tr('설치되지 않음')
                  : _isDefault
                  ? tr('설치됨 · 기본 프린터')
                  : tr('설치됨'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (_working)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (installed == true) ...[
            if (!_isDefault) TextButton(onPressed: _makeDefault, child: Text(tr('기본 프린터로'))),
            TextButton(onPressed: _uninstall, child: Text(tr('제거'))),
          ] else if (installed == false)
            FilledButton.tonal(onPressed: _install, child: Text(tr('설치 (관리자 권한)'))),
        ],
      ),
    );
  }
}
