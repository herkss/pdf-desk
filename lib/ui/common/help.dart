import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../l10n/manual.dart';
import 'app_theme.dart';

const appVersion = '1.2.0';

/// 프로그램 정보: icon, version, what it is, and the open-source licenses.
Future<void> showAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/app_icon.png', width: 96, height: 96),
          ),
          const SizedBox(height: 12),
          const Text('PDF Desk', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(tr('버전 {v}', {'v': appVersion}), style: TextStyle(color: context.ink3)),
          const SizedBox(height: 14),
          Text(
            tr('종이 문서를 책상 위에 펼쳐 놓듯 PDF를 다루는 문서 관리 프로그램입니다. 겹치기·펼치기·바인더, 주석과 도장, 가상 프린터를 지원합니다.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.ink2, height: 1.4),
          ),
          const SizedBox(height: 14),
          Text(tr('PDF 엔진: PDFium (pdfrx) · 화면: Flutter'), style: TextStyle(fontSize: 12, color: context.ink3)),
          const SizedBox(height: 4),
          Text('© 2026 PDF Desk', style: TextStyle(fontSize: 12, color: context.ink3)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'PDF Desk',
          applicationVersion: appVersion,
          applicationIcon: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset('assets/app_icon.png', width: 64, height: 64),
          ),
        ),
        child: Text(tr('오픈 소스 라이선스')),
      ),
      FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('닫기'))),
    ],
  ),
);

/// 사용 설명서: chapters on the left, the chapter on the right.
Future<void> showManual(BuildContext context, {int chapter = 0}) {
  final chapters = manualFor(appLanguage.value);
  var current = chapter.clamp(0, chapters.length - 1);
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final (title, body) = chapters[current];
        return Dialog(
          child: SizedBox(
            width: 900,
            height: 620,
            child: Row(
              children: [
                Material(
                  color: context.palette.sidebar,
                  shape: Border(right: context.hairline),
                  child: SizedBox(
                    width: 230,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                          child: Row(
                            children: [
                              Icon(Icons.menu_book_outlined, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(tr('사용 설명서'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final (i, (t, _)) in chapters.indexed)
                                ListTile(
                                  dense: true,
                                  selected: i == current,
                                  selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                                  title: Text(t, style: const TextStyle(fontSize: 13)),
                                  onTap: () => setState(() => current = i),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                            ),
                            IconButton(
                              tooltip: tr('닫기'),
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                          child: _ManualBody(body),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: current > 0 ? () => setState(() => current--) : null,
                              icon: const Icon(Icons.chevron_left),
                              label: Text(tr('이전')),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: current < chapters.length - 1 ? () => setState(() => current++) : null,
                              icon: const Icon(Icons.chevron_right),
                              label: Text(tr('다음')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Renders the manual's light markup: `## ` subheadings, `- ` bullets,
/// `` `keys` `` and blank-line paragraphs.
class _ManualBody extends StatelessWidget {
  const _ManualBody(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    InlineSpan spans(String line) {
      final parts = line.split('`');
      return TextSpan(
        children: [
          for (final (i, s) in parts.indexed)
            i.isOdd
                ? WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.palette.field,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: context.palette.separator, width: 0.5),
                      ),
                      child: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  )
                : TextSpan(text: s),
        ],
      );
    }

    final out = <Widget>[];
    for (final raw in text.trim().split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        out.add(const SizedBox(height: 8));
      } else if (line.startsWith('## ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              line.substring(3),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: accent),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: TextStyle(color: accent, height: 1.5)),
                Expanded(
                  child: Text.rich(spans(line.substring(2)), style: const TextStyle(height: 1.5, fontSize: 13.5)),
                ),
              ],
            ),
          ),
        );
      } else {
        out.add(Text.rich(spans(line), style: const TextStyle(height: 1.55, fontSize: 13.5)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }
}
