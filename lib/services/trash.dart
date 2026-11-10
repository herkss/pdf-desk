import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'storage.dart';

/// A deleted document or binder waiting in the trash.
class TrashItem {
  TrashItem(this.dir, this.name, this.origin, this.deleted);

  /// Folder in the trash holding the entry and its annotations.
  final String dir;
  final String name;

  /// Where it was deleted from.
  final String origin;
  final DateTime deleted;

  String get path => p.join(dir, name);
}

/// 휴지통: deleting from the desk moves documents here (with their
/// annotations) so they can be restored. Items older than [keep] are
/// removed for good.
class Trash {
  Trash(this.root);

  /// The desk root; the trash lives in its metadata folder.
  final String root;
  static const keep = Duration(days: 30);

  String get _dir => p.join(metaDirOf(root), 'trash');

  Future<TrashItem> put(String path) async {
    final stamp = DateTime.now();
    final dir = p.join(_dir, '${stamp.microsecondsSinceEpoch}');
    await Directory(dir).create(recursive: true);
    final name = p.basename(path);
    await moveDocument(path, p.join(dir, name));
    await File(
      p.join(dir, 'info.json'),
    ).writeAsString(jsonEncode({'name': name, 'origin': path, 'deleted': stamp.toIso8601String()}));
    return TrashItem(dir, name, path, stamp);
  }

  /// Newest first; also drops items past [keep].
  Future<List<TrashItem>> list() async {
    final d = Directory(_dir);
    if (!await d.exists()) return [];
    final items = <TrashItem>[];
    await for (final e in d.list()) {
      if (e is! Directory) continue;
      try {
        final j = jsonDecode(await File(p.join(e.path, 'info.json')).readAsString()) as Map<String, dynamic>;
        final item = TrashItem(
          e.path,
          j['name'] as String,
          j['origin'] as String,
          DateTime.parse(j['deleted'] as String),
        );
        if (!await File(item.path).exists() && !await Directory(item.path).exists()) continue;
        if (DateTime.now().difference(item.deleted) > keep) {
          await purge(item);
        } else {
          items.add(item);
        }
      } catch (_) {
        // Not one of ours (or half-written): leave it.
      }
    }
    items.sort((a, b) => b.deleted.compareTo(a.deleted));
    return items;
  }

  /// Puts the item back where it was (or into the desk root if that folder
  /// is gone), under a new name if the old one is taken. Returns its path.
  Future<String> restore(TrashItem item) async {
    var folder = p.dirname(item.origin);
    if (!await Directory(folder).exists()) folder = root;
    final ext = p.extension(item.name);
    final target = uniquePath(folder, p.basenameWithoutExtension(item.name), ext);
    await moveDocument(item.path, target);
    try {
      await retryFileOp(() => Directory(item.dir).delete(recursive: true), attempts: 5);
    } on FileSystemException {
      // Only info.json is left; list() skips folders without the entry.
    }
    return target;
  }

  Future<void> purge(TrashItem item) => retryFileOp(() => Directory(item.dir).delete(recursive: true));

  Future<void> empty() async {
    final d = Directory(_dir);
    if (await d.exists()) await retryFileOp(() => d.delete(recursive: true));
  }
}
