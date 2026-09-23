import 'package:blue_hydrangea/models/garden_models.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:blue_hydrangea/services/mood_statistics.dart';
import 'package:blue_hydrangea/services/mood_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('心情、回忆和视角记录统一最多保存 1500 条', () {
    expect(LocalDatabase.recordLimit, 1500);
  });

  test('纪念日最多保存 100 条', () {
    expect(LocalDatabase.anniversaryLimit, 100);
  });

  test('纪念日当天算第 1 天并自动生成温柔文案', () {
    final anniversary = Anniversary(
      message: '我们在一起',
      date: DateTime(2026, 7, 29),
    );

    expect(anniversary.elapsedDays(DateTime(2026, 7, 29, 23)), 1);
    expect(anniversary.displaySentence(DateTime(2026, 7, 31)), '我们在一起已经3天了');
  });

  test('未来纪念日显示剩余天数，同月同日下一年识别为周年', () {
    final anniversary = Anniversary(
      message: '我们一起去看海',
      date: DateTime(2026, 8, 1),
    );

    expect(anniversary.displaySentence(DateTime(2026, 7, 29)), '距离我们一起去看海还有3天');
    expect(anniversary.isAnniversaryToday(DateTime(2027, 8, 1)), isTrue);
    expect(anniversary.anniversaryYears(DateTime(2027, 8, 1)), 1);
  });

  test('温柔记录可以从数据库字段恢复', () {
    final note = TenderNote.fromMap({
      'id': 1,
      'title': '认真生活的你',
      'content': '一直都很闪光。',
      'date': '2026-07-26T00:00:00.000',
      'image_path': null,
    });

    expect(note.id, 1);
    expect(note.title, '认真生活的你');
    expect(note.date, DateTime(2026, 7, 26));
  });

  test('回忆可以转换为本地存储字段', () {
    final memory = Memory(
      note: '普通的一天，也很幸福。',
      date: DateTime(2026, 7, 26),
      place: '小花园',
    );

    expect(memory.toMap()['place'], '小花园');
    expect(memory.toMap()['date'], contains('2026-07-26'));
  });

  test('回忆内容清空后仍保留日期记录', () {
    final memory = Memory(
      id: 8,
      note: '',
      date: DateTime(2026, 7, 27),
      place: '',
    );

    expect(memory.id, 8);
    expect(memory.toMap()['note'], '');
    expect(memory.toMap()['place'], '');
    expect(memory.toMap()['date'], contains('2026-07-27'));
  });

  test('旧版单张回忆照片会兼容为多图列表', () {
    final memory = Memory.fromMap({
      'id': 9,
      'note': '旧照片也不会走丢。',
      'date': '2026-07-28T00:00:00.000',
      'place': '',
      'image_path': '/garden_images/old.jpg',
    });

    expect(memory.allImagePaths, ['/garden_images/old.jpg']);
    expect(memory.toMap()['image_path'], '/garden_images/old.jpg');
  });

  test('多图回忆保持顺序并将第一张镜像为封面', () {
    final memory = Memory(
      note: '好多张照片的一天。',
      date: DateTime(2026, 7, 29),
      imagePath: '/garden_images/legacy.jpg',
      imagePaths: const [
        '/garden_images/cover.jpg',
        '/garden_images/second.jpg',
        '/garden_images/third.jpg',
      ],
    );

    expect(memory.allImagePaths, [
      '/garden_images/cover.jpg',
      '/garden_images/second.jpg',
      '/garden_images/third.jpg',
    ]);
    expect(memory.toMap()['image_path'], '/garden_images/cover.jpg');
  });

  test('多图路径会保序去重、忽略空值并限制为 20 张', () {
    final paths = [
      '  /garden_images/first.jpg  ',
      '',
      '/garden_images/first.jpg',
      ...List.generate(25, (index) => '/garden_images/$index.jpg'),
    ];

    final normalized = Memory.normalizeImagePaths(paths);

    expect(normalized, hasLength(Memory.maxImages));
    expect(normalized.first, '/garden_images/first.jpg');
    expect(normalized[1], '/garden_images/0.jpg');
    expect(
      () => normalized.add('/garden_images/cannot-add.jpg'),
      throwsUnsupportedError,
    );
  });

  test('心情备注清空后仍可按原记录更新', () {
    final mood = MoodEntry(
      id: 12,
      mood: '普通',
      note: '',
      date: DateTime(2026, 7, 28),
    );

    expect(mood.id, 12);
    expect(mood.toMap()['mood'], '普通');
    expect(mood.toMap()['note'], '');
    expect(mood.toMap()['date'], contains('2026-07-28'));
  });

  test('心情统计按自然周汇总四类心情', () {
    final entries = [
      MoodEntry(mood: '开心', note: '', date: DateTime(2026, 7, 27)),
      MoodEntry(mood: '普通', note: '', date: DateTime(2026, 7, 28)),
      MoodEntry(mood: '开心', note: '', date: DateTime(2026, 7, 31)),
      MoodEntry(mood: '不开心', note: '', date: DateTime(2026, 8, 1)),
      MoodEntry(mood: '有点累', note: '', date: DateTime(2026, 8, 3)),
    ];

    final result = calculateMoodStatistics(
      entries,
      MoodStatisticsPeriod.week,
      DateTime(2026, 7, 30),
    );

    expect(result.start, DateTime(2026, 7, 27));
    expect(result.endExclusive, DateTime(2026, 8, 3));
    expect(result.counts, {'开心': 2, '普通': 1, '有点累': 0, '不开心': 1});
    expect(result.total, 4);
  });

  test('心情统计按自然月汇总且不混入下个月', () {
    final entries = [
      MoodEntry(mood: '开心', note: '', date: DateTime(2026, 7, 1)),
      MoodEntry(mood: '有点累', note: '', date: DateTime(2026, 7, 31, 23)),
      MoodEntry(mood: '不开心', note: '', date: DateTime(2026, 8, 1)),
    ];

    final result = calculateMoodStatistics(
      entries,
      MoodStatisticsPeriod.month,
      DateTime(2026, 7, 28),
    );

    expect(result.start, DateTime(2026, 7));
    expect(result.endExclusive, DateTime(2026, 8));
    expect(result.counts['开心'], 1);
    expect(result.counts['有点累'], 1);
    expect(result.counts['不开心'], 0);
    expect(result.total, 2);
  });

  test('心情时段按真实系统时刻覆盖完整一天', () {
    expect(moodDayPart(DateTime(2026, 7, 28, 4, 59)), '深夜');
    expect(moodDayPart(DateTime(2026, 7, 28, 5)), '清晨');
    expect(moodDayPart(DateTime(2026, 7, 28, 8)), '上午');
    expect(moodDayPart(DateTime(2026, 7, 28, 12)), '中午');
    expect(moodDayPart(DateTime(2026, 7, 28, 14)), '下午');
    expect(moodDayPart(DateTime(2026, 7, 28, 18)), '晚上');
    expect(moodDayPart(DateTime(2026, 7, 28, 23)), '深夜');
    expect(moodTimeLabel(DateTime(2026, 7, 28, 6, 7)), '清晨 06:07');
  });
}
