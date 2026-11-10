import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../services/desk_controller.dart';
import '../../services/storage.dart';
import '../common/dialogs.dart';
import 'desk_actions.dart';
import 'desk_canvas.dart';
import '../common/app_theme.dart';

/// Files dragged out of the disk explorer.
class DiskDragData {
  DiskDragData(this.paths);
  final List<String> paths;
}

/// 내 PC: the real drives and folders, like Explorer's navigation pane.
///
/// - Drag a PDF or image onto the desk to move it there (Ctrl: copy).
/// - Drag desk documents onto a folder to copy them out as PDFs.
/// - Drag a file onto another folder to move it (Ctrl: copy).
/// - Right-click a folder → 데스크로 열기 to work on that folder directly.
class DiskTree extends StatefulWidget {
  const DiskTree({super.key, required this.desk, required this.actions});
  final DeskController desk;
  final DeskActions Function(BuildContext) actions;

  @override
  State<DiskTree> createState() => _DiskTreeState();
}

/// Top-level places: the user's common folders, then every drive.
List<(String label, String path, IconData icon)> diskRoots() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final places = <(String, String, IconData)>[
    if (home.isNotEmpty) ...[
      (tr('바탕 화면'), p.join(home, 'Desktop'), Icons.desktop_mac_outlined),
      (tr('문서'), p.join(home, 'Documents'), Icons.description_outlined),
      (tr('다운로드'), p.join(home, 'Downloads'), Icons.download_outlined),
    ],
  ].where((e) => Directory(e.$2).existsSync()).toList();
  if (Platform.isWindows) {
    for (var c = 'C'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
      final drive = '${String.fromCharCode(c)}:\\';
      if (Directory(drive).existsSync()) {
        places.add((tr('로컬 디스크 ({d})', {'d': drive.substring(0, 2)}), drive, Icons.storage));
      }
    }
  } else {
    if (home.isNotEmpty) places.add((tr('홈'), home, Icons.home_outlined));
    places.add(('/', '/', Icons.storage));
  }
  return places;
}

/// System folders Explorer hides too.
bool _skip(String name) =>
    name.startsWith('.') ||
    name.startsWith(r'$') ||
    const {'System Volume Information', 'Recovery', 'PerfLogs', 'Config.Msi', 'node_modules'}.contains(name) ||
    name.toLowerCase().endsWith('.sys');

class _DiskTreeState extends State<DiskTree> {
  final _expanded = <String>{};
  final _cache = <String, (List<String> dirs, List<String> files)>{};
  String? _selectedFile;

  DeskController get desk => widget.desk;

  (List<String>, List<String>) _list(String folder) => _cache[folder] ??= () {
    try {
      final dirs = <String>[], files = <String>[];
      for (final e in Directory(folder).listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (_skip(name)) continue;
        if (e is Directory && !isBinderPath(name)) {
          dirs.add(e.path);
        } else if (e is File && isImportable(e.path)) {
          files.add(e.path);
        }
      }
      int byName(String a, String b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
      return (dirs..sort(byName), files..sort(byName));
    } catch (_) {
      return (<String>[], <String>[]);
    }
  }();

  void _refresh([String? folder]) => setState(() => folder == null ? _cache.clear() : _cache.remove(folder));

  bool get _ctrl => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  Future<void> _moveFiles(List<String> files, String folder) async {
    final copy = _ctrl;
    try {
      for (final f in files) {
        if (p.dirname(f) == folder) continue;
        final target = uniquePath(folder, p.basenameWithoutExtension(f), p.extension(f));
        copy ? await copyDocument(f, target) : await moveDocument(f, target);
        _cache.remove(p.dirname(f));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    _refresh(folder);
  }

  Future<void> _folderMenu(String folder, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'desk', child: Text(tr('데스크로 열기'))),
        PopupMenuItem(value: 'explorer', child: Text(tr('탐색기에서 열기'))),
        PopupMenuItem(value: 'refresh', child: Text(tr('새로 고침'))),
      ],
    );
    switch (choice) {
      case 'desk':
        await desk.openFolder(folder);
      case 'explorer':
        await Process.run(Platform.isWindows ? 'explorer' : (Platform.isMacOS ? 'open' : 'xdg-open'), [folder]);
      case 'refresh':
        _refresh(folder);
    }
  }

  Future<void> _fileMenu(String file, Offset pos) async {
    final a = widget.actions(context);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'move', child: Text(tr('데스크로 옮기기'))),
        PopupMenuItem(value: 'copy', child: Text(tr('데스크로 복사'))),
        PopupMenuItem(value: 'explorer', child: Text(tr('탐색기에서 보기'))),
      ],
    );
    switch (choice) {
      case 'move' || 'copy':
        await a.receiveDiskFiles([file], null, copy: choice == 'copy');
        _refresh(p.dirname(file));
      case 'explorer':
        if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', file]);
        } else {
          await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [p.dirname(file)]);
        }
    }
  }

  List<Widget> _folder(String path, String label, IconData icon, int depth) {
    final open = _expanded.contains(path);
    final (dirs, files) = open ? _list(path) : (const <String>[], const <String>[]);
    return [
      _DiskRow(
        depth: depth,
        icon: icon,
        label: label,
        expandable: true,
        expanded: open,
        current: desk.folder == path,
        onTap: () => setState(() => open ? _expanded.remove(path) : _expanded.add(path)),
        onSecondary: (pos) => _folderMenu(path, pos),
        onDeskDrop: (paths) => widget.actions(context).copyToDiskFolder(paths, path).then((_) => _refresh(path)),
        onFileDrop: (paths) => _moveFiles(paths, path),
        tooltip: path,
      ),
      if (open) ...[
        for (final d in dirs) ..._folder(d, p.basename(d), Icons.folder, depth + 1),
        for (final f in files) _file(f, depth + 1),
      ],
    ];
  }

  Widget _file(String path, int depth) {
    final row = _DiskRow(
      depth: depth,
      icon: isPdf(path) ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
      iconColor: isPdf(path) ? const Color(0xFFE53935) : const Color(0xFF43A047),
      label: p.basename(path),
      selected: _selectedFile == path,
      onTap: () => setState(() => _selectedFile = path),
      onDoubleTap: () async {
        await widget.actions(context).receiveDiskFiles([path], null, copy: true);
        _refresh(p.dirname(path));
      },
      onSecondary: (pos) {
        setState(() => _selectedFile = path);
        _fileMenu(path, pos);
      },
      tooltip: path,
    );
    return Draggable<DiskDragData>(
      data: DiskDragData([path]),
      onDragEnd: (_) => _refresh(p.dirname(path)),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPdf(path) ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 16),
              const SizedBox(width: 6),
              Text(p.basename(path), style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: desk,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [for (final (label, path, icon) in diskRoots()) ..._folder(path, label, icon, 0)],
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({
    required this.depth,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.onSecondary,
    required this.tooltip,
    this.iconColor,
    this.expandable = false,
    this.expanded = false,
    this.current = false,
    this.selected = false,
    this.onDoubleTap,
    this.onDeskDrop,
    this.onFileDrop,
  });

  final int depth;
  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool expandable, expanded, current, selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset) onSecondary;
  final void Function(List<String>)? onDeskDrop;
  final void Function(List<String>)? onFileDrop;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(bool hot) => GestureDetector(
      onSecondaryTapUp: (d) => onSecondary(d.globalPosition),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          height: 26,
          color: hot
              ? scheme.primary.withValues(alpha: 0.18)
              : current || selected
              ? scheme.primaryContainer
              : null,
          padding: EdgeInsets.only(left: 4.0 + depth * 14),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: expandable ? Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 16) : null,
              ),
              Icon(icon, size: 17, color: iconColor ?? (expandable ? context.palette.folder : null)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: current ? FontWeight.w600 : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget tip(Widget w) => Tooltip(message: tooltip, waitDuration: const Duration(seconds: 1), child: w);
    if (onDeskDrop == null && onFileDrop == null) return tip(row(false));
    // A folder takes desk documents (copied out) and disk files (moved).
    return DragTarget<DeskDragData>(
      onAcceptWithDetails: (d) => onDeskDrop?.call(d.data.paths),
      builder: (context, desks, _) => DragTarget<DiskDragData>(
        onWillAcceptWithDetails: (d) => onFileDrop != null,
        onAcceptWithDetails: (d) => onFileDrop!(d.data.paths),
        builder: (context, files, _) => tip(row(desks.isNotEmpty || files.isNotEmpty)),
      ),
    );
  }
}
