import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/desk_controller.dart';
import '../../services/thumbnails.dart';
import '../common/annotation_painter.dart';
import '../common/app_theme.dart';

const _pageShadow = [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(1.5, 1.5))];

/// First-page thumbnail of a document or binder with its annotations, drawn
/// as a sheet of paper. With [stacked], a multi-page document shows the
/// edges of the sheets underneath, like a pile on a desk.
class ThumbnailView extends StatefulWidget {
  const ThumbnailView({super.key, required this.path, this.stacked = false});
  final String path;
  final bool stacked;

  /// Gap between the edges of stacked sheets.
  static const sheetGap = DeskController.sheetGap;

  @override
  State<ThumbnailView> createState() => _ThumbnailViewState();
}

class _ThumbnailViewState extends State<ThumbnailView> {
  Thumbnail? _thumb;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ThumbnailService.instance.revision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(ThumbnailView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  @override
  void dispose() {
    ThumbnailService.instance.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final path = widget.path;
    Thumbnail? t;
    try {
      t = await ThumbnailService.instance.get(path);
    } catch (_) {
      // A missing or unreadable document: the broken-page icon, not a
      // spinner that never stops.
    }
    if (!mounted || path != widget.path) return;
    setState(() {
      _thumb = t;
      _failed = t == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _thumb;
    if (t == null) {
      return LayoutBuilder(
        builder: (context, c) => Container(
          width: c.maxWidth,
          height: math.min(c.maxHeight, c.maxWidth * 1.414),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: _pageShadow),
          alignment: Alignment.center,
          child: _failed
              ? Icon(Icons.broken_image_outlined, color: context.ink4)
              : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final sheets = widget.stacked ? math.min(3, t.pageCount - 1) : 0;
    const gap = ThumbnailView.sheetGap;
    return LayoutBuilder(
      builder: (context, c) {
        final inset = sheets * gap;
        final aspect = t.pageSize.width / t.pageSize.height;
        var w = c.maxWidth - inset, h = w / aspect;
        if (h > c.maxHeight - inset) {
          h = c.maxHeight - inset;
          w = h * aspect;
        }
        final page = Container(
          width: w,
          height: h,
          decoration: const BoxDecoration(color: Colors.white, boxShadow: _pageShadow),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RawImage(image: t.image, fit: BoxFit.fill),
              if (t.annotations.isNotEmpty)
                CustomPaint(
                  painter: AnnotationPainter(annotations: t.annotations, scale: w / t.pageSize.width),
                ),
              if (t.pageCount > 1)
                Positioned(
                  left: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0x8A000000), borderRadius: BorderRadius.circular(3)),
                    child: Text('${t.pageCount}p', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        );
        if (sheets == 0) return page;
        // Lower sheets peek out up and to the right of the top sheet.
        return SizedBox(
          width: w + inset,
          height: h + inset,
          child: Stack(
            children: [
              for (var i = sheets; i >= 1; i--)
                Positioned(
                  left: i * gap,
                  top: inset - i * gap,
                  width: w,
                  height: h,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color.lerp(Colors.white, const Color(0xFFD5D8DC), i / (sheets + 1)),
                      border: Border.all(color: const Color(0x33000000), width: 0.6),
                      boxShadow: _pageShadow,
                    ),
                  ),
                ),
              Positioned(left: 0, top: inset, child: page),
            ],
          ),
        );
      },
    );
  }
}

/// A document or binder card on the desk.
class DeskItemCard extends StatelessWidget {
  const DeskItemCard({
    super.key,
    required this.entry,
    required this.size,
    required this.selected,
    this.highlighted = false,
    this.dropLabel,
  });

  final DeskEntry entry;
  final Size size;
  final bool selected;

  /// Shown while something is dragged over this item.
  final bool highlighted;

  /// What dropping here will do, shown while [highlighted].
  final String? dropLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbH = size.height - DeskController.labelHeight;
    const border = DeskController.cardBorder;
    // Only the sheet itself (and its name) takes clicks and drops: the empty
    // space around a small or landscape page is left to the desk.
    final page = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: highlighted
              ? Colors.orange
              : selected
              ? scheme.primary
              : Colors.transparent,
          width: border,
        ),
      ),
      child: _Page(
        entry: entry,
        width: size.width - border * 2 - (entry.isBinder ? 10 : 0),
        maxHeight: thumbH - border * 2,
      ),
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          SizedBox(
            width: size.width,
            height: thumbH,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                page,
                if (highlighted && dropLabel != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add, size: 14, color: Colors.white),
                              Text(dropLabel!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.2, color: selected ? scheme.onPrimary : context.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.entry, required this.width, required this.maxHeight});
  final DeskEntry entry;
  final double width;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final page = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: maxHeight - (entry.isBinder ? DeskController.binderTop : 0),
      ),
      child: ThumbnailView(path: entry.path, stacked: !entry.isBinder),
    );
    if (!entry.isBinder) return page;
    // Binder: a cover spine on the left and stacked sheets behind.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Transform.translate(
            offset: const Offset(5, -5),
            child: Container(color: const Color(0xFFE0E0E0)),
          ),
        ),
        page,
        Positioned(
          left: -8,
          top: 0,
          bottom: 0,
          child: Container(
            width: 9,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
              boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 2)],
            ),
          ),
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Icon(Icons.collections_bookmark, size: 16, color: Theme.of(context).colorScheme.primary),
        ),
      ],
    );
  }
}
