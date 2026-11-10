import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

/// A registered stamp: a date stamp (label / date / name in a circle) or an
/// image such as a company seal or a signature.
class StampDef {
  StampDef({
    String? id,
    required this.kind,
    this.label = '',
    this.name = '',
    this.image,
    this.aspect = 1,
    this.size = 64,
    this.color = 0xFFD32F2F,
  }) : id = id ?? const Uuid().v4();

  factory StampDef.date(String label, String name) => StampDef(kind: 'date', label: label, name: name);

  final String id;

  /// 'date' or 'image'.
  final String kind;
  String label;
  String name;

  /// Image stamps: the picture as base64 PNG, and its width / height.
  String? image;
  double aspect;

  /// Width in points.
  double size;
  int color;

  bool get isImage => kind == 'image';

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'label': label,
    'name': name,
    'image': ?image,
    'aspect': aspect,
    'size': size,
    'color': color,
  };

  factory StampDef.fromJson(Map<String, dynamic> j) => StampDef(
    id: j['id'] as String?,
    kind: j['kind'] as String? ?? 'date',
    label: j['label'] as String? ?? '',
    name: j['name'] as String? ?? '',
    image: j['image'] as String?,
    aspect: (j['aspect'] as num?)?.toDouble() ?? 1,
    size: (j['size'] as num?)?.toDouble() ?? 64,
    color: j['color'] as int? ?? 0xFFD32F2F,
  );
}

/// An image stamp from a picture file. With [clearWhite], the near-white
/// background of a scanned seal or signature becomes transparent so only the
/// ink shows on the page. Large pictures are scaled down. Null if the file
/// isn't an image.
StampDef? imageStamp(Uint8List bytes, {bool clearWhite = true, String name = ''}) {
  var picture = img.decodeImage(bytes);
  if (picture == null) return null;
  if (picture.width > 800 || picture.height > 800) {
    picture = picture.width >= picture.height
        ? img.copyResize(picture, width: 800)
        : img.copyResize(picture, height: 800);
  }
  picture = picture.convert(numChannels: 4);
  if (clearWhite) {
    for (final px in picture) {
      final light = (px.r + px.g + px.b) / 3;
      final max = px.maxChannelValue;
      if (light > max * 0.86) {
        px.a = 0;
      } else if (light > max * 0.7) {
        // Soften the edge of the ink instead of a hard cut.
        px.a = (px.a * (max * 0.86 - light) / (max * 0.16)).clamp(0, max);
      }
    }
  }
  final png = img.encodePng(picture);
  return StampDef(
    kind: 'image',
    name: name,
    image: base64Encode(png),
    aspect: picture.width / picture.height,
    size: 70,
  );
}
