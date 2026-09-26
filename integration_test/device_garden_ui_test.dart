import 'package:blue_hydrangea/main.dart' as app;
import 'package:blue_hydrangea/models/garden_models.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:blue_hydrangea/services/white_noise_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'device_clock_ui_test.dart' show settleFrames, checkpoint;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final store = LocalDatabase.instance;

  setUp(() async {
    expect(
      (await getApplicationSupportDirectory()).path,
      contains('com.example.blue_hydrangea.stage3test/'),
    );
    final db = await store.database;
    await db.transaction((txn) async {
      for (final table in [
        'memory_images',
        'memories',
        'moods',
        'tender_notes',
        'anniversaries',
      ]) {
        await txn.delete(table);
      }
    });
  });

  Future<void> open(WidgetTester tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await tester.pumpWidget(
      const app.BlueHydrangeaApp(showWelcomeGuide: false),
    );
    await settleFrames(tester, 20);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.last);
    await tester.tap(finder.last);
    await settleFrames(tester, 12);
  }

  Future<void> text(WidgetTester tester, String value) =>
      tap(tester, find.text(value));
  Future<void> tip(WidgetTester tester, String value) =>
      tap(tester, find.byTooltip(value));
  Future<void> nav(WidgetTester tester, String value) => tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(value)),
  );

  Future<void> field(WidgetTester tester, String label, String value) async {
    final finder = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settleFrames(tester, 3);
  }

  Future<void> close(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settleFrames(tester, 10);
  }

  testWidgets('H-01 welcome finish skip and persisted bootstrap selection', (
    tester,
  ) async {
    final db = await store.database;
    Future<void> resetGuide() => db.delete(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: ['welcome_guide_v1_completed'],
    );
    try {
      await resetGuide();
      await app.main();
      await settleFrames(tester, 20);
      expect(find.text('跳过'), findsOneWidget);
      await text(tester, '继续');
      await text(tester, '继续');
      await text(tester, '进入我的小花园');
      expect(await store.hasSeenWelcomeGuide(), true);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await app.main();
      await settleFrames(tester, 20);
      expect(find.text('跳过'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await resetGuide();
      await app.main();
      await settleFrames(tester, 20);
      await text(tester, '跳过');
      expect(await store.hasSeenWelcomeGuide(), true);
      expect(find.byType(NavigationBar), findsOneWidget);
      await checkpoint(tester, 'welcome-completed');
    } finally {
      await close(tester);
    }
  });

  testWidgets('H-02 H-03 H-04 navigation quotes and ephemeral phrase input', (
    tester,
  ) async {
    try {
      await open(tester);
      for (final tab in ['我视角下的他', '心语', '回忆', '心情', '花园']) {
        await nav(tester, tab);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (var i = 0; i < 6; i++) {
        await text(tester, '点开一只蝴蝶');
      }
      expect(find.byIcon(Icons.format_quote_rounded), findsOneWidget);
      await text(tester, '今日花语');
      final input = find.byType(TextField).hitTestable();
      await tester.ensureVisible(find.byType(TextField).last);
      await tester.enterText(input.last, '临时测试材料，不发送给在线服务');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await text(tester, '今日花语');
      await text(tester, '今日花语');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      await checkpoint(tester, 'garden-inline-phrase');
    } finally {
      await close(tester);
    }
  });

  testWidgets('N-01 N-02 N-03 note create edit and delete confirmation', (
    tester,
  ) async {
    try {
      await open(tester);
      await nav(tester, '我视角下的他');
      await tip(tester, '记下一件温柔小事');
      await field(tester, '标题', '真机测试标题');
      await field(tester, '我想对你说', '虚构测试内容');
      await text(tester, '收藏这件小事');
      expect(find.text('真机测试标题'), findsOneWidget);
      expect(await store.tenderNotes(), hasLength(1));
      await tip(tester, '修改这条记录');
      await field(tester, '标题', '修改后的测试标题');
      await field(tester, '我想对你说', '修改后的虚构内容');
      await text(tester, '保存修改');
      expect(find.text('修改后的测试标题'), findsOneWidget);
      expect((await store.tenderNotes()).single.content, '修改后的虚构内容');
      await tip(tester, '删除这条记录');
      await text(tester, '先留着');
      expect(await store.tenderNotes(), hasLength(1));
      await tip(tester, '删除这条记录');
      await text(tester, '确认删除');
      expect(await store.tenderNotes(), isEmpty);
      expect(find.text('修改后的测试标题'), findsNothing);
      await checkpoint(tester, 'note-deleted');
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'M-01 M-04 M-06 memory clear optional fields and confirm deletion',
    (tester) async {
      try {
        await open(tester);
        await nav(tester, '回忆');
        await tip(tester, '收藏一段回忆');
        await field(tester, '一句话记录（可以留空）', '真机测试回忆');
        await field(tester, '地点（可以留空）', '虚构地点');
        await text(tester, '收藏这段回忆');
        expect(find.text('真机测试回忆'), findsOneWidget);
        await tip(tester, '修改这段回忆');
        await field(tester, '一句话记录（可以留空）', '');
        await field(tester, '地点（可以留空）', '');
        await text(tester, '保存修改');
        final memories = await store.memories();
        expect(memories, hasLength(1));
        expect(memories.single.note, isEmpty);
        expect(memories.single.place ?? '', isEmpty);
        await tip(tester, '删除这段回忆');
        await text(tester, '先留着');
        expect(await store.memories(), hasLength(1));
        await tip(tester, '删除这段回忆');
        await text(tester, '确认删除');
        expect(await store.memories(), isEmpty);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets(
    'D-01 D-02 D-03 four moods append edit empty and delete confirmation',
    (tester) async {
      try {
        await open(tester);
        await nav(tester, '心情');
        final choices = ['开心', '普通', '有点累', '不开心'];
        for (final mood in choices) {
          await text(tester, mood);
          final entry = find.widgetWithText(TextField, '想留下一句话吗？（可以不写）');
          await tester.ensureVisible(entry);
          final remark = 'stage3-mood-${choices.indexOf(mood)}';
          if (const bool.fromEnvironment('STAGE3_NATIVE_TEXT')) {
            await tester.tap(entry);
            await settleFrames(tester, 5);
            debugPrint('DEVICE_TEXT_INPUT value=$remark');
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 2)),
            );
          } else {
            await tester.enterText(entry, remark);
          }
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await settleFrames(tester, 5);
          expect(
            tester.widget<TextField>(entry).controller!.text,
            remark,
            reason: 'Input must still contain the entered remark before save',
          );
          await text(tester, '新增这条心情');
          final saved = (await store.moods())
              .where((m) => m.mood == mood)
              .single;
          debugPrint('DEVICE_MOOD_SAVED mood=$mood note=${saved.note}');
          expect(saved.note, remark);
        }
        final records = await store.moods();
        expect(records, hasLength(4));
        expect(records.map((item) => item.mood).toSet(), {
          '开心',
          '普通',
          '有点累',
          '不开心',
        });
        await tester.scrollUntilVisible(
          find.byTooltip('修改这条心情').first,
          230,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, find.byTooltip('修改这条心情').first);
        final editor = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '也可以什么都不写。',
        );
        await tester.enterText(editor, '');
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await checkpoint(tester, 'mood-edit-empty');
        await text(tester, '保存修改');
        expect(
          (await store.moods()).where((m) => m.note.isEmpty),
          hasLength(1),
        );
        await tap(tester, find.byTooltip('删除这条心情').first);
        await text(tester, '先留着');
        expect(await store.moods(), hasLength(4));
        await tap(tester, find.byTooltip('删除这条心情').first);
        await text(tester, '确认删除');
        expect(await store.moods(), hasLength(3));
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets('N-03 M-07 D-04 inline today date filters and clearing', (
    tester,
  ) async {
    final today = DateTime.now();
    final past = today.subtract(const Duration(days: 45));
    for (final date in [today, past]) {
      final marker = date == today ? '当天测试记录' : '过去测试记录';
      await store.addTenderNote(
        TenderNote(title: marker, content: '虚构内容', date: date),
      );
      await store.addMemory(Memory(note: marker, date: date));
      await store.saveMood(mood: '开心', note: marker, date: date);
    }
    try {
      await open(tester);
      for (final tab in ['我视角下的他', '回忆', '心情']) {
        await nav(tester, tab);
        await tip(tester, '按日期筛选');
        await text(tester, '今天');
        await text(tester, '查看结果');
        expect(find.text('过去测试记录'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('当天测试记录').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('当天测试记录'), findsWidgets);
        final filter = find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').startsWith('修改日期筛选：'),
        );
        await tap(tester, filter);
        await text(tester, '清除筛选');
        await tester.scrollUntilVisible(
          find.text('过去测试记录').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('过去测试记录'), findsWidgets);
      }
    } finally {
      await close(tester);
    }
  });

  testWidgets('V-01 V-04 V-06 anniversary create reopen and confirm deletion', (
    tester,
  ) async {
    try {
      await open(tester);
      await tip(tester, '我们的纪念日');
      await tip(tester, '添加纪念日');
      await tester.enterText(find.byType(TextField).last, '真机测试纪念日');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await text(tester, '收好这一天');
      expect(await store.anniversaries(), hasLength(1));
      expect(
        (await store.anniversaries()).single.elapsedDays(DateTime.now()),
        1,
      );
      await tip(tester, '关闭');
      await tip(tester, '我们的纪念日');
      expect(find.textContaining('真机测试纪念日'), findsWidgets);
      await checkpoint(tester, 'anniversary-list');
      await tip(tester, '删除这个纪念日');
      await text(tester, '先留着');
      expect(await store.anniversaries(), hasLength(1));
      await tip(tester, '删除这个纪念日');
      await text(tester, '确认删除');
      expect(await store.anniversaries(), isEmpty);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'W-01 W-02 six sound controls and folded playback state',
    (tester) async {
      try {
        await open(tester);
        await text(tester, '陪你安静一会儿');
        for (final sound in WhiteNoiseKind.values) {
          await tap(tester, find.widgetWithText(ChoiceChip, sound.label));
          if (find.byTooltip('播放${sound.label}').evaluate().isNotEmpty) {
            await tip(tester, '播放${sound.label}');
          }
          expect(find.byTooltip('暂停白噪音'), findsOneWidget);
          await settleFrames(tester, 20);
        }
        await text(tester, '陪你安静一会儿');
        await nav(tester, '回忆');
        await nav(tester, '花园');
        await text(tester, '陪你安静一会儿');
        expect(find.byTooltip('暂停白噪音'), findsOneWidget);
        await tip(tester, '暂停白噪音');
        expect(
          find.byTooltip('播放${WhiteNoiseKind.gardenDream.label}'),
          findsOneWidget,
        );
        await checkpoint(tester, 'white-noise-controls');
      } finally {
        await close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
