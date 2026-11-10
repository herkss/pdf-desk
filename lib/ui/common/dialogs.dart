import 'dart:io';

import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../services/perf_log.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = '',
  String? okLabel,
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
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('취소'))),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(okLabel ?? tr('확인'))),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String? okLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('취소'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(okLabel ?? tr('확인')),
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
    return await PerfLog.time(label, task);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  } finally {
    if (shown) navigator.pop();
  }
}

void showError(BuildContext context, Object error) {
  final msg = switch (error) {
    StateError(:final message) => message,
    FileSystemException(:final path) => tr(
      '파일을 사용 중이라 처리하지 못했습니다{name}. 다른 프로그램(PDF 뷰어, OneDrive 동기화 등)에서 열려 있지 않은지 확인한 뒤 다시 시도하세요.',
      {'name': path == null ? '' : ': ${path.split(RegExp(r'[\\/]')).last}'},
    ),
    _ => '$error',
  };
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(tr('오류: {msg}', {'msg': msg})), backgroundColor: Theme.of(context).colorScheme.error),
  );
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}
