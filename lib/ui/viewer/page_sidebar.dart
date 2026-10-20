import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../common/annotation_painter.dart';
import 'viewer_controller.dart';

/// Page thumbnails. Click to jump, Ctrl/Shift-click to multi-select, drag the
/// handle to reorder, right-click for page operations.
class PageSidebar extends StatelessWidget {
  const PageSidebar({
    super.key,
    required this.controller,
    required this.onGoTo,
    required this.onReorder,
    required this.onMenu,
  });

  final ViewerController controller;
  final void Function(int page) onGoTo;
  final void Function(List<int> order) onReorder;
  final void Function(Offset globalPosition) onMenu;

  ViewerController get c => controller;

  void _tap(int i) {
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed) {
      c.selectedPages.contains(i) ? c.selectedPages.remove(i) : c.selectedPages.add(i);
    } else if (kb.isShiftPressed && c.selectedPages.isNotEmpty) {
      final anchor = c.selectedPages.last;
      final (a, b) = anchor < i ? (anchor, i) : (i, anchor);
      c.selectedPages.addAll([for (var p = a; p <= b; p++) p]);
    } else {
      c.selectedPages
        ..clear()
        ..add(i);
    }
    onGoTo(i);
  }

  @override
  Widget build(BuildContext context) {
    final doc = c.document;
    if (doc == null) return const SizedBox();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: const Color(0xFFF2F4F7),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: doc.pages.length,
        onReorderItem: (from, to) {
          if (from == to) return;
          final order = [for (var i = 0; i < doc.pages.length; i++) i];
          order.insert(to, order.removeAt(from));
          onReorder(order);
        },
        itemBuilder: (context, i) {
          final size = c.pageSize(i);
          final selected = c.selectedPages.contains(i);
          final current = c.currentPage == i;
          const w = 100.0;
          final h = w * size.height / size.width;
          return GestureDetector(
            key: ValueKey('${doc.hashCode}-$i'),
            onSecondaryTapUp: (d) {
              if (!c.selectedPages.contains(i)) {
                c.selectedPages
                  ..clear()
                  ..add(i);
                onGoTo(i);
              }
              onMenu(d.globalPosition);
            },
            child: InkWell(
              onTap: () => _tap(i),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 28, 6),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? scheme.primary
                              : current
                              ? scheme.primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PdfPageView(document: doc, pageNumber: i + 1, maximumDpi: 72),
                            if (c.showAnnotations)
                              ValueListenableBuilder(
                                valueListenable: c.repaint,
                                builder: (context, _, _) => CustomPaint(
                                  painter: AnnotationPainter(annotations: c.annotationsOn(i), scale: w / size.width),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: current ? FontWeight.bold : null,
                        color: current ? scheme.primary : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
