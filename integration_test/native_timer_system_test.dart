import 'package:blue_hydrangea/services/focus_timer_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _channel = MethodChannel('blue_hydrangea/timer_service');
const _durationSeconds = int.fromEnvironment(
  'STAGE3_TIMER_SECONDS',
  defaultValue: 30,
);

Future<Map<Object?, Object?>> _nativeState() async {
  final value = await _channel.invokeMethod<Object?>('getState');
  if (value is! Map) throw StateError('Native timer state is unavailable');
  return Map<Object?, Object?>.from(value);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'C-05 倒计时在后台及息屏后按系统时间到点',
    (tester) async {
      expect(_durationSeconds, greaterThanOrEqualTo(20));
      // With no active session getState returns an empty map, so inspect
      // permissions only after starting the isolated test session.
      expect(
        await _channel.invokeMethod<bool>('ensureNotificationPermission'),
        true,
      );
      expect(
        await _channel.invokeMethod<bool>('ensureExactAlarmPermission'),
        true,
      );

      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final endAt = startedAt + _durationSeconds * 1000;
      final sessionId = 'stage3-$startedAt';
      final snapshot = FocusTimerSnapshot(
        sessionId: sessionId,
        mode: FocusTimerMode.countdown,
        phase: FocusTimerPhase.none,
        status: FocusTimerStatus.running,
        startedAtEpochMs: startedAt,
        endAtEpochMs: endAt,
        elapsedMs: 0,
        remainingMs: _durationSeconds * 1000,
        totalDurationSeconds: _durationSeconds,
      );

      try {
        expect(await FocusTimerBridge.instance.startTimer(snapshot), true);
        final running = await _nativeState();
        debugPrint(
          'STAGE3_PERMISSIONS '
          'notification=${running['notificationPermissionGranted']} '
          'exactAlarm=${running['exactAlarmAvailable']} '
          'promoted=${running['promotedNotificationsAvailable']}',
        );
        expect(running['notificationPermissionGranted'], true);
        expect(running['exactAlarmAvailable'], true);
        expect(running['status'], 'running');
        expect(running['sessionId'], sessionId);
        debugPrint(
          'STAGE3_STARTED session=$sessionId plannedEndMs=$endAt '
          'durationSeconds=$_durationSeconds',
        );

        // The host turns the screen off after STAGE3_STARTED. Native
        // completion time is persisted by the service and does not depend
        // on this Dart wait being scheduled.
        await tester.runAsync(() async {
          await Future<void>.delayed(
            const Duration(seconds: _durationSeconds + 12),
          );
        });

        final completed = await _nativeState();
        final completedAt = completed['completedAtEpochMs'];
        final errorMs = completedAt is num ? completedAt.toInt() - endAt : null;
        debugPrint(
          'STAGE3_COMPLETED status=${completed['status']} '
          'completedAtMs=$completedAt errorMs=$errorMs '
          'alarmActive=${completed['isAlarmActive']}',
        );
        expect(completed['status'], 'overtime');
        expect(errorMs, isNotNull);
        expect(errorMs!.abs(), lessThanOrEqualTo(10000));
      } finally {
        await FocusTimerBridge.instance.stopTimer(sessionId: sessionId);
        debugPrint('STAGE3_CLEANUP session=$sessionId');
      }
    },
    timeout: const Timeout(Duration(seconds: _durationSeconds + 90)),
  );
}
