import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/settings.dart';
import 'app_theme.dart';

/// Top-right language switch: 한국어, 日本語, 中文, English, Español, Français.
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key, required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final current = appLanguage.value;
    return PopupMenuButton<AppLanguage>(
      tooltip: tr('언어'),
      initialValue: current,
      position: PopupMenuPosition.under,
      onSelected: (lang) {
        settings.language = lang.name;
        unawaited(settings.save());
        appLanguage.value = lang;
      },
      itemBuilder: (_) => [
        for (final l in AppLanguage.values) CheckedPopupMenuItem(value: l, checked: l == current, child: Text(l.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(current.label, style: const TextStyle(fontSize: 13)),
            Icon(Icons.expand_more, size: 16, color: context.ink3),
          ],
        ),
      ),
    );
  }
}

/// Top-right theme switch, each entry with a sample of its colors.
class ThemeMenu extends StatelessWidget {
  const ThemeMenu({super.key, required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final current = appTheme.value;
    Widget swatch(AppTheme t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in t.swatch)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0x33808080)),
            ),
          ),
      ],
    );
    return PopupMenuButton<AppTheme>(
      tooltip: tr('테마'),
      initialValue: current,
      position: PopupMenuPosition.under,
      onSelected: (t) {
        settings.theme = t.name;
        unawaited(settings.save());
        appTheme.value = t;
      },
      itemBuilder: (_) => [
        for (final t in AppTheme.values)
          CheckedPopupMenuItem(
            value: t,
            checked: t == current,
            child: Row(children: [swatch(t), const SizedBox(width: 10), Text(t.label)]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.palette_outlined, size: 21, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
