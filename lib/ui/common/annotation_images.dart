import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Decoded pictures of image annotations, shared by every page, thumbnail
/// and preview. Painters listen to it and repaint once a picture is ready.
class AnnotationImages extends ChangeNotifier {
  AnnotationImages._();
  static final instance = AnnotationImages._();

  final _images = <int, ui.Image>{};
  final _pending = <int>{};

  static int _key(String data) => Object.hash(data.length, data.hashCode);

  /// The picture, or null while it is being decoded (listeners are told
  /// when it is ready).
  ui.Image? get(String data) {
    final key = _key(data);
    final hit = _images[key];
    if (hit != null || !_pending.add(key)) return hit;
    () async {
      try {
        final codec = await ui.instantiateImageCodec(base64Decode(data));
        _images[key] = (await codec.getNextFrame()).image;
        // Keep memory bounded: pictures are small, but a desk can have many.
        while (_images.length > 200) {
          _images.remove(_images.keys.first)?.dispose();
        }
        notifyListeners();
      } catch (e) {
        debugPrint('image annotation: $e');
      } finally {
        _pending.remove(key);
      }
    }();
    return null;
  }
}
