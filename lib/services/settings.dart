import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    } catch (_) {}
    if (s.rootPath.isEmpty || !Directory(s.rootPath).existsSync()) {
      final docs = await getApplicationDocumentsDirectory();
      s.rootPath = p.join(docs.path, 'PdfDesk');
    }
    await Directory(s.rootPath).create(recursive: true);
    if (s.stampName.isEmpty) {
      s.stampName = Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    }
    return s;
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
      }),
    );
  }
}
