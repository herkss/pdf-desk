import 'package:flutter/widgets.dart';

import 'tr_en.dart';
import 'tr_es.dart';
import 'tr_fr.dart';
import 'tr_ja.dart';
import 'tr_zh.dart';

/// UI languages. Korean is the source language: every string in the code is
/// written in Korean and looked up in the other tables.
enum AppLanguage {
  ko('한국어', Locale('ko')),
  ja('日本語', Locale('ja')),
  zh('中文', Locale('zh')),
  en('English', Locale('en')),
  es('Español', Locale('es')),
  fr('Français', Locale('fr'));

  const AppLanguage(this.label, this.locale);

  /// The language's own name, shown in the language menu.
  final String label;
  final Locale locale;

  static AppLanguage byCode(String? code) => values.firstWhere((l) => l.name == code, orElse: () => AppLanguage.ko);
}

/// The current UI language; the app rebuilds when it changes.
final appLanguage = ValueNotifier(AppLanguage.ko);

const translationTables = <AppLanguage, Map<String, String>>{
  AppLanguage.ja: trJa,
  AppLanguage.zh: trZh,
  AppLanguage.en: trEn,
  AppLanguage.es: trEs,
  AppLanguage.fr: trFr,
};

/// [ko] in the current language, with `{name}` placeholders filled from
/// [args]. Missing translations fall back to Korean.
String tr(String ko, [Map<String, Object?> args = const {}]) {
  var s = translationTables[appLanguage.value]?[ko] ?? ko;
  for (final MapEntry(:key, :value) in args.entries) {
    s = s.replaceAll('{$key}', '$value');
  }
  return s;
}
