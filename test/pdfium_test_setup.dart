import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

/// `flutter test` has no app bundle, so point pdfrx at the PDFium library that
/// pdfium_dart's build hook placed under build/native_assets.
Future<void> initPdfiumForTests(String cacheDir) async {
  Pdfrx.cacheDirectoryPath = cacheDir;
  final (os, name) = Platform.isWindows
      ? ('windows', 'pdfium.dll')
      : Platform.isMacOS
      ? ('macos', 'libpdfium.dylib')
      : ('linux', 'libpdfium.so');
  final lib = File('build/native_assets/$os/$name');
  if (lib.existsSync()) Pdfrx.pdfiumModulePath = lib.absolute.path;
  await pdfrxFlutterInitialize();
}
