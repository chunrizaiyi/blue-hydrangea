import 'package:blue_hydrangea/theme/app_theme.dart';
import 'package:blue_hydrangea/widgets/garden_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'device_clock_ui_test.dart' show settleFrames, checkpoint;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in ['reverse', 'same-day', 'fixed-start', 'reselect']) {
    testWidgets('N-03 M-07 D-04 date range $scenario', (tester) async {
      final now = DateTime.now();
      DateTime day(int number) => DateTime(now.year, now.month, number);
      GardenDateFilterSelection? result;
      final initial = scenario == 'fixed-start' || scenario == 'reselect'
          ? DateTimeRange(start: day(5), end: day(15))
          : null;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showGardenDateFilterPopup(context, initial);
                  },
                  child: const Text('打开测试筛选'),
                ),
              ),
            ),
          ),
        ),
      );
      await settleFrames(tester);
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder.last);
        await tester.tap(finder.last);
        await settleFrames(tester, 6);
      }

      Future<void> select(int number) => tap(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').startsWith(
                '${now.year}年${now.month}月$number日',
              ),
        ),
      );
      try {
        await tap(find.text('打开测试筛选'));
        await tap(find.text(initial == null ? '开始日期' : '结束日期'));
        switch (scenario) {
          case 'reverse':
            await select(15);
            await select(5);
          case 'same-day':
            await select(12);
            await select(12);
          case 'fixed-start':
            await select(20);
          case 'reselect':
            await select(20);
            await tap(find.text('结束日期'));
            await select(3);
            await select(4);
        }
        if (scenario == 'reverse') {
          await checkpoint(tester, 'date-range-reverse');
        }
        await tap(find.text('查看结果'));
        expect(result?.range, isNotNull);
        final expected = switch (scenario) {
          'reverse' => (5, 15),
          'same-day' => (12, 12),
          'fixed-start' => (5, 20),
          _ => (3, 4),
        };
        expect(result!.range!.start, day(expected.$1));
        expect(result!.range!.end, day(expected.$2));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleFrames(tester, 5);
      }
    });
  }
}
