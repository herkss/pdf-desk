import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings.dart';
import 'page_view.dart';
import 'viewer_controller.dart';

const _gap = 16.0;

/// Points → logical pixels at 100% zoom (PDF is 72 dpi, screens 96 dpi).
const pointToPixel = 96 / 72;

/// Continuous vertical page view.
class PagesView extends StatefulWidget {
  const PagesView({super.key, required this.controller, required this.settings});
  final ViewerController controller;
  final Settings settings;

  @override
  State<PagesView> createState() => PagesViewState();
}

class PagesViewState extends State<PagesView> {
  final _v = ScrollController();
  final _h = ScrollController();
  Size _viewport = Size.zero;
  double _lastScale = 0;

  ViewerController get c => widget.controller;
  double get scale => c.zoom * pointToPixel;

  @override
  void initState() {
    super.initState();
    _v.addListener(_trackPage);
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  double _extent(int i) => c.pageSize(i).height * scale + _gap;

  double offsetOf(int page) {
    var y = 0.0;
    for (var i = 0; i < page && i < c.pages.length; i++) {
      y += _extent(i);
    }
    return y;
  }

  void _trackPage() {
    if (!_v.hasClients || c.pages.isEmpty) return;
    final probe = _v.offset + _viewport.height / 3;
    var y = 0.0;
    var page = 0;
    for (var i = 0; i < c.pages.length; i++) {
      final next = y + _extent(i);
      if (probe < next) {
        page = i;
        break;
      }
      y = next;
      page = i;
    }
    c.setCurrentPage(page);
  }

  void goToPage(int page, {Rect? reveal}) {
    if (!_v.hasClients || c.pages.isEmpty) return;
    page = page.clamp(0, c.pages.length - 1);
    var target = offsetOf(page);
    if (reveal != null) target += reveal.top * scale - _viewport.height / 3;
    _v.jumpTo(target.clamp(0, _v.position.maxScrollExtent));
    c.setCurrentPage(page);
  }

  double get _maxPageWidth {
    var w = 0.0;
    for (var i = 0; i < c.pages.length; i++) {
      w = math.max(w, c.pageSize(i).width);
    }
    return w;
  }

  void fitWidth() {
    if (_viewport.width <= 0 || c.pages.isEmpty) return;
    c.setZoom((_viewport.width - 48) / (_maxPageWidth * pointToPixel));
  }

  void fitPage() {
    if (_viewport.width <= 0 || c.pages.isEmpty) return;
    final s = c.pageSize(c.currentPage);
    c.setZoom(
      math.min(
        (_viewport.width - 48) / (s.width * pointToPixel),
        (_viewport.height - _gap * 2) / (s.height * pointToPixel),
      ),
    );
  }

  /// Keeps the current reading position when the zoom changes.
  void _preserveAnchor() {
    if (_lastScale == 0 || _lastScale == scale || !_v.hasClients || _v.offset <= 0) {
      _lastScale = scale;
      return;
    }
    final ratio = scale / _lastScale;
    final target = (_v.offset + _viewport.height / 2) * ratio - _viewport.height / 2;
    _lastScale = scale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_v.hasClients) _v.jumpTo(target.clamp(0, _v.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (c.pages.isEmpty) return const SizedBox();
    _preserveAnchor();
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        final contentWidth = math.max(constraints.maxWidth, _maxPageWidth * scale + 48);
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent &&
                (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
              GestureBinding.instance.pointerSignalResolver.register(e, (_) {
                c.setZoom(c.zoom * (e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1));
              });
            }
          },
          // While a drawing tool is active, pen/touch drags must draw rather
          // than scroll; the wheel and scrollbars still scroll.
          child: ScrollConfiguration(
            behavior: c.tool == Tool.select
                ? ScrollConfiguration.of(context)
                : ScrollConfiguration.of(context).copyWith(dragDevices: const {}),
            child: Container(
              color: const Color(0xFF8A9099),
              child: Scrollbar(
                controller: _h,
                thumbVisibility: contentWidth > constraints.maxWidth,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    height: constraints.maxHeight,
                    child: Scrollbar(
                      controller: _v,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _v,
                        padding: const EdgeInsets.only(bottom: _gap),
                        itemCount: c.pages.length,
                        itemExtentBuilder: (i, _) => i < c.pages.length ? _extent(i) : null,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(top: _gap),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: AnnotatedPage(
                              key: ValueKey('${c.document.hashCode}-$i'),
                              controller: c,
                              index: i,
                              scale: scale,
                              settings: widget.settings,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
