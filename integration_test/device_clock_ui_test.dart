import 'package:blue_hydrangea/pages/focus_clock_page.dart';
import 'package:blue_hydrangea/services/focus_timer_bridge.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:blue_hydrangea/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('blue_hydrangea/timer_service');

Future<void> settleFrames(WidgetTester tester, [int frames = 16]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).hitTestable().last;
  expect(target, findsOneWidget, reason: 'Visible action: $text');
  await tester.tap(target);
  await settleFrames(tester);
}

Future<void> checkpoint(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  debugPrint('DEVICE_UI_CHECKPOINT $name');
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
}

Finder timerLayout() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_TimerLayout',
);

Future<void> doubleTapDisplay(WidgetTester tester, String label) async {
  final gesture = find.descendant(
    of: timerLayout(),
    matching: find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onDoubleTap != null,
    ),
  );
  expect(gesture, findsOneWidget);
  final display = find
      .descendant(of: gesture, matching: find.byType(FittedBox))
      .first;
  final center = tester.getCenter(display) * tester.view.devicePixelRatio;
  if (const bool.fromEnvironment('STAGE3_PHYSICAL_TAPS')) {
    final previous = tester.binding.shouldPropagateDevicePointerEvents;
    void observe(PointerEvent event) {
      if (event is PointerDownEvent || event is PointerUpEvent) {
        debugPrint(
          'DEVICE_POINTER label=$label type=${event.runtimeType} '
          'timeUs=${event.timeStamp.inMicroseconds} '
          'x=${event.position.dx} y=${event.position.dy}',
        );
      }
    }

    tester.binding.pointerRouter.addGlobalRoute(observe);
    tester.binding.shouldPropagateDevicePointerEvents = true;
    try {
      debugPrint(
        'DEVICE_DOUBLE_TAP x=${center.dx.round()} y=${center.dy.round()} label=$label',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
    } finally {
      tester.binding.shouldPropagateDevicePointerEvents = previous;
      tester.binding.pointerRouter.removeGlobalRoute(observe);
    }
  } else {
    final watch = Stopwatch()..start();
    await tester.tap(display);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.tap(display);
    debugPrint(
      'DEVICE_SYNTHETIC_DOUBLE_TAP label=$label elapsedMs=${watch.elapsedMilliseconds}',
    );
  }
  await settleFrames(tester);
}

Future<Map<Object?, Object?>> timerState() async {
  final result = await _channel.invokeMethod<Object?>('getState');
  return result is Map ? Map<Object?, Object?>.from(result) : {};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    expect(
      (await getApplicationSupportDirectory()).path,
      contains('com.example.blue_hydrangea.stage3test/'),
    );
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const FocusClockPage()),
    );
    await settleFrames(tester, 35);
    expect(
      tester.view.physicalSize.width,
      greaterThan(tester.view.physicalSize.height),
    );
  }

  Future<void> cleanup(WidgetTester tester) async {
    final state = await timerState();
    final session = state['sessionId'];
    if (session is String) {
      await FocusTimerBridge.instance.stopTimer(sessionId: session);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await settleFrames(tester);
  }

  testWidgets(
    'C-01 C-02 repeated fullscreen interactions',
    (tester) async {
      try {
        await open(tester);
        for (final mode in ['正计时', '倒计时', '番茄钟']) {
          await tapText(tester, mode);
          final normalWidth = tester.getSize(timerLayout()).width;
          for (var repeat = 0; repeat < 3; repeat++) {
            await doubleTapDisplay(tester, 'enter-$mode-$repeat');
            expect(
              tester.getSize(timerLayout()).width,
              greaterThan(normalWidth + 40),
            );
            await doubleTapDisplay(tester, 'leave-$mode-$repeat');
            expect(
              tester.getSize(timerLayout()).width,
              closeTo(normalWidth, 2),
            );
          }
        }
        await checkpoint(tester, 'clock-fullscreen-complete');
      } finally {
        await cleanup(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'C-10 repeated inline calendar remains responsive in all timer modes',
    (tester) async {
      try {
        await open(tester);
        for (final mode in ['正计时', '倒计时', '番茄钟']) {
          await tapText(tester, mode);
          await tester.tap(find.byTooltip('看看宝宝的专注成长'));
          await settleFrames(tester);
          for (var repeat = 0; repeat < 3; repeat++) {
            await tapText(tester, '自定义');
            expect(find.byTooltip('关闭日历'), findsOneWidget);
            await tester.tap(find.byTooltip('上个月').last);
            await settleFrames(tester, 5);
            await tester.tap(find.byTooltip('下个月').last);
            await settleFrames(tester, 5);
            await tapText(tester, '近7天');
            if (repeat == 0) {
              await checkpoint(
                tester,
                'calendar-${mode == '正计时'
                    ? 'stopwatch'
                    : mode == '倒计时'
                    ? 'countdown'
                    : 'pomodoro'}',
              );
            }
            await tapText(tester, '看看这段时间');
            expect(find.byTooltip('关闭日历'), findsNothing);
          }
          await tester.tap(find.byTooltip('关闭').last);
          await settleFrames(tester);
          expect(timerLayout(), findsOneWidget);
        }
        await checkpoint(tester, 'clock-calendars-complete');
      } finally {
        await cleanup(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'C-03 stopwatch pause resume classification and single persistence',
    (tester) async {
      final store = LocalDatabase.instance;
      final before = (await store.focusSessions()).map((s) => s.id).toSet();
      try {
        await open(tester);
        await tapText(tester, '正计时');
        final normalWidth = tester.getSize(timerLayout()).width;
        await tapText(tester, '开始');
        expect(
          tester.getSize(timerLayout()).width,
          greaterThan(normalWidth + 40),
        );
        await settleFrames(tester, 20);
        expect((await timerState())['status'], 'running');
        await tapText(tester, '暂停');
        final paused = await timerState();
        expect(paused['status'], 'paused');
        await settleFrames(tester, 20);
        expect((await timerState())['elapsedMs'], paused['elapsedMs']);
        await tapText(tester, '继续');
        expect((await timerState())['status'], 'running');
        await tapText(tester, '结束');
        await tapText(tester, '再专注会儿');
        expect((await timerState())['status'], 'running');
        await tapText(tester, '结束');
        await tapText(tester, '确定结束');
        await tapText(tester, '行测');
        await tapText(tester, '资料');
        await checkpoint(tester, 'stopwatch-classification');
        await tapText(tester, '收好这次努力');
        final added = (await store.focusSessions())
            .where((s) => !before.contains(s.id))
            .toList();
        expect(added, hasLength(1));
        expect(added.single.category, '行测');
        expect(added.single.subcategory, '资料');
        expect(added.single.durationSeconds, greaterThan(0));
        expect(tester.getSize(timerLayout()).width, closeTo(normalWidth, 2));
      } finally {
        await cleanup(tester);
        for (final item in await store.focusSessions()) {
          if (!before.contains(item.id) && item.id != null) {
            await store.deleteFocusSession(item.id!);
          }
        }
      }
    },
  );

  testWidgets(
    'C-04 C-08 countdown custom validation pause early end and silent overtime',
    (tester) async {
      Future<void> configure(String seconds) async {
        await tapText(tester, '自定义');
        for (final entry in {'小时': '0', '分钟': '0', '秒': seconds}.entries) {
          await tester.enterText(
            find.widgetWithText(TextField, entry.key),
            entry.value,
          );
        }
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await settleFrames(tester, 5);
        await tapText(tester, '设定时间');
      }

      try {
        await open(tester);
        await tapText(tester, '倒计时');
        await configure('0');
        expect(find.text('请至少留下一秒钟'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, '秒'), '60');
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tapText(tester, '设定时间');
        expect(find.text('分钟和秒数最多 59，小时最多 99'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, '秒'), '20');
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tapText(tester, '设定时间');
        await tapText(tester, '开始');
        await tapText(tester, '暂停');
        final paused = await timerState();
        expect(paused['status'], 'paused');
        await settleFrames(tester, 15);
        expect((await timerState())['remainingMs'], paused['remainingMs']);
        await tapText(tester, '继续');
        await tapText(tester, '结束');
        await tapText(tester, '其实不是！');
        expect((await timerState())['status'], 'running');
        await tapText(tester, '结束');
        await tapText(tester, '其实是的！');
        await tapText(tester, '这次先不记录');
        await configure('5');
        await tapText(tester, '开始');
        await settleFrames(tester, 65);
        expect(find.text('停叭'), findsOneWidget);
        await tapText(tester, '吵死了！');
        expect((await timerState())['isAlarmActive'], false);
        expect(find.text('搞完了就点这里吧宝宝'), findsOneWidget);
        await checkpoint(tester, 'countdown-silent-overtime');
        await tapText(tester, '搞完了就点这里吧宝宝');
        await tapText(tester, '这次先不记录');
        await checkpoint(tester, 'countdown-reset');
      } finally {
        await cleanup(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets('C-09 pomodoro early completion produces one record', (
    tester,
  ) async {
    final store = LocalDatabase.instance;
    final before = (await store.focusSessions()).map((s) => s.id).toSet();
    try {
      await open(tester);
      await tapText(tester, '番茄钟');
      await tapText(tester, '开始');
      await tapText(tester, '暂停');
      expect((await timerState())['status'], 'paused');
      await tapText(tester, '继续');
      await tapText(tester, '结束');
      await tapText(tester, '结束这轮');
      await tapText(tester, '收好这次努力');
      final added = (await store.focusSessions())
          .where((s) => !before.contains(s.id))
          .toList();
      expect(added, hasLength(1));
      expect(added.single.mode.name, 'pomodoro');
    } finally {
      await cleanup(tester);
      for (final item in await store.focusSessions()) {
        if (!before.contains(item.id) && item.id != null) {
          await store.deleteFocusSession(item.id!);
        }
      }
    }
  });
}
