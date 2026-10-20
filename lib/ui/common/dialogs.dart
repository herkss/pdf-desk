import 'package:flutter/material.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = '',
  String okLabel = '확인',
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 3 : 1,
          decoration: InputDecoration(labelText: label.isEmpty ? null : label),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(context, v) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(okLabel)),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = '확인',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Runs [task] behind a modal progress indicator and reports failures.
Future<T?> runBusy<T>(BuildContext context, String label, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var shown = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 20),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    ),
  ).whenComplete(() => shown = false);
  try {
    return await task();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  } finally {
    if (shown) navigator.pop();
  }
}

void showError(BuildContext context, Object error) {
  final msg = error is StateError ? error.message : '$error';
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text('오류: $msg'), backgroundColor: Theme.of(context).colorScheme.error));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}
