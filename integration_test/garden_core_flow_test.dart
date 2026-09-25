import 'package:blue_hydrangea/main.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('阶段二：回忆与心情新增后立即展示，切换页面后数据仍在', (tester) async {
    const memoryMarker = '阶段二虚构回忆样本-20260924';
    const moodMarker = '阶段二虚构心情样本-20260924';
    final store = LocalDatabase.instance;
    await store.database;

    try {
      await tester.pumpWidget(const BlueHydrangeaApp(showWelcomeGuide: false));
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.text('回忆').last);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('我们的回忆'), findsOneWidget);
      await tester.tap(find.byTooltip('收藏一段回忆'));
      await tester.pump(const Duration(milliseconds: 800));
      final memoryField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == '一句话记录（可以留空）',
      );
      await tester.enterText(memoryField, memoryMarker);
      final saveMemory = find.text('收藏这段回忆').last;
      await tester.ensureVisible(saveMemory);
      await tester.tap(saveMemory);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text(memoryMarker), findsWidgets);

      await tester.tap(find.text('心情').last);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('今天的心情'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, '想留下一句话吗？（可以不写）'),
        moodMarker,
      );
      await tester.tap(find.text('新增这条心情'));
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        (await store.moods()).where((item) => item.note == moodMarker),
        hasLength(1),
      );
      await tester.scrollUntilVisible(
        find.text(moodMarker),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(moodMarker), findsWidgets);

      await tester.tap(find.text('回忆').last);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text(memoryMarker), findsWidgets);
      expect(
        (await store.memories()).where((item) => item.note == memoryMarker),
        hasLength(1),
      );
      expect(
        (await store.moods()).where((item) => item.note == moodMarker),
        hasLength(1),
      );
    } finally {
      for (final item in await store.memories()) {
        if (item.note == memoryMarker && item.id != null) {
          await store.deleteMemory(item.id!);
        }
      }
      for (final item in await store.moods()) {
        if (item.note == moodMarker && item.id != null) {
          await store.deleteMood(item.id!);
        }
      }
    }
  });
}
