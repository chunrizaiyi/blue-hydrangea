import 'dart:async';

import 'package:blue_hydrangea/services/focus_timer_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('blue_hydrangea/timer_service');

Future<Map<Object?, Object?>> _state() async {
  final result = await _channel.invokeMethod<Object?>('getState');
  if (result is! Map) throw StateError('Native timer state is unavailable');
  return Map<Object?, Object?>.from(result);
}

Future<Map<Object?, Object?>> _waitForStatus(String expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 180));
  while (DateTime.now().isBefore(deadline)) {
    final current = await _state();
    if (current['status'] == expected) return current;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TimeoutException('Notification did not change status to $expected');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('C-07 通知栏暂停与继续同步原生计时状态', (tester) async {
    expect(
      (await getApplicationSupportDirectory()).path,
      contains('com.example.blue_hydrangea.stage3test/'),
    );
    expect(
      await _channel.invokeMethod<bool>('ensureNotificationPermission'),
      true,
    );
    expect(
      await _channel.invokeMethod<bool>('ensureExactAlarmPermission'),
      true,
    );

    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final sessionId = 'stage3-actions-$startedAt';
    final snapshot = FocusTimerSnapshot(
      sessionId: sessionId,
      mode: FocusTimerMode.countdown,
      phase: FocusTimerPhase.none,
      status: FocusTimerStatus.running,
      startedAtEpochMs: startedAt,
      endAtEpochMs: startedAt + 600000,
      elapsedMs: 0,
      remainingMs: 600000,
      totalDurationSeconds: 600,
    );

    try {
      expect(await FocusTimerBridge.instance.startTimer(snapshot), true);
      debugPrint('STAGE3_ACTIONS_STARTED session=$sessionId');

      // The host taps the actual notification buttons after each marker.
      final paused = await tester.runAsync(() => _waitForStatus('paused'));
      expect(paused, isNotNull);
      debugPrint(
        'STAGE3_ACTIONS_PAUSED remainingMs=${paused!['remainingMs']} '
        'session=${paused['sessionId']}',
      );
      expect(paused['sessionId'], sessionId);
      final pausedRemaining = (paused['remainingMs'] as num).toInt();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      final stillPaused = await _state();
      expect(stillPaused['status'], 'paused');
      expect(stillPaused['remainingMs'], pausedRemaining);

      final resumed = await tester.runAsync(() => _waitForStatus('running'));
      expect(resumed, isNotNull);
      debugPrint(
        'STAGE3_ACTIONS_RESUMED remainingMs=${resumed!['remainingMs']} '
        'session=${resumed['sessionId']}',
      );
      expect(resumed['sessionId'], sessionId);
      expect(
        (resumed['remainingMs'] as num).toInt(),
        lessThanOrEqualTo(pausedRemaining),
      );
    } finally {
      await FocusTimerBridge.instance.stopTimer(sessionId: sessionId);
      debugPrint('STAGE3_ACTIONS_CLEANUP session=$sessionId');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
