import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_desk/services/desk_controller.dart';
import 'package:pdf_desk/services/settings.dart';
import 'package:pdf_desk/ui/common/app_theme.dart';
import 'package:pdf_desk/ui/desk/desk_actions.dart';
import 'package:pdf_desk/ui/desk/disk_tree.dart';

void main() {
  testWidgets('clicking a drive lists its folders and files', (tester) async {
    late DeskController desk;
    late String home;
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_disk');
      home = tmp.path;
      await Directory(p.join(home, 'Projects')).create();
      await File(p.join(home, 'scan.pdf')).writeAsString('%PDF');
      await File(p.join(home, 'notes.txt')).writeAsString('x');
      desk = DeskController(Settings.at(File(p.join(tmp.path, 's.json')), home));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppTheme.iosLight),
        home: Scaffold(
          body: DiskTree(desk: desk, actions: (c) => DeskActions(c, desk), roots: [('Home', home, Icons.home)]),
        ),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Projects'), findsNothing);

    await tester.tap(find.text('Home'));
    for (var i = 0; i < 20 && find.text('Projects').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing); // only PDFs and images

    // An empty folder says so instead of showing nothing.
    await tester.tap(find.text('Projects'));
    for (var i = 0; i < 20 && find.text('PDF나 이미지 파일이 없습니다').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('PDF나 이미지 파일이 없습니다'), findsOneWidget);
  });

  testWidgets("the computer's own places appear instead of loading forever", (tester) async {
    late DeskController desk;
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('pdfdesk_disk2');
      desk = DeskController(Settings.at(File(p.join(tmp.path, 's.json')), tmp.path));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppTheme.iosLight),
        home: Scaffold(
          body: DiskTree(desk: desk, actions: (c) => DeskActions(c, desk)),
        ),
      ),
    );
    expect(find.text('불러오는 중…'), findsOneWidget);
    for (var i = 0; i < 100 && find.text('불러오는 중…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('불러오는 중…'), findsNothing);
    expect(find.text('/'), findsOneWidget);
  }, skip: Platform.isWindows);
}
