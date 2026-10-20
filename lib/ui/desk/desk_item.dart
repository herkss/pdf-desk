import 'package:flutter/material.dart';

import '../../services/desk_controller.dart';
import '../../services/thumbnails.dart';
import '../common/annotation_painter.dart';

/// First-page thumbnail of a document or binder with its annotations.
class ThumbnailView extends StatefulWidget {
  const ThumbnailView({super.key, required this.path});
  final String path;

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
    final t = await ThumbnailService.instance.get(path);
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
      return Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: _failed
            ? const Icon(Icons.broken_image_outlined, color: Colors.black26)
            : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return AspectRatio(
      aspectRatio: t.pageSize.width / t.pageSize.height,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          fit: StackFit.expand,
          children: [
            RawImage(image: t.image, fit: BoxFit.fill),
            if (t.annotations.isNotEmpty)
              CustomPaint(
                painter: AnnotationPainter(annotations: t.annotations, scale: c.maxWidth / t.pageSize.width),
              ),
            if (t.pageCount > 1)
              Positioned(
                left: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                  child: Text('${t.pageCount}p', style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
          ],
        ),
      ),
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
  });

  final DeskEntry entry;
  final Size size;
  final bool selected;

  /// Shown while something is dragged over this item.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbH = size.height - 40;
    final pageBox = Container(
      width: size.width,
      height: thumbH,
      alignment: Alignment.bottomCenter,
      child: _Page(entry: entry, width: size.width - (entry.isBinder ? 10 : 0), maxHeight: thumbH),
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: highlighted
                    ? Colors.orange
                    : selected
                    ? scheme.primary
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: pageBox,
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
              style: TextStyle(fontSize: 11.5, height: 1.2, color: selected ? scheme.onPrimary : Colors.black87),
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
    final page = Container(
      constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight - (entry.isBinder ? 6 : 2)),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(1.5, 1.5))],
      ),
      child: ThumbnailView(path: entry.path),
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
              color: const Color(0xFF3F51B5),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
              boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 2)],
            ),
          ),
        ),
        const Positioned(
          right: 2,
          bottom: 2,
          child: Icon(Icons.collections_bookmark, size: 16, color: Color(0xFF3F51B5)),
        ),
      ],
    );
  }
}
