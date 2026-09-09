import 'package:blue_hydrangea/services/focus_timer_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native timer snapshot preserves completed focus base for today', () {
    const snapshot = FocusTimerSnapshot(
      sessionId: 'countdown-1',
      mode: FocusTimerMode.countdown,
      phase: FocusTimerPhase.none,
      status: FocusTimerStatus.running,
      startedAtEpochMs: 1785751200000,
      endAtEpochMs: 1785752700000,
      elapsedMs: 0,
      remainingMs: 1500000,
      totalDurationSeconds: 1500,
      todayAccumulatedMs: 5400000,
    );

    expect(snapshot.toMap()['todayAccumulatedMs'], 5400000);
    expect(
      FocusTimerSnapshot.fromMap(snapshot.toMap()).todayAccumulatedMs,
      5400000,
    );
  });

  test('negative native today base is safely normalized to zero', () {
    final restored = FocusTimerSnapshot.fromMap(const {
      'sessionId': 'stopwatch-1',
      'mode': 'stopwatch',
      'phase': 'none',
      'status': 'paused',
      'startedAtEpochMs': 1785751200000,
      'elapsedMs': 300000,
      'remainingMs': 0,
      'totalDurationSeconds': 0,
      'todayAccumulatedMs': -1,
    });

    expect(restored.todayAccumulatedMs, 0);
  });
}
