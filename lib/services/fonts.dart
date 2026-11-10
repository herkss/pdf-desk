import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A font file, or one face of a TrueType collection (.ttc).
class FontFace {
  const FontFace(this.file, [this.index = 0]);
  final String file;
  final int index;
}

/// A font that text annotations can use: the family name Flutter draws with
/// and the Windows font files embedded when exporting.
class FontChoice {
  const FontChoice(
    this.label,
    this.family,
    this.regular, {
    this.bold,
    this.italic,
    this.boldItalic,
    this.korean = true,
  });

  /// Name shown in menus.
  final String label;
  final String family;
  final FontFace regular;
  final FontFace? bold, italic, boldItalic;

  /// Has Hangul glyphs; otherwise Korean text is exported in the default font.
  final bool korean;

  /// The face for the style; null if the font has none, so the export makes
  /// it up (heavier outline, slanted).
  FontFace? face({bool bold = false, bool italic = false}) => switch ((bold, italic)) {
    (false, false) => regular,
    (true, false) => this.bold,
    (false, true) => this.italic,
    (true, true) => boldItalic,
  };
}

const defaultFontFamily = 'Malgun Gothic';

const fontChoices = [
  FontChoice('맑은 고딕', 'Malgun Gothic', FontFace('malgun.ttf'), bold: FontFace('malgunbd.ttf')),
  FontChoice('굴림', 'Gulim', FontFace('gulim.ttc')),
  FontChoice('돋움', 'Dotum', FontFace('gulim.ttc', 2)),
  FontChoice('바탕', 'Batang', FontFace('batang.ttc')),
  FontChoice('궁서', 'Gungsuh', FontFace('batang.ttc', 2)),
  FontChoice('나눔고딕', 'NanumGothic', FontFace('NanumGothic.ttf'), bold: FontFace('NanumGothicBold.ttf')),
  FontChoice('나눔명조', 'NanumMyeongjo', FontFace('NanumMyeongjo.ttf'), bold: FontFace('NanumMyeongjoBold.ttf')),
  FontChoice('나눔손글씨 펜', 'Nanum Pen Script', FontFace('NanumPen.ttf')),
  FontChoice(
    'Arial',
    'Arial',
    FontFace('arial.ttf'),
    bold: FontFace('arialbd.ttf'),
    italic: FontFace('ariali.ttf'),
    boldItalic: FontFace('arialbi.ttf'),
    korean: false,
  ),
  FontChoice(
    'Times New Roman',
    'Times New Roman',
    FontFace('times.ttf'),
    bold: FontFace('timesbd.ttf'),
    italic: FontFace('timesi.ttf'),
    boldItalic: FontFace('timesbi.ttf'),
    korean: false,
  ),
  FontChoice(
    'Courier New',
    'Courier New',
    FontFace('cour.ttf'),
    bold: FontFace('courbd.ttf'),
    italic: FontFace('couri.ttf'),
    boldItalic: FontFace('courbi.ttf'),
    korean: false,
  ),
];

FontChoice fontChoiceOf(String? family) =>
    fontChoices.firstWhere((f) => f.family == (family ?? defaultFontFamily), orElse: () => fontChoices.first);

/// Folders searched for font files: the Windows fonts folder (machine-wide
/// and per-user installs) and common Linux/macOS locations.
List<String> get _fontDirs => [
  // Extra folder for tests (e.g. Windows font files copied elsewhere).
  ?Platform.environment['PDFDESK_FONT_DIR'],
  if (Platform.isWindows) ...[
    p.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts'),
    if (Platform.environment['LOCALAPPDATA'] case final local?) p.join(local, 'Microsoft', 'Windows', 'Fonts'),
  ],
  '/usr/share/fonts/truetype/nanum',
  '/Library/Fonts',
];

final _bytes = <String, Uint8List?>{};

/// The face as a single-font TrueType file (PDFium can't embed a collection),
/// or null if it isn't installed.
Future<Uint8List?> loadFontFace(FontFace face) async {
  final key = '${face.file}#${face.index}';
  if (_bytes.containsKey(key)) return _bytes[key];
  Uint8List? out;
  for (final dir in _fontDirs) {
    final f = File(p.join(dir, face.file));
    if (!await f.exists()) continue;
    final data = await f.readAsBytes();
    out = face.file.toLowerCase().endsWith('.ttc') ? extractTtcFace(data, face.index) : data;
    break;
  }
  return _bytes[key] = out;
}

/// Copies face [index] out of a TrueType collection into a standalone font:
/// its table directory plus the tables it points at, with offsets rebased.
Uint8List? extractTtcFace(Uint8List ttc, int index) {
  final src = ByteData.sublistView(ttc);
  if (ttc.length < 12 || String.fromCharCodes(ttc.sublist(0, 4)) != 'ttcf') return null;
  final count = src.getUint32(8);
  if (index >= count) return null;
  final dir = src.getUint32(12 + index * 4);
  final numTables = src.getUint16(dir + 4);
  final headerLen = 12 + numTables * 16;
  final tables = <(int tag, int checksum, int offset, int length)>[
    for (var i = 0; i < numTables; i++)
      (
        src.getUint32(dir + 12 + i * 16),
        src.getUint32(dir + 12 + i * 16 + 4),
        src.getUint32(dir + 12 + i * 16 + 8),
        src.getUint32(dir + 12 + i * 16 + 12),
      ),
  ];
  var size = headerLen;
  for (final t in tables) {
    size += (t.$4 + 3) & ~3;
  }
  final out = Uint8List(size);
  final o = ByteData.sublistView(out);
  out.setRange(0, 12, ttc, dir);
  var at = headerLen;
  for (final (i, t) in tables.indexed) {
    o
      ..setUint32(12 + i * 16, t.$1)
      ..setUint32(12 + i * 16 + 4, t.$2)
      ..setUint32(12 + i * 16 + 8, at)
      ..setUint32(12 + i * 16 + 12, t.$4);
    out.setRange(at, at + t.$4, ttc, t.$3);
    at += (t.$4 + 3) & ~3;
  }
  return out;
}
