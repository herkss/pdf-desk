import 'package:flutter/material.dart';

import '../../services/pdf_ops.dart' show paperSizes;
import '../../l10n/l10n.dart';

class NewDocument {
  NewDocument(this.name, this.size, this.pages);
  final String name;

  /// Page size in points, already turned for the orientation.
  final Size size;
  final int pages;
}

/// 새 문서 작성: paper size, orientation, page count and name.
Future<NewDocument?> showNewDocumentDialog(BuildContext context) {
  var paper = 'A4';
  var landscape = false;
  final pages = TextEditingController(text: '1');
  final name = TextEditingController(text: tr('새 문서'));
  return showDialog<NewDocument>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final s = paperSizes[paper]!;
        final size = landscape ? Size(s.height, s.width) : s;
        void ok() {
          final n = (int.tryParse(pages.text) ?? 1).clamp(1, 200);
          final title = name.text.trim().isEmpty ? tr('새 문서') : name.text.trim();
          Navigator.pop(context, NewDocument(title, size, n));
        }

        return AlertDialog(
          title: Text(tr('새 문서 작성')),
          content: SizedBox(
            width: 420,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('용지'), style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final k in paperSizes.keys)
                            ChoiceChip(
                              label: Text(k),
                              selected: paper == k,
                              onSelected: (_) => setState(() => paper = k),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(tr('방향'), style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(value: false, icon: Icon(Icons.crop_portrait), label: Text(tr('세로'))),
                          ButtonSegment(value: true, icon: Icon(Icons.crop_landscape), label: Text(tr('가로'))),
                        ],
                        selected: {landscape},
                        onSelectionChanged: (v) => setState(() => landscape = v.first),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: pages,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: tr('쪽 수'), isDense: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: name,
                              autofocus: true,
                              decoration: InputDecoration(labelText: tr('이름'), isDense: true),
                              onSubmitted: (_) => ok(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Preview of the sheet's proportions.
                SizedBox(
                  width: 96,
                  height: 120,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: size.width / size.height,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(1, 2))],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${(size.width / 72 * 25.4).round()}×${(size.height / 72 * 25.4).round()}',
                          style: const TextStyle(fontSize: 10, color: Colors.black45),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('취소'))),
            FilledButton(onPressed: ok, child: Text(tr('만들기'))),
          ],
        );
      },
    ),
  );
}
