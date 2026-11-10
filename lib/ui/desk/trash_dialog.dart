import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../services/storage.dart';
import '../../services/trash.dart';
import '../common/app_theme.dart';
import '../common/dialogs.dart';

/// Lists the trash; returns the paths of restored documents.
Future<List<String>> showTrashDialog(BuildContext context, Trash trash) async {
  final restored = <String>[];
  var items = await trash.list();
  final selected = <TrashItem>{};
  if (!context.mounted) return restored;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> reload() async {
          items = await trash.list();
          selected.removeWhere((s) => !items.any((i) => i.dir == s.dir));
          setState(() {});
        }

        Future<void> run(Future<void> Function() op) async {
          try {
            await op();
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
          await reload();
        }

        final fmt = DateFormat('yyyy-MM-dd HH:mm');
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.delete_outline),
              const SizedBox(width: 8),
              Text(tr('휴지통')),
              const Spacer(),
              Text(
                tr('{n}개 항목', {'n': items.length}),
                style: TextStyle(fontSize: 13, color: context.ink3, fontWeight: FontWeight.normal),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            height: 360,
            child: items.isEmpty
                ? Center(
                    child: Text(tr('휴지통이 비어 있습니다'), style: TextStyle(color: context.ink3)),
                  )
                : ListView(
                    children: [
                      for (final item in items)
                        CheckboxListTile(
                          dense: true,
                          value: selected.any((s) => s.dir == item.dir),
                          onChanged: (on) => setState(
                            () => on == true ? selected.add(item) : selected.removeWhere((s) => s.dir == item.dir),
                          ),
                          secondary: Icon(
                            isBinderPath(item.name)
                                ? Icons.collections_bookmark_outlined
                                : Icons.picture_as_pdf_outlined,
                          ),
                          title: Text(p.basenameWithoutExtension(item.name), overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${fmt.format(item.deleted)} · ${p.dirname(item.origin)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: context.ink3),
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: items.isEmpty
                  ? null
                  : () async {
                      final ok = await confirm(
                        context,
                        title: tr('휴지통 비우기'),
                        message: tr('휴지통의 모든 항목을 영구히 삭제할까요? 되돌릴 수 없습니다.'),
                        okLabel: tr('비우기'),
                        destructive: true,
                      );
                      if (ok) await run(trash.empty);
                    },
              child: Text(tr('휴지통 비우기')),
            ),
            TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => run(() async {
                      for (final s in selected.toList()) {
                        await trash.purge(s);
                      }
                    }),
              child: Text(tr('영구 삭제')),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => run(() async {
                      for (final s in selected.toList()) {
                        restored.add(await trash.restore(s));
                      }
                    }),
              child: Text(tr('복원')),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('닫기'))),
          ],
        );
      },
    ),
  );
  return restored;
}
