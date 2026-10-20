import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/desk_controller.dart';
import '../../services/storage.dart';
import '../common/dialogs.dart';
import 'desk_actions.dart';
import 'desk_canvas.dart';

/// Folder tree under the workspace root. Documents dragged from the desk can
/// be dropped on a folder to move them there.
class FolderTree extends StatefulWidget {
  const FolderTree({super.key, required this.desk, required this.actions});
  final DeskController desk;
  final DeskActions Function(BuildContext) actions;

  @override
  State<FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<FolderTree> {
  final _expanded = <String>{};

  DeskController get desk => widget.desk;
  String get root => desk.settings.rootPath;

  @override
  void initState() {
    super.initState();
    _expanded.add(root);
    // Expand the path to the current folder.
    var f = desk.folder;
    while (p.isWithin(root, f)) {
      f = p.dirname(f);
      _expanded.add(f);
    }
    desk.treeRevision.addListener(_changed);
  }

  @override
  void dispose() {
    desk.treeRevision.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  List<String> _children(String folder) {
    try {
      final dirs = Directory(folder)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((d) => d.path)
          .where((d) => !isHiddenName(p.basename(d)) && !isBinderPath(d))
          .toList();
      dirs.sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
      return dirs;
    } catch (_) {
      return [];
    }
  }

  List<Widget> _build(String folder, int depth) {
    final children = _children(folder);
    final expanded = _expanded.contains(folder);
    return [
      _FolderRow(
        path: folder,
        label: folder == root ? '내 데스크' : p.basename(folder),
        depth: depth,
        hasChildren: children.isNotEmpty,
        expanded: expanded,
        selected: desk.folder == folder,
        onToggle: () => setState(() => expanded ? _expanded.remove(folder) : _expanded.add(folder)),
        onOpen: () async {
          await desk.openFolder(folder);
          setState(() {});
        },
        onMenu: (pos) => _menu(folder, pos),
        onDropDocs: (paths) => widget.actions(context).moveToFolder(paths, folder),
      ),
      if (expanded)
        for (final c in children) ..._build(c, depth + 1),
    ];
  }

  Future<void> _menu(String folder, Offset pos) async {
    final isRoot = folder == root;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'new', child: Text('새 폴더')),
        if (!isRoot) const PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
        const PopupMenuItem(value: 'explorer', child: Text('탐색기에서 열기')),
        if (!isRoot)
          const PopupMenuItem(
            value: 'delete',
            child: Text('삭제', style: TextStyle(color: Colors.red)),
          ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'new':
        await newFolder(folder);
      case 'rename':
        final name = await promptText(context, title: '폴더 이름 바꾸기', initial: p.basename(folder));
        if (name == null || name.trim().isEmpty) return;
        final target = p.join(p.dirname(folder), sanitizeFileName(name));
        try {
          await Directory(folder).rename(target);
          if (desk.folder == folder || p.isWithin(folder, desk.folder)) await desk.openFolder(target);
        } catch (e) {
          if (mounted) showError(context, e);
        }
      case 'explorer':
        final cmd = Platform.isWindows ? 'explorer' : (Platform.isMacOS ? 'open' : 'xdg-open');
        await Process.run(cmd, [folder]);
      case 'delete':
        final ok = await confirm(
          context,
          title: '폴더 삭제',
          message: "'${p.basename(folder)}' 폴더와 그 안의 모든 문서를 삭제할까요?",
          okLabel: '삭제',
          destructive: true,
        );
        if (!ok) return;
        try {
          if (desk.folder == folder || p.isWithin(folder, desk.folder)) await desk.openFolder(p.dirname(folder));
          await Directory(folder).delete(recursive: true);
        } catch (e) {
          if (mounted) showError(context, e);
        }
    }
    setState(() {});
  }

  Future<void> newFolder(String parent) async {
    final name = await promptText(context, title: '새 폴더', initial: '새 폴더');
    if (name == null || name.trim().isEmpty) return;
    final path = uniquePath(parent, sanitizeFileName(name), '');
    await Directory(path).create();
    setState(() => _expanded.add(parent));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: desk,
      builder: (context, _) => ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: _build(root, 0)),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.path,
    required this.label,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
    required this.onMenu,
    required this.onDropDocs,
  });

  final String path;
  final String label;
  final int depth;
  final bool hasChildren;
  final bool expanded;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final void Function(Offset) onMenu;
  final void Function(List<String>) onDropDocs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<DeskDragData>(
      onWillAcceptWithDetails: (d) => d.data.paths.every((x) => p.dirname(x) != path),
      onAcceptWithDetails: (d) => onDropDocs(d.data.paths),
      builder: (context, candidates, _) => GestureDetector(
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: InkWell(
          onTap: onOpen,
          onDoubleTap: hasChildren ? onToggle : null,
          child: Container(
            height: 28,
            color: candidates.isNotEmpty
                ? Colors.orange.withValues(alpha: 0.3)
                : selected
                ? scheme.primaryContainer
                : null,
            padding: EdgeInsets.only(left: 4.0 + depth * 14),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: hasChildren
                      ? InkWell(
                          onTap: onToggle,
                          child: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 18),
                        )
                      : null,
                ),
                Icon(
                  depth == 0 ? Icons.desktop_windows_outlined : (selected ? Icons.folder_open : Icons.folder),
                  size: 18,
                  color: depth == 0 ? scheme.primary : const Color(0xFFF4B400),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
