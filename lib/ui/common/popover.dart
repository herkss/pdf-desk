import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'app_theme.dart';

/// A settings panel that opens under [anchor] (a toolbar button), like the
/// right-click settings of drawing programs. Changes apply as they are made;
/// clicking outside or 닫기 closes it.
Future<void> showPopover(
  BuildContext context, {
  required Rect anchor,
  required String title,
  required Widget Function(BuildContext context, StateSetter setState) builder,
  double width = 340,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, _) {
      final screen = MediaQuery.sizeOf(context);
      final left = anchor.left.clamp(8.0, screen.width - width - 8);
      final top = anchor.bottom + 4;
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screen.height - top - 12),
              child: Material(
                elevation: 12,
                color: context.palette.menu,
                borderRadius: BorderRadius.circular(context.palette.radius + 4),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            ),
                            IconButton(
                              tooltip: tr('닫기'),
                              iconSize: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: builder(context, setState),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// A labelled row inside a popover.
Widget popRow(BuildContext context, String label, Widget child) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    children: [
      SizedBox(
        width: 78,
        child: Text(label, style: TextStyle(fontSize: 12.5, color: context.ink2)),
      ),
      Expanded(child: child),
    ],
  ),
);

/// A switch row inside a popover.
Widget popSwitch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
  dense: true,
  contentPadding: EdgeInsets.zero,
  title: Text(label, style: const TextStyle(fontSize: 13)),
  value: value,
  onChanged: onChanged,
);

/// Single-choice chips inside a popover.
Widget popChoices<T>(Map<T, String> options, T value, ValueChanged<T> onChanged) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [
    for (final MapEntry(:key, value: label) in options.entries)
      ChoiceChip(
        label: Text(label),
        selected: key == value,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onChanged(key),
      ),
  ],
);
