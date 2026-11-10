import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_desk/l10n/l10n.dart';

String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]) {
    'n' => '\n',
    final c => c!,
  },
);

/// Every tr('…') key used in lib/.
Set<String> _keysInSource() {
  final keys = <String>{};
  final pattern = RegExp(r'''\btr\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''');
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
    for (final m in pattern.allMatches(f.readAsStringSync())) {
      keys.add(_unescape(m[1] ?? m[2]!));
    }
  }
  return keys;
}

void main() {
  test('every UI string is translated into every language', () {
    final keys = _keysInSource();
    expect(keys.length, greaterThan(200));
    for (final MapEntry(key: lang, value: table) in translationTables.entries) {
      final missing = keys.where((k) => !table.containsKey(k)).toList();
      expect(missing, isEmpty, reason: '$lang is missing ${missing.length} strings');
      for (final k in keys) {
        final ph = RegExp(r'\{\w+\}');
        expect(
          ph.allMatches(table[k]!).map((m) => m[0]).toSet(),
          ph.allMatches(k).map((m) => m[0]).toSet(),
          reason: '$lang: placeholders of "$k"',
        );
      }
    }
  });

  test('tr switches language and fills placeholders', () {
    addTearDown(() => appLanguage.value = AppLanguage.ko);
    expect(tr('{n}개 선택', {'n': 3}), '3개 선택');
    appLanguage.value = AppLanguage.en;
    expect(tr('{n}개 선택', {'n': 3}), '3 selected');
    appLanguage.value = AppLanguage.ja;
    expect(tr('삭제'), '削除');
    appLanguage.value = AppLanguage.fr;
    expect(tr('번역 없는 문장'), '번역 없는 문장');
    expect(AppLanguage.byCode('zh'), AppLanguage.zh);
    expect(AppLanguage.byCode('xx'), AppLanguage.ko);
  });
}
