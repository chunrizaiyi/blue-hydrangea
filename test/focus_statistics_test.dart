import 'package:blue_hydrangea/models/garden_models.dart';
import 'package:blue_hydrangea/services/focus_statistics.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('专注记录可无损转换为数据库字段', () {
    final session = FocusSession(
      id: 8,
      startedAt: DateTime(2026, 7, 29, 9, 30),
      durationSeconds: 3661,
      mode: FocusSessionMode.stopwatch,
      category: '行测',
      subcategory: ' 言语 ',
    );

    final restored = FocusSession.fromMap({...session.toMap(), 'id': 8});
    expect(restored.id, 8);
    expect(restored.startedAt, DateTime(2026, 7, 29, 9, 30));
    expect(restored.durationSeconds, 3661);
    expect(restored.mode, FocusSessionMode.stopwatch);
    expect(restored.category, '行测');
    expect(restored.subcategory, '言语');
    expect(restored.endedAt, DateTime(2026, 7, 29, 10, 31, 1));
  });

  test('空细分类存为 null，未知旧模式安全回退为正计时', () {
    final restored = FocusSession.fromMap({
      'id': 1,
      'started_at': '2026-07-29T12:00:00.000',
      'duration_seconds': 60,
      'mode': 'legacy_mode',
      'category': '专注',
      'subcategory': null,
    });
    final session = FocusSession(
      startedAt: DateTime(2026, 7, 29),
      durationSeconds: 60,
      mode: FocusSessionMode.pomodoro,
      category: '申论',
      subcategory: '   ',
    );

    expect(restored.mode, FocusSessionMode.stopwatch);
    expect(restored.targetDurationSeconds, isNull);
    expect(restored.sessionKey, isNull);
    expect(session.toMap()['subcategory'], isNull);
    expect(session.toMap()['session_key'], isNull);
  });

  test('倒计时计划与幂等键可无损转换，并可推导达成和额外坚持', () {
    final session = FocusSession(
      id: 9,
      startedAt: DateTime(2026, 8, 3, 8),
      durationSeconds: 1680,
      mode: FocusSessionMode.countdown,
      category: '行测',
      subcategory: '资料',
      targetDurationSeconds: 1500,
      sessionKey: ' countdown-20260803-0800 ',
    );

    final map = session.toMap();
    final restored = FocusSession.fromMap({...map, 'id': 9});

    expect(map['session_key'], 'countdown-20260803-0800');
    expect(restored.mode, FocusSessionMode.countdown);
    expect(restored.targetDurationSeconds, 1500);
    expect(restored.sessionKey, 'countdown-20260803-0800');
    expect(restored.hasCountdownTarget, isTrue);
    expect(restored.reachedCountdownTarget, isTrue);
    expect(restored.extraDurationSeconds, 180);
  });

  test('数据库升级版本和专注记录上限固定', () {
    expect(LocalDatabase.databaseVersion, 8);
    expect(LocalDatabase.recordLimit, 1500);
  });

  test('今天、自然周、自然月与反向自定义日期都能生成正确范围', () {
    final anchor = DateTime(2026, 7, 29, 23, 59);

    final today = focusStatisticsRange(FocusStatisticsPeriod.today, anchor);
    final week = focusStatisticsRange(FocusStatisticsPeriod.week, anchor);
    final month = focusStatisticsRange(FocusStatisticsPeriod.month, anchor);
    final custom = focusStatisticsRange(
      FocusStatisticsPeriod.custom,
      anchor,
      customStart: DateTime(2026, 7, 31),
      customEndInclusive: DateTime(2026, 7, 29),
    );

    expect(today.start, DateTime(2026, 7, 29));
    expect(today.endExclusive, DateTime(2026, 7, 30));
    expect(week.start, DateTime(2026, 7, 27));
    expect(week.endExclusive, DateTime(2026, 8, 3));
    expect(month.start, DateTime(2026, 7));
    expect(month.endExclusive, DateTime(2026, 8));
    expect(custom.start, DateTime(2026, 7, 29));
    expect(custom.endExclusive, DateTime(2026, 8, 1));
  });

  test('周统计返回总量、均值、每日、分类和上一等长周期变化', () {
    final sessions = [
      _session(DateTime(2026, 7, 27, 9), 3600, '行测', '言语'),
      _session(
        DateTime(2026, 7, 27, 14),
        1800,
        '行测',
        '资料',
        mode: FocusSessionMode.pomodoro,
      ),
      _session(DateTime(2026, 7, 29, 20), 1200, '专注', null),
      _session(DateTime(2026, 7, 20, 9), 1800, '行测', '判断'),
      _session(DateTime(2026, 7, 26, 9), 600, '申论', null),
      _session(DateTime(2026, 8, 3), 9999, '专注', null),
    ];

    final result = calculateFocusStatistics(
      sessions,
      FocusStatisticsPeriod.week,
      DateTime(2026, 7, 29),
    );

    expect(result.totalDurationSeconds, 6600);
    expect(result.sessionCount, 3);
    expect(result.averageSecondsPerDay, closeTo(6600 / 7, 0.001));
    expect(result.averageSecondsPerSession, 2200);
    expect(result.dailySummaries.length, 7);
    expect(result.dailySummaries[DateTime(2026, 7, 27)]!.durationSeconds, 5400);
    expect(result.dailySummaries[DateTime(2026, 7, 28)]!.sessionCount, 0);
    expect(result.categorySummaries['行测']!.durationSeconds, 5400);
    expect(
      result.categorySummaries['行测']!.subcategories['言语']!.durationSeconds,
      3600,
    );
    expect(result.categorySummaries['申论']!.durationSeconds, 0);
    expect(
      result.modeSummaries[FocusSessionMode.stopwatch]!.durationSeconds,
      4800,
    );
    expect(
      result.modeSummaries[FocusSessionMode.pomodoro]!.durationSeconds,
      1800,
    );
    expect(
      result.modeSummaries[FocusSessionMode.countdown]!.durationSeconds,
      0,
    );
    expect(result.countdownSummary.sessionCount, 0);
    expect(result.comparison.previousDurationSeconds, 2400);
    expect(result.comparison.durationDifferenceSeconds, 4200);
    expect(result.comparison.durationChangePercent, 175);
  });

  test('模式与分类筛选同时影响统计和连续专注天数', () {
    final sessions = [
      _session(
        DateTime(2026, 7, 26),
        1200,
        '行测',
        '言语',
        mode: FocusSessionMode.pomodoro,
      ),
      _session(
        DateTime(2026, 7, 27),
        1200,
        '行测',
        '言语',
        mode: FocusSessionMode.pomodoro,
      ),
      _session(
        DateTime(2026, 7, 28),
        1200,
        '行测',
        '资料',
        mode: FocusSessionMode.pomodoro,
      ),
      _session(
        DateTime(2026, 7, 29),
        1200,
        '行测',
        '言语',
        mode: FocusSessionMode.stopwatch,
      ),
    ];

    final result = calculateFocusStatistics(
      sessions,
      FocusStatisticsPeriod.week,
      DateTime(2026, 7, 28),
      filter: const FocusSessionFilter(
        mode: FocusSessionMode.pomodoro,
        category: '行测',
        subcategory: '言语',
      ),
    );

    expect(result.totalDurationSeconds, 1200);
    expect(result.sessionCount, 1);
    expect(result.currentStreakDays, 2);
    expect(result.longestStreakDays, 2);
  });

  test('连续天数允许今天未记录时延续昨天，最长连续另行保留', () {
    final sessions = [
      _session(DateTime(2026, 7, 20), 60, '专注', null),
      _session(DateTime(2026, 7, 21), 60, '专注', null),
      _session(DateTime(2026, 7, 22), 60, '专注', null),
      _session(DateTime(2026, 7, 23), 60, '专注', null),
      _session(DateTime(2026, 7, 27), 60, '专注', null),
      _session(DateTime(2026, 7, 28), 60, '专注', null),
      _session(DateTime(2026, 7, 29), 60, '专注', null),
    ];

    final result = calculateFocusStatistics(
      sessions,
      FocusStatisticsPeriod.month,
      DateTime(2026, 7, 30),
    );

    expect(result.currentStreakDays, 3);
    expect(result.longestStreakDays, 4);
  });

  test('倒计时统计区分总数、可评估数、达成率与额外坚持', () {
    final sessions = [
      _session(
        DateTime(2026, 7, 27, 8),
        1200,
        '行测',
        '言语',
        mode: FocusSessionMode.countdown,
        targetDurationSeconds: 1500,
      ),
      _session(
        DateTime(2026, 7, 28, 8),
        1500,
        '行测',
        '资料',
        mode: FocusSessionMode.countdown,
        targetDurationSeconds: 1500,
      ),
      _session(
        DateTime(2026, 7, 29, 8),
        1740,
        '专注',
        null,
        mode: FocusSessionMode.countdown,
        targetDurationSeconds: 1500,
      ),
      _session(
        DateTime(2026, 7, 29, 12),
        600,
        '专注',
        null,
        mode: FocusSessionMode.countdown,
      ),
      _session(DateTime(2026, 7, 29, 14), 3600, '申论', null),
    ];

    final all = calculateFocusStatistics(
      sessions,
      FocusStatisticsPeriod.week,
      DateTime(2026, 7, 29),
    );
    final countdownOnly = calculateFocusStatistics(
      sessions,
      FocusStatisticsPeriod.week,
      DateTime(2026, 7, 29),
      filter: const FocusSessionFilter(mode: FocusSessionMode.countdown),
    );

    expect(
      all.modeSummaries[FocusSessionMode.countdown]!.durationSeconds,
      5040,
    );
    expect(all.modeSummaries[FocusSessionMode.countdown]!.sessionCount, 4);
    expect(
      all.modeSummaries[FocusSessionMode.stopwatch]!.durationSeconds,
      3600,
    );
    expect(countdownOnly.totalDurationSeconds, 5040);
    expect(countdownOnly.sessionCount, 4);
    expect(countdownOnly.countdownSummary.sessionCount, 4);
    expect(countdownOnly.countdownSummary.assessedSessionCount, 3);
    expect(countdownOnly.countdownSummary.unassessedSessionCount, 1);
    expect(countdownOnly.countdownSummary.achievedSessionCount, 2);
    expect(countdownOnly.countdownSummary.earlyEndedSessionCount, 1);
    expect(
      countdownOnly.countdownSummary.achievementRate,
      closeTo(2 / 3, 0.001),
    );
    expect(countdownOnly.countdownSummary.plannedDurationSeconds, 4500);
    expect(countdownOnly.countdownSummary.extraDurationSeconds, 240);
  });

  test('completed focus for today includes all modes and clips midnight', () {
    final sessions = [
      _session(DateTime(2026, 8, 2, 23, 50), 1200, '专注', null),
      _session(
        DateTime(2026, 8, 3, 8),
        1500,
        '行测',
        '资料',
        mode: FocusSessionMode.countdown,
      ),
      _session(
        DateTime(2026, 8, 3, 10),
        1500,
        '专注',
        null,
        mode: FocusSessionMode.pomodoro,
      ),
      _session(DateTime(2026, 8, 4), 3600, '申论', null),
    ];

    expect(
      completedFocusSecondsForDay(sessions, DateTime(2026, 8, 3, 21)),
      3600,
    );
  });

  test('completed focus excludes restored current session key', () {
    final sessions = [
      FocusSession(
        startedAt: DateTime(2026, 8, 3, 9),
        durationSeconds: 600,
        mode: FocusSessionMode.stopwatch,
        category: '专注',
        sessionKey: 'restored-session',
      ),
      FocusSession(
        startedAt: DateTime(2026, 8, 3, 10),
        durationSeconds: 900,
        mode: FocusSessionMode.countdown,
        category: '专注',
        sessionKey: 'completed-session',
      ),
    ];

    expect(
      completedFocusSecondsForDay(
        sessions,
        DateTime(2026, 8, 3),
        excludingSessionKey: 'restored-session',
      ),
      900,
    );
  });
}

FocusSession _session(
  DateTime startedAt,
  int durationSeconds,
  String category,
  String? subcategory, {
  FocusSessionMode mode = FocusSessionMode.stopwatch,
  int? targetDurationSeconds,
}) {
  return FocusSession(
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    mode: mode,
    category: category,
    subcategory: subcategory,
    targetDurationSeconds: targetDurationSeconds,
  );
}
