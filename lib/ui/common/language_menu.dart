import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/settings.dart';

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
            const Icon(Icons.expand_more, size: 16, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}
