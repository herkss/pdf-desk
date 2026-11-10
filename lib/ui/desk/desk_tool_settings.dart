import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/desk_controller.dart';
import '../../services/flatten.dart' show exportEditData;
import '../../services/pdf_ops.dart' as ops;
import '../../services/settings.dart';
import '../common/app_theme.dart';
import '../common/popover.dart';

/// The desk toolbar's buttons that have settings (right-click).
enum DeskTool { import, stack, spread, export, print, delete, arrange, preview }

/// Applies settings that live outside the widgets (import and export).
void applyDeskSettings(Settings s) {
  ops.importImagesFitA4 = s.imageFit == 'a4';
  exportEditData = s.exportEditable;
}

/// Right-click on a desk toolbar button: how that function behaves.
Future<void> showDeskToolSettings(
  BuildContext context,
  Settings s,
  DeskController desk,
  DeskTool tool,
  Rect anchor, {
  required VoidCallback onChanged,
  VoidCallback? onPrinterSetup,
}) {
  final title = switch (tool) {
    DeskTool.import => tr('가져오기 설정'),
    DeskTool.stack => tr('겹치기 설정'),
    DeskTool.spread => tr('펼치기 설정'),
    DeskTool.export => tr('PDF 내보내기 설정'),
    DeskTool.print => tr('인쇄 설정'),
    DeskTool.delete => tr('삭제 설정'),
    DeskTool.arrange => tr('정렬 설정'),
    DeskTool.preview => tr('미리보기 설정'),
  };
  return showPopover(
    context,
    anchor: anchor,
    title: title,
    builder: (context, setState) {
      void change(void Function() f) {
        f();
        applyDeskSettings(s);
        s.save();
        onChanged();
        setState(() {});
      }

      Widget note(String text) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: context.ink3, height: 1.4)),
      );

      final body = switch (tool) {
        DeskTool.import => [
          popRow(
            context,
            tr('이미지'),
            popChoices<String>(
              {'a4': tr('A4 용지에 맞춤'), 'original': tr('원래 크기')},
              s.imageFit,
              (v) => change(() => s.imageFit = v),
            ),
          ),
          note(tr('jpg·png 같은 이미지를 가져오면 PDF로 바뀝니다. 원래 크기는 96dpi 기준입니다.')),
        ],
        DeskTool.stack => [
          Text(tr('문서를 다른 문서 위에 놓으면'), style: TextStyle(fontSize: 12.5, color: context.ink2)),
          const SizedBox(height: 6),
          popChoices<String>(
            {'stack': tr('바로 겹치기'), 'ask': tr('어떻게 할지 묻기'), 'place': tr('위에 놓기만')},
            s.dropAction,
            (v) => change(() => s.dropAction = v),
          ),
          note(tr('놓을 때 Shift: 위에 놓기만, Ctrl: 복사')),
        ],
        DeskTool.spread => [
          popSwitch(context, tr('원본 문서 남겨 두기'), s.spreadKeepsOriginal, (v) => change(() => s.spreadKeepsOriginal = v)),
          note(tr('끄면 원본이 낱장으로 바뀌고, 켜면 원본은 그대로 두고 낱장을 새로 만듭니다.')),
        ],
        DeskTool.export => [
          popSwitch(context, tr('다시 고칠 수 있게 편집 정보 넣기'), s.exportEditable, (v) => change(() => s.exportEditable = v)),
          note(tr('켜 두면 내보낸 PDF를 다시 데스크로 가져올 때 주석을 고칠 수 있습니다. 다른 프로그램에서는 똑같이 보입니다.')),
        ],
        DeskTool.print => [
          Text(tr('PDF Desk 프린터로 인쇄한 문서는'), style: TextStyle(fontSize: 12.5, color: context.ink2)),
          const SizedBox(height: 6),
          popChoices<bool>(
            {false: tr('한 문서로 놓기'), true: tr('낱장으로 펼쳐 놓기')},
            s.spreadPrinted,
            (v) => change(() => s.spreadPrinted = v),
          ),
          if (onPrinterSetup != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onPrinterSetup();
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text(tr("'PDF Desk' 프린터 설치/설정…")),
            ),
          ],
        ],
        DeskTool.delete => [
          popSwitch(context, tr('휴지통으로 옮기기'), s.deleteToTrash, (v) => change(() => s.deleteToTrash = v)),
          popSwitch(context, tr('삭제하기 전에 묻기'), s.confirmDelete, (v) => change(() => s.confirmDelete = v)),
          note(tr('휴지통을 끄면 바로 영구히 삭제되며, 이때는 항상 묻습니다.')),
        ],
        DeskTool.arrange => [
          popRow(
            context,
            tr('기준'),
            popChoices<String>(
              {'name': tr('이름순'), 'modified': tr('수정일순'), 'size': tr('크기순')},
              s.arrangeBy,
              (v) => change(() => s.arrangeBy = v),
            ),
          ),
          popRow(
            context,
            tr('순서'),
            popChoices<bool>(
              {false: tr('기본'), true: tr('거꾸로')},
              s.arrangeDescending,
              (v) => change(() => s.arrangeDescending = v),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              arrangeDesk(desk, s);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.grid_view, size: 18),
            label: Text(tr('지금 정렬')),
          ),
        ],
        DeskTool.preview => [
          popSwitch(context, tr('마우스 휠로 페이지 넘기기'), s.previewWheelPages, (v) => change(() => s.previewWheelPages = v)),
        ],
      };
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body);
    },
  );
}

/// 정렬 with the settings' order.
Future<void> arrangeDesk(DeskController desk, Settings s) => desk.arrange(switch (s.arrangeBy) {
  'modified' => SortMode.modified,
  'size' => SortMode.size,
  _ => SortMode.name,
}, descending: s.arrangeDescending);
