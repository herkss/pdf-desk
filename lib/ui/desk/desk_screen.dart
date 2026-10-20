import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/desk_controller.dart';
import '../../services/settings.dart';
import '../../services/storage.dart';
import '../common/dialogs.dart';
import '../common/toolbar.dart';
import 'desk_actions.dart';
import 'desk_canvas.dart';
import 'folder_tree.dart';

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
  double _treeWidth = 220;
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
  }

  @override
  void dispose() {
    desk.dispose();
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _newFolder() async {
    final name = await promptText(context, title: '새 폴더', initial: '새 폴더');
    if (name == null || name.trim().isEmpty) return;
    await Directory(uniquePath(desk.folder, sanitizeFileName(name), '')).create();
    desk.treeRevision.value++;
  }

  Future<void> _settingsDialog() async {
    final s = widget.settings;
    final label = TextEditingController(text: s.stampLabel);
    final name = TextEditingController(text: s.stampName);
    var root = s.rootPath;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('환경 설정'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('데스크 폴더 (문서 보관 위치)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text(root, style: const TextStyle(fontSize: 13))),
                    TextButton(
                      onPressed: () async {
                        final dir = await FilePicker.getDirectoryPath(dialogTitle: '데스크 폴더 선택');
                        if (dir != null) setLocal(() => root = dir);
                      },
                      child: const Text('변경…'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('날짜 도장', style: TextStyle(fontWeight: FontWeight.w600)),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: '위쪽 문구 (예: 승인, 확인)'),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '이름'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    s.stampLabel = label.text;
    s.stampName = name.text;
    final rootChanged = root != s.rootPath;
    s.rootPath = root;
    await s.save();
    if (rootChanged) {
      await desk.openFolder(root);
      setState(() => _treeKey++);
    }
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(BuildContext context) {
    final a = _actions(context);
    return {
      const SingleActivator(LogicalKeyboardKey.delete): a.delete,
      const SingleActivator(LogicalKeyboardKey.f2): a.rename,
      const SingleActivator(LogicalKeyboardKey.enter): a.open,
      const SingleActivator(LogicalKeyboardKey.f5): desk.refresh,
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): desk.selectAll,
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): a.duplicate,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => a.importFiles(),
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
                          child: Container(
                            color: const Color(0xFFF7F8FA),
                            child: FolderTree(key: ValueKey(_treeKey), desk: desk, actions: _actions),
                          ),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (d) =>
                                setState(() => _treeWidth = (_treeWidth + d.delta.dx).clamp(140, 480)),
                            child: Container(width: 5, color: const Color(0xFFE3E6EA)),
                          ),
                        ),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: desk,
                            builder: (context, _) => DeskCanvas(desk: desk, actions: _actions),
                          ),
                        ),
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
            ToolButton(icon: Icons.file_download_outlined, label: '가져오기', onPressed: () => a.importFiles()),
            ToolButton(icon: Icons.create_new_folder_outlined, label: '새 폴더', onPressed: _newFolder),
            const ToolSeparator(),
            ToolButton(icon: Icons.menu_book_outlined, label: '열기', onPressed: one ? () => a.open() : null),
            ToolButton(icon: Icons.layers_outlined, label: '묶기', onPressed: sel.length > 1 ? () => a.combine() : null),
            ToolButton(
              icon: Icons.call_split,
              label: '분할',
              onPressed: one && !sel.first.isBinder ? () => a.split() : null,
            ),
            ToolButton(
              icon: Icons.collections_bookmark_outlined,
              label: '바인더',
              onPressed: sel.isNotEmpty ? () => a.makeBinder() : null,
            ),
            ToolButton(
              icon: Icons.unarchive_outlined,
              label: '해제',
              onPressed: one && sel.first.isBinder ? () => a.unbind() : null,
            ),
            const ToolSeparator(),
            ToolButton(icon: Icons.rotate_left, label: '왼쪽 회전', onPressed: docs.isNotEmpty ? () => a.rotate(3) : null),
            ToolButton(
              icon: Icons.rotate_right,
              label: '오른쪽 회전',
              onPressed: docs.isNotEmpty ? () => a.rotate(1) : null,
            ),
            const ToolSeparator(),
            ToolButton(
              icon: Icons.picture_as_pdf_outlined,
              label: 'PDF 내보내기',
              onPressed: sel.isNotEmpty ? () => a.exportPdf() : null,
            ),
            ToolButton(icon: Icons.print_outlined, label: '인쇄', onPressed: sel.isNotEmpty ? () => a.printDocs() : null),
            ToolButton(icon: Icons.delete_outline, label: '삭제', onPressed: sel.isNotEmpty ? a.delete : null),
            const ToolSeparator(),
            PopupMenuButton<SortMode>(
              tooltip: '정렬',
              onSelected: desk.arrange,
              itemBuilder: (_) => const [
                PopupMenuItem(value: SortMode.name, child: Text('이름순')),
                PopupMenuItem(value: SortMode.modified, child: Text('수정일순')),
              ],
              child: const ToolButtonFace(icon: Icons.grid_view, label: '정렬'),
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
                  hintText: '문서 이름 검색',
                  border: const OutlineInputBorder(),
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
            IconButton(tooltip: '환경 설정', icon: const Icon(Icons.settings_outlined), onPressed: _settingsDialog),
          ],
        );
      },
    );
  }

  Widget _statusBar() => ListenableBuilder(
    listenable: desk,
    builder: (context, _) => Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFFF0F2F5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              desk.folder,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Text(
            '${desk.entries.length}개 항목'
            '${desk.selection.isEmpty ? '' : ' · ${desk.selection.length}개 선택'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.photo_size_select_large, size: 14, color: Colors.black45),
          SizedBox(
            width: 140,
            child: Slider(value: desk.thumbWidth.clamp(70, 400), min: 70, max: 400, onChanged: desk.setThumbWidth),
          ),
        ],
      ),
    ),
  );
}
