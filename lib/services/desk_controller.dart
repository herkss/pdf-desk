import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'settings.dart';
import 'storage.dart';
import 'thumbnails.dart';

class DeskEntry {
  DeskEntry(this.path);
  final String path;
  String get fileName => p.basename(path);
  String get title => p.basenameWithoutExtension(path);
  bool get isBinder => isBinderPath(path);
}

enum SortMode { name, modified }

/// State of the desk (the central work area) for the current folder.
class DeskController extends ChangeNotifier {
  DeskController(this.settings);

  final Settings settings;
  String folder = '';
  List<DeskEntry> entries = [];
  DeskLayout layout = DeskLayout();

  /// Selected paths in selection order (combine/binder use this order).
  final List<String> selection = [];
  String filter = '';

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _refreshDebounce;
  Timer? _saveDebounce;

  /// Folder tree changes (new/renamed/deleted subfolders).
  final treeRevision = ValueNotifier(0);

  double get thumbWidth => layout.thumbWidth;
  Size get itemSize => Size(thumbWidth, thumbWidth * 1.414 + 40);
  Size get gridStep => Size(itemSize.width + 28, itemSize.height + 20);

  List<DeskEntry> get visibleEntries {
    if (filter.isEmpty) return entries;
    final f = filter.toLowerCase();
    return entries.where((e) => e.title.toLowerCase().contains(f)).toList();
  }

  Future<void> openFolder(String path) async {
    await _flushLayout();
    folder = path;
    selection.clear();
    layout = await DeskLayout.load(folder);
    settings.lastFolder = folder;
    unawaited(settings.save());
    await _watchFolder();
    await refresh();
  }

  Future<void> _watchFolder() async {
    await _watch?.cancel();
    _watch = null;
    try {
      _watch = Directory(folder).watch().listen((e) {
        if (e.path.contains(metaDirName) || e.path.endsWith('.tmp')) return;
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
          ThumbnailService.instance.invalidate();
          refresh();
        });
      });
    } catch (_) {
      // Watching isn't available on every file system; manual refresh still works.
    }
  }

  Future<void> refresh() async {
    final dir = Directory(folder);
    if (!await dir.exists()) return;
    final found = <DeskEntry>[];
    var subfoldersChanged = false;
    await for (final e in dir.list(followLinks: false)) {
      final name = p.basename(e.path);
      if (isHiddenName(name)) continue;
      if (e is File && isPdf(name)) found.add(DeskEntry(e.path));
      if (e is Directory) {
        if (isBinderPath(name)) {
          found.add(DeskEntry(e.path));
        } else {
          subfoldersChanged = true;
        }
      }
    }
    found.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    entries = found;

    final names = {for (final e in entries) e.fileName};
    layout.positions.removeWhere((k, _) => !names.contains(k));
    selection.removeWhere((s) => !names.contains(p.basename(s)));
    for (final e in entries) {
      if (!layout.positions.containsKey(e.fileName)) {
        layout.positions[e.fileName] = _nextFreeSlot();
      }
    }
    if (subfoldersChanged) treeRevision.value++;
    _scheduleLayoutSave();
    notifyListeners();
  }

  Offset positionOf(DeskEntry e) => layout.positions[e.fileName] ?? Offset.zero;

  Rect rectOf(DeskEntry e) => positionOf(e) & itemSize;

  Offset _nextFreeSlot({Offset? near}) {
    final step = gridStep;
    final occupied = layout.positions.values.map((o) => o & itemSize).toList();
    final cols = math.max(1, (1100 / step.width).floor());
    final startRow = near == null ? 0 : (near.dy / step.height).floor();
    final startCol = near == null ? 0 : (near.dx / step.width).floor();
    for (var i = 0; i < 10000; i++) {
      final row = startRow + (startCol + i) ~/ cols;
      final col = (startCol + i) % cols;
      final pos = Offset(16 + col * step.width, 16 + row * step.height);
      final r = (pos & itemSize).deflate(4);
      if (!occupied.any((o) => o.overlaps(r))) return pos;
    }
    return const Offset(16, 16);
  }

  /// Positions newly created [paths] near [at] (or in the next free slots).
  void place(List<String> paths, {Offset? at}) {
    var cursor = at;
    for (final path in paths) {
      final name = p.basename(path);
      final pos = cursor == null ? _nextFreeSlot() : _nextFreeSlot(near: cursor);
      layout.positions[name] = pos;
      cursor = pos;
    }
    _scheduleLayoutSave();
  }

  // --- selection ---------------------------------------------------------

  bool isSelected(DeskEntry e) => selection.contains(e.path);

  List<DeskEntry> get selectedEntries => [for (final s in selection) ...entries.where((e) => e.path == s)];

  void select(DeskEntry e, {bool toggle = false}) {
    if (toggle) {
      selection.contains(e.path) ? selection.remove(e.path) : selection.add(e.path);
    } else if (!selection.contains(e.path)) {
      selection
        ..clear()
        ..add(e.path);
    }
    notifyListeners();
  }

  void selectOnly(DeskEntry e) {
    selection
      ..clear()
      ..add(e.path);
    notifyListeners();
  }

  void selectInRect(Rect r, {Set<String> keep = const {}}) {
    selection
      ..clear()
      ..addAll(keep);
    for (final e in visibleEntries) {
      if (rectOf(e).overlaps(r) && !selection.contains(e.path)) selection.add(e.path);
    }
    notifyListeners();
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(visibleEntries.map((e) => e.path));
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    notifyListeners();
  }

  // --- layout ----------------------------------------------------------------

  void movePathsBy(List<String> paths, Offset delta) {
    for (final s in paths) {
      final name = p.basename(s);
      final pos = layout.positions[name];
      if (pos == null) continue;
      layout.positions[name] = Offset(math.max(0, pos.dx + delta.dx), math.max(0, pos.dy + delta.dy));
    }
    notifyListeners();
  }

  void endMove() => _scheduleLayoutSave();

  void setThumbWidth(double w) {
    final ratio = w / layout.thumbWidth;
    layout.thumbWidth = w;
    layout.positions.updateAll((_, v) => Offset(v.dx * ratio, v.dy * ratio));
    _scheduleLayoutSave();
    notifyListeners();
  }

  /// 정렬: lays all documents out on a grid in [mode] order.
  Future<void> arrange(SortMode mode) async {
    final list = List.of(entries);
    if (mode == SortMode.modified) {
      final stamps = {for (final e in list) e.path: (await FileStat.stat(e.path)).modified};
      list.sort((a, b) => stamps[b.path]!.compareTo(stamps[a.path]!));
    }
    final step = gridStep;
    final cols = math.max(1, (1100 / step.width).floor());
    for (var i = 0; i < list.length; i++) {
      layout.positions[list[i].fileName] = Offset(16 + (i % cols) * step.width, 16 + (i ~/ cols) * step.height);
    }
    _scheduleLayoutSave();
    notifyListeners();
  }

  void renamePosition(String oldPath, String newPath) {
    final pos = layout.positions.remove(p.basename(oldPath));
    if (pos != null) layout.positions[p.basename(newPath)] = pos;
  }

  void _scheduleLayoutSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _flushLayout);
  }

  Future<void> _flushLayout() async {
    _saveDebounce?.cancel();
    if (folder.isEmpty) return;
    try {
      await layout.save(folder);
    } catch (e) {
      debugPrint('layout save failed: $e');
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _refreshDebounce?.cancel();
    _flushLayout();
    super.dispose();
  }
}
