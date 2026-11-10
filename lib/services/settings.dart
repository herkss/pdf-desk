import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'stamps.dart';

export 'stamps.dart' show StampDef;

/// App-wide preferences, stored as JSON in the application support directory.
class Settings extends ChangeNotifier {
  Settings._(this._file);

  final File _file;
  String rootPath = '';
  String stampLabel = '승인';
  String stampName = '';
  String lastFolder = '';

  /// What to do with a document printed to the "PDF Desk" printer: lay it on
  /// the desk as one document, or spread it out one sheet per page.
  bool spreadPrinted = false;

  /// Asked once at startup whether to install the PDF Desk printer.
  bool printerPrompted = false;

  /// Whether the desk shows the preview pane on the right.
  bool showPreview = true;

  /// UI language code (ko, ja, zh, en, es, fr).
  String language = 'ko';

  /// UI theme name (see AppTheme).
  String theme = 'iosLight';

  /// Each viewer tool's style (see ToolStyle), as saved JSON.
  Map<String, dynamic>? toolStyles;

  /// Registered stamps and the one the stamp tool uses.
  List<StampDef> stamps = [];
  String activeStamp = '';

  // Desk behaviour, set from the right-click menus of the toolbar buttons.

  /// Dropping a document on another: 'stack' (겹치기), 'ask', or 'place'
  /// (just lay it on top).
  String dropAction = 'stack';

  /// 펼치기 keeps the original document instead of replacing it.
  bool spreadKeepsOriginal = false;
  bool confirmDelete = true;

  /// Deleting moves documents to the trash (otherwise they're gone).
  bool deleteToTrash = true;

  /// Exported PDFs carry the annotations as data, to edit them again later.
  bool exportEditable = true;

  /// Imported images: 'a4' fits them to an A4 page, 'original' keeps their
  /// size (at 96 dpi).
  String imageFit = 'a4';

  /// 정렬: 'name', 'modified' or 'size', and the order.
  String arrangeBy = 'name';
  bool arrangeDescending = false;

  /// The mouse wheel turns pages in the preview pane.
  bool previewWheelPages = true;

  /// The stamp the stamp tool puts down (a date stamp from [stampLabel] and
  /// [stampName] if none is registered).
  StampDef get currentStamp {
    if (stamps.isEmpty) stamps = [StampDef.date(stampLabel, stampName)];
    return stamps.firstWhere((s) => s.id == activeStamp, orElse: () => stamps.first);
  }

  /// Where the "PDF Desk" printer writes its output.
  String get inboxPath => p.join(_file.parent.path, 'inbox');

  /// Settings stored in [file], for tests.
  @visibleForTesting
  factory Settings.at(File file, String rootPath) => Settings._(file)..rootPath = rootPath;

  static Future<Settings> load() async {
    final dir = await getApplicationSupportDirectory();
    final s = Settings._(File(p.join(dir.path, 'settings.json')));
    try {
      final j = jsonDecode(await s._file.readAsString()) as Map<String, dynamic>;
      s.rootPath = j['rootPath'] as String? ?? '';
      s.stampLabel = j['stampLabel'] as String? ?? s.stampLabel;
      s.stampName = j['stampName'] as String? ?? '';
      s.lastFolder = j['lastFolder'] as String? ?? '';
      s.spreadPrinted = j['spreadPrinted'] as bool? ?? false;
      s.printerPrompted = j['printerPrompted'] as bool? ?? false;
      s.showPreview = j['showPreview'] as bool? ?? true;
      s.language = j['language'] as String? ?? 'ko';
      s.theme = j['theme'] as String? ?? 'iosLight';
      s.toolStyles = j['toolStyles'] as Map<String, dynamic>?;
      s.stamps = [
        for (final x in (j['stamps'] as List? ?? const []))
          if (x is Map<String, dynamic>) StampDef.fromJson(x),
      ];
      s.activeStamp = j['activeStamp'] as String? ?? '';
      s.dropAction = j['dropAction'] as String? ?? 'stack';
      s.spreadKeepsOriginal = j['spreadKeepsOriginal'] as bool? ?? false;
      s.confirmDelete = j['confirmDelete'] as bool? ?? true;
      s.deleteToTrash = j['deleteToTrash'] as bool? ?? true;
      s.exportEditable = j['exportEditable'] as bool? ?? true;
      s.imageFit = j['imageFit'] as String? ?? 'a4';
      s.arrangeBy = j['arrangeBy'] as String? ?? 'name';
      s.arrangeDescending = j['arrangeDescending'] as bool? ?? false;
      s.previewWheelPages = j['previewWheelPages'] as bool? ?? true;
    } catch (_) {}
    if (s.rootPath.isEmpty || !Directory(s.rootPath).existsSync()) {
      s.rootPath = await defaultRootPath();
    }
    await Directory(s.rootPath).create(recursive: true);
    if (s.stampName.isEmpty) {
      s.stampName = Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    }
    return s;
  }

  /// Where the desk lives by default: `C:\Users\<name>\PdfDesk` on Windows.
  /// Not under Documents, which OneDrive often syncs: it holds files while
  /// uploading them, so merging and saving fail with "file in use".
  static Future<String> defaultRootPath() async {
    final home = Platform.isWindows ? Platform.environment['USERPROFILE'] : null;
    if (home != null && home.isNotEmpty) return p.join(home, 'PdfDesk');
    return p.join((await getApplicationDocumentsDirectory()).path, 'PdfDesk');
  }

  /// Whether [path] is inside a OneDrive (or other cloud-synced) folder.
  static bool isCloudSynced(String path) {
    final parts = p.split(path).map((s) => s.toLowerCase());
    return parts.any((s) => s == 'onedrive' || s.startsWith('onedrive -') || s == 'dropbox' || s == 'google drive');
  }

  Future<void> save() async {
    notifyListeners();
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'rootPath': rootPath,
        'stampLabel': stampLabel,
        'stampName': stampName,
        'lastFolder': lastFolder,
        'spreadPrinted': spreadPrinted,
        'printerPrompted': printerPrompted,
        'showPreview': showPreview,
        'language': language,
        'theme': theme,
        'toolStyles': ?toolStyles,
        'stamps': [for (final st in stamps) st.toJson()],
        'activeStamp': activeStamp,
        'dropAction': dropAction,
        'spreadKeepsOriginal': spreadKeepsOriginal,
        'confirmDelete': confirmDelete,
        'deleteToTrash': deleteToTrash,
        'exportEditable': exportEditable,
        'imageFit': imageFit,
        'arrangeBy': arrangeBy,
        'arrangeDescending': arrangeDescending,
        'previewWheelPages': previewWheelPages,
      }),
    );
  }
}
