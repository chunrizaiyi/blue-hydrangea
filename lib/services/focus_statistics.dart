import '../models/garden_models.dart';

enum FocusStatisticsPeriod { today, week, month, custom }

/// Returns the completed, persisted focus time belonging to one local
/// calendar day. Sessions crossing midnight contribute only their overlap
/// with that day.
int completedFocusSecondsForDay(
  Iterable<FocusSession> sessions,
  DateTime day, {
  String? excludingSessionKey,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  final excludedKey = excludingSessionKey?.trim();
  var accumulatedMilliseconds = 0;

  for (final session in sessions) {
    if (session.durationSeconds <= 0 ||
        (excludedKey != null &&
            excludedKey.isNotEmpty &&
            session.sessionKey == excludedKey)) {
      continue;
    }

    final sessionStart = session.startedAt;
    final sessionEnd = session.endedAt;
    if (!sessionStart.isBefore(dayEnd) || !sessionEnd.isAfter(dayStart)) {
      continue;
    }
    final overlapStart = sessionStart.isAfter(dayStart)
        ? sessionStart
        : dayStart;
    final overlapEnd = sessionEnd.isBefore(dayEnd) ? sessionEnd : dayEnd;
    accumulatedMilliseconds += overlapEnd
        .difference(overlapStart)
        .inMilliseconds;
  }

  return Duration(milliseconds: accumulatedMilliseconds).inSeconds;
}

class FocusSessionFilter {
  const FocusSessionFilter({this.mode, this.category, this.subcategory});

  final FocusSessionMode? mode;
  final String? category;
  final String? subcategory;

  bool matches(FocusSession session) {
    if (mode != null && session.mode != mode) return false;
    if (category != null && session.category != category) return false;
    if (subcategory != null && session.subcategory != subcategory) return false;
    return true;
  }
}

class FocusStatisticsRange {
  FocusStatisticsRange({
    required DateTime start,
    required DateTime endExclusive,
  }) : start = _dateOnly(start),
       endExclusive = _dateOnly(endExclusive) {
    if (!this.start.isBefore(this.endExclusive)) {
      throw ArgumentError.value(endExclusive, 'endExclusive', '必须晚于 start');
    }
  }

  final DateTime start;
  final DateTime endExclusive;

  int get dayCount => _dayNumber(endExclusive) - _dayNumber(start);

  bool contains(DateTime value) {
    return !value.isBefore(start) && value.isBefore(endExclusive);
  }

  FocusStatisticsRange get previous => FocusStatisticsRange(
    start: _addCalendarDays(start, -dayCount),
    endExclusive: start,
  );
}

class FocusAggregate {
  const FocusAggregate({
    required this.durationSeconds,
    required this.sessionCount,
  });

  final int durationSeconds;
  final int sessionCount;

  Duration get duration => Duration(seconds: durationSeconds);

  double get averageSecondsPerSession =>
      sessionCount == 0 ? 0 : durationSeconds / sessionCount;
}

class FocusCountdownSummary extends FocusAggregate {
  const FocusCountdownSummary({
    required super.durationSeconds,
    required super.sessionCount,
    required this.assessedSessionCount,
    required this.achievedSessionCount,
    required this.plannedDurationSeconds,
    required this.extraDurationSeconds,
  });

  /// Records with a valid target. This is kept separate from [sessionCount] so
  /// rows created by an older build can remain visible without lowering the
  /// achievement rate when their target is unknown.
  final int assessedSessionCount;
  final int achievedSessionCount;
  final int plannedDurationSeconds;
  final int extraDurationSeconds;

  int get earlyEndedSessionCount => assessedSessionCount - achievedSessionCount;

  int get unassessedSessionCount => sessionCount - assessedSessionCount;

  /// A value from 0 to 1. Returns 0 when no countdown has an assessable target.
  double get achievementRate => assessedSessionCount == 0
      ? 0
      : achievedSessionCount / assessedSessionCount;
}

class FocusCategorySummary extends FocusAggregate {
  const FocusCategorySummary({
    required this.category,
    required super.durationSeconds,
    required super.sessionCount,
    required this.subcategories,
  });

  final String category;
  final Map<String, FocusAggregate> subcategories;
}

class FocusPeriodComparison {
  const FocusPeriodComparison({
    required this.currentDurationSeconds,
    required this.previousDurationSeconds,
    required this.currentSessionCount,
    required this.previousSessionCount,
  });

  final int currentDurationSeconds;
  final int previousDurationSeconds;
  final int currentSessionCount;
  final int previousSessionCount;

  int get durationDifferenceSeconds =>
      currentDurationSeconds - previousDurationSeconds;

  int get sessionCountDifference => currentSessionCount - previousSessionCount;

  /// 相比上一等长周期的百分比；上一周期为 0 时返回 null，方便界面显示
  /// “这是新的开始”，避免展示无意义的无穷大百分比。
  double? get durationChangePercent => previousDurationSeconds == 0
      ? null
      : durationDifferenceSeconds / previousDurationSeconds * 100;

  double? get sessionCountChangePercent => previousSessionCount == 0
      ? null
      : sessionCountDifference / previousSessionCount * 100;

  bool get isNewStart =>
      previousDurationSeconds == 0 && currentDurationSeconds > 0;
}

class FocusStatisticsResult {
  const FocusStatisticsResult({
    required this.range,
    required this.previousRange,
    required this.totalDurationSeconds,
    required this.sessionCount,
    required this.averageSecondsPerDay,
    required this.averageSecondsPerSession,
    required this.dailySummaries,
    required this.categorySummaries,
    required this.modeSummaries,
    required this.countdownSummary,
    required this.comparison,
    required this.currentStreakDays,
    required this.longestStreakDays,
  });

  final FocusStatisticsRange range;
  final FocusStatisticsRange previousRange;
  final int totalDurationSeconds;
  final int sessionCount;
  final double averageSecondsPerDay;
  final double averageSecondsPerSession;

  /// 包含所选周期中的每个自然日；没有记录的日期也会以 0 填充，便于画图。
  final Map<DateTime, FocusAggregate> dailySummaries;
  final Map<String, FocusCategorySummary> categorySummaries;
  final Map<FocusSessionMode, FocusAggregate> modeSummaries;
  final FocusCountdownSummary countdownSummary;
  final FocusPeriodComparison comparison;

  /// 截至 anchor 当天（当天尚未专注时允许延续至昨天）的连续天数。
  final int currentStreakDays;
  final int longestStreakDays;

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
}

FocusStatisticsRange focusStatisticsRange(
  FocusStatisticsPeriod period,
  DateTime anchor, {
  DateTime? customStart,
  DateTime? customEndInclusive,
}) {
  final day = _dateOnly(anchor);
  switch (period) {
    case FocusStatisticsPeriod.today:
      return FocusStatisticsRange(
        start: day,
        endExclusive: _addCalendarDays(day, 1),
      );
    case FocusStatisticsPeriod.week:
      final start = _addCalendarDays(day, -(day.weekday - DateTime.monday));
      return FocusStatisticsRange(
        start: start,
        endExclusive: _addCalendarDays(start, 7),
      );
    case FocusStatisticsPeriod.month:
      return FocusStatisticsRange(
        start: DateTime(day.year, day.month),
        endExclusive: DateTime(day.year, day.month + 1),
      );
    case FocusStatisticsPeriod.custom:
      if (customStart == null || customEndInclusive == null) {
        throw ArgumentError('自定义统计需要同时提供开始和结束日期');
      }
      var start = _dateOnly(customStart);
      var end = _dateOnly(customEndInclusive);
      if (end.isBefore(start)) {
        final temporary = start;
        start = end;
        end = temporary;
      }
      return FocusStatisticsRange(
        start: start,
        endExclusive: _addCalendarDays(end, 1),
      );
  }
}

FocusStatisticsResult calculateFocusStatistics(
  Iterable<FocusSession> sessions,
  FocusStatisticsPeriod period,
  DateTime anchor, {
  DateTime? customStart,
  DateTime? customEndInclusive,
  FocusSessionFilter filter = const FocusSessionFilter(),
}) {
  final range = focusStatisticsRange(
    period,
    anchor,
    customStart: customStart,
    customEndInclusive: customEndInclusive,
  );
  final previousRange = range.previous;
  final filtered = sessions.where(filter.matches).toList(growable: false);
  final current = filtered.where((entry) => range.contains(entry.startedAt));
  final previous = filtered.where(
    (entry) => previousRange.contains(entry.startedAt),
  );

  final daily = <DateTime, _MutableAggregate>{};
  for (var offset = 0; offset < range.dayCount; offset += 1) {
    daily[_addCalendarDays(range.start, offset)] = _MutableAggregate();
  }

  final categories = <String, _MutableCategorySummary>{
    for (final category in FocusSession.categories)
      category: _MutableCategorySummary(category),
  };
  for (final subcategory in FocusSession.aptitudeSubcategories) {
    categories['行测']!.subcategories[subcategory] = _MutableAggregate();
  }
  final modes = <FocusSessionMode, _MutableAggregate>{
    for (final mode in FocusSessionMode.values) mode: _MutableAggregate(),
  };
  final countdown = _MutableCountdownSummary();

  var totalDurationSeconds = 0;
  var sessionCount = 0;
  for (final entry in current) {
    totalDurationSeconds += entry.durationSeconds;
    sessionCount += 1;

    final date = _dateOnly(entry.startedAt);
    daily[date]?.add(entry.durationSeconds);
    modes[entry.mode]!.add(entry.durationSeconds);
    if (entry.mode == FocusSessionMode.countdown) countdown.add(entry);

    final category = categories.putIfAbsent(
      entry.category,
      () => _MutableCategorySummary(entry.category),
    );
    category.total.add(entry.durationSeconds);
    final subcategory = entry.subcategory?.trim();
    if (subcategory != null && subcategory.isNotEmpty) {
      category.subcategories
          .putIfAbsent(subcategory, _MutableAggregate.new)
          .add(entry.durationSeconds);
    }
  }

  var previousDurationSeconds = 0;
  var previousSessionCount = 0;
  for (final entry in previous) {
    previousDurationSeconds += entry.durationSeconds;
    previousSessionCount += 1;
  }

  final streaks = _calculateStreaks(filtered, anchor);
  return FocusStatisticsResult(
    range: range,
    previousRange: previousRange,
    totalDurationSeconds: totalDurationSeconds,
    sessionCount: sessionCount,
    averageSecondsPerDay: totalDurationSeconds / range.dayCount,
    averageSecondsPerSession: sessionCount == 0
        ? 0
        : totalDurationSeconds / sessionCount,
    dailySummaries: Map.unmodifiable({
      for (final entry in daily.entries) entry.key: entry.value.freeze(),
    }),
    categorySummaries: Map.unmodifiable({
      for (final entry in categories.entries) entry.key: entry.value.freeze(),
    }),
    modeSummaries: Map.unmodifiable({
      for (final entry in modes.entries) entry.key: entry.value.freeze(),
    }),
    countdownSummary: countdown.freeze(),
    comparison: FocusPeriodComparison(
      currentDurationSeconds: totalDurationSeconds,
      previousDurationSeconds: previousDurationSeconds,
      currentSessionCount: sessionCount,
      previousSessionCount: previousSessionCount,
    ),
    currentStreakDays: streaks.current,
    longestStreakDays: streaks.longest,
  );
}

class _MutableAggregate {
  int durationSeconds = 0;
  int sessionCount = 0;

  void add(int seconds) {
    durationSeconds += seconds;
    sessionCount += 1;
  }

  FocusAggregate freeze() => FocusAggregate(
    durationSeconds: durationSeconds,
    sessionCount: sessionCount,
  );
}

class _MutableCategorySummary {
  _MutableCategorySummary(this.category);

  final String category;
  final total = _MutableAggregate();
  final subcategories = <String, _MutableAggregate>{};

  FocusCategorySummary freeze() => FocusCategorySummary(
    category: category,
    durationSeconds: total.durationSeconds,
    sessionCount: total.sessionCount,
    subcategories: Map.unmodifiable({
      for (final entry in subcategories.entries)
        entry.key: entry.value.freeze(),
    }),
  );
}

class _MutableCountdownSummary {
  final total = _MutableAggregate();
  int assessedSessionCount = 0;
  int achievedSessionCount = 0;
  int plannedDurationSeconds = 0;
  int extraDurationSeconds = 0;

  void add(FocusSession session) {
    total.add(session.durationSeconds);
    final target = session.targetDurationSeconds;
    if (target == null) return;

    assessedSessionCount += 1;
    plannedDurationSeconds += target;
    if (session.durationSeconds >= target) achievedSessionCount += 1;
    extraDurationSeconds += session.extraDurationSeconds;
  }

  FocusCountdownSummary freeze() => FocusCountdownSummary(
    durationSeconds: total.durationSeconds,
    sessionCount: total.sessionCount,
    assessedSessionCount: assessedSessionCount,
    achievedSessionCount: achievedSessionCount,
    plannedDurationSeconds: plannedDurationSeconds,
    extraDurationSeconds: extraDurationSeconds,
  );
}

({int current, int longest}) _calculateStreaks(
  Iterable<FocusSession> sessions,
  DateTime anchor,
) {
  final anchorDay = _dayNumber(_dateOnly(anchor));
  final activeDays = sessions
      .where((session) => session.durationSeconds > 0)
      .map((session) => _dayNumber(_dateOnly(session.startedAt)))
      .where((day) => day <= anchorDay)
      .toSet();
  if (activeDays.isEmpty) return (current: 0, longest: 0);

  final sortedDays = activeDays.toList()..sort();
  var longest = 1;
  var run = 1;
  for (var index = 1; index < sortedDays.length; index += 1) {
    if (sortedDays[index] == sortedDays[index - 1] + 1) {
      run += 1;
      if (run > longest) longest = run;
    } else {
      run = 1;
    }
  }

  var cursor = activeDays.contains(anchorDay)
      ? anchorDay
      : activeDays.contains(anchorDay - 1)
      ? anchorDay - 1
      : null;
  var current = 0;
  while (cursor != null && activeDays.contains(cursor)) {
    current += 1;
    cursor -= 1;
  }
  return (current: current, longest: longest);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addCalendarDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

int _dayNumber(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;
