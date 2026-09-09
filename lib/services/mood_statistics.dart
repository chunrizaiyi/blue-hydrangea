import '../models/garden_models.dart';

enum MoodStatisticsPeriod { week, month }

const moodNames = ['开心', '普通', '有点累', '不开心'];

class MoodPeriodStatistics {
  const MoodPeriodStatistics({
    required this.start,
    required this.endExclusive,
    required this.counts,
  });

  final DateTime start;
  final DateTime endExclusive;
  final Map<String, int> counts;

  int get total => counts.values.fold(0, (sum, count) => sum + count);
}

DateTime moodPeriodStart(DateTime anchor, MoodStatisticsPeriod period) {
  final day = DateTime(anchor.year, anchor.month, anchor.day);
  return switch (period) {
    MoodStatisticsPeriod.week => day.subtract(
      Duration(days: day.weekday - DateTime.monday),
    ),
    MoodStatisticsPeriod.month => DateTime(day.year, day.month),
  };
}

DateTime shiftMoodPeriod(
  DateTime anchor,
  MoodStatisticsPeriod period,
  int amount,
) {
  final start = moodPeriodStart(anchor, period);
  return switch (period) {
    MoodStatisticsPeriod.week => start.add(Duration(days: amount * 7)),
    MoodStatisticsPeriod.month => DateTime(start.year, start.month + amount),
  };
}

MoodPeriodStatistics calculateMoodStatistics(
  List<MoodEntry> entries,
  MoodStatisticsPeriod period,
  DateTime anchor,
) {
  final start = moodPeriodStart(anchor, period);
  final endExclusive = switch (period) {
    MoodStatisticsPeriod.week => start.add(const Duration(days: 7)),
    MoodStatisticsPeriod.month => DateTime(start.year, start.month + 1),
  };
  final counts = {for (final mood in moodNames) mood: 0};
  for (final entry in entries) {
    if (!entry.date.isBefore(start) && entry.date.isBefore(endExclusive)) {
      if (counts.containsKey(entry.mood)) {
        counts[entry.mood] = counts[entry.mood]! + 1;
      }
    }
  }
  return MoodPeriodStatistics(
    start: start,
    endExclusive: endExclusive,
    counts: counts,
  );
}
