class GentleQuote {
  const GentleQuote({required this.text, required this.category});

  final String text;
  final String category;

  factory GentleQuote.fromJson(Map<String, dynamic> json) {
    return GentleQuote(
      text: json['text'] as String,
      category: json['category'] as String,
    );
  }
}

class TenderNote {
  const TenderNote({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    this.imagePath,
  });

  final int? id;
  final String title;
  final String content;
  final DateTime date;
  final String? imagePath;

  factory TenderNote.fromMap(Map<String, Object?> map) => TenderNote(
    id: map['id'] as int?,
    title: map['title'] as String,
    content: map['content'] as String,
    date: DateTime.parse(map['date'] as String),
    imagePath: map['image_path'] as String?,
  );

  Map<String, Object?> toMap() => {
    'title': title,
    'content': content,
    'date': date.toIso8601String(),
    'image_path': imagePath,
  };
}

class Memory {
  const Memory({
    this.id,
    required this.note,
    required this.date,
    this.place,
    this.imagePath,
    this.imagePaths = const [],
  });

  static const maxImages = 20;

  final int? id;
  final String note;
  final DateTime date;
  final String? place;

  /// Kept for backward compatibility with databases created before v7.
  final String? imagePath;
  final List<String> imagePaths;

  static List<String> normalizeImagePaths(Iterable<String> paths) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final path in paths) {
      final value = path.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      normalized.add(value);
      if (normalized.length == maxImages) break;
    }
    return List<String>.unmodifiable(normalized);
  }

  List<String> get allImagePaths {
    if (imagePaths.isNotEmpty) return normalizeImagePaths(imagePaths);
    final legacyPath = imagePath;
    return legacyPath == null || legacyPath.isEmpty
        ? const []
        : normalizeImagePaths([legacyPath]);
  }

  factory Memory.fromMap(Map<String, Object?> map) => Memory(
    id: map['id'] as int?,
    note: map['note'] as String,
    date: DateTime.parse(map['date'] as String),
    place: map['place'] as String?,
    imagePath: map['image_path'] as String?,
    imagePaths: List<String>.unmodifiable(
      (map['image_paths'] as Iterable<Object?>? ?? const [])
          .whereType<String>()
          .where((path) => path.isNotEmpty),
    ),
  );

  Map<String, Object?> toMap() {
    final paths = allImagePaths;
    return {
      'note': note,
      'date': date.toIso8601String(),
      'place': place,
      // Mirroring the cover keeps the row readable by older app versions while
      // v7 stores the complete ordered gallery in memory_images.
      'image_path': paths.isEmpty ? null : paths.first,
    };
  }
}

class MoodEntry {
  const MoodEntry({
    this.id,
    required this.mood,
    required this.note,
    required this.date,
  });

  final int? id;
  final String mood;
  final String note;
  final DateTime date;

  factory MoodEntry.fromMap(Map<String, Object?> map) => MoodEntry(
    id: map['id'] as int?,
    mood: map['mood'] as String,
    note: map['note'] as String,
    date: DateTime.parse(map['date'] as String),
  );

  Map<String, Object?> toMap() => {
    'mood': mood,
    'note': note,
    'date': date.toIso8601String(),
  };
}

class Anniversary {
  const Anniversary({this.id, required this.message, required this.date});

  final int? id;
  final String message;
  final DateTime date;

  factory Anniversary.fromMap(Map<String, Object?> map) => Anniversary(
    id: map['id'] as int?,
    message: map['message'] as String,
    date: DateTime.parse(map['date'] as String),
  );

  Map<String, Object?> toMap() => {
    'message': message,
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
  };

  int elapsedDays(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    return today.difference(eventDay).inDays + 1;
  }

  String displaySentence(DateTime now) {
    final days = elapsedDays(now);
    if (days > 0) return '$message已经$days天了';
    return '距离$message还有${1 - days}天';
  }

  bool isAnniversaryToday(DateTime now) {
    return date.year < now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  int anniversaryYears(DateTime now) => now.year - date.year;
}

enum FocusSessionMode { stopwatch, countdown, pomodoro }

FocusSessionMode focusSessionModeFromStorage(String value) {
  return FocusSessionMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => FocusSessionMode.stopwatch,
  );
}

class FocusSession {
  const FocusSession({
    this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.mode,
    required this.category,
    this.subcategory,
    this.targetDurationSeconds,
    this.sessionKey,
  }) : assert(durationSeconds >= 0),
       assert(targetDurationSeconds == null || targetDurationSeconds > 0);

  static const categories = ['行测', '申论', '专注'];
  static const aptitudeSubcategories = ['言语', '资料', '判断', '数量', '时政'];

  final int? id;
  final DateTime startedAt;
  final int durationSeconds;
  final FocusSessionMode mode;
  final String category;
  final String? subcategory;
  final int? targetDurationSeconds;
  final String? sessionKey;

  DateTime get endedAt => startedAt.add(Duration(seconds: durationSeconds));

  bool get hasCountdownTarget => targetDurationSeconds != null;

  bool get reachedCountdownTarget =>
      targetDurationSeconds != null &&
      durationSeconds >= targetDurationSeconds!;

  int get extraDurationSeconds {
    final target = targetDurationSeconds;
    if (target == null || durationSeconds <= target) return 0;
    return durationSeconds - target;
  }

  factory FocusSession.fromMap(Map<String, Object?> map) => FocusSession(
    id: map['id'] as int?,
    startedAt: DateTime.parse(map['started_at'] as String),
    durationSeconds: map['duration_seconds'] as int,
    mode: focusSessionModeFromStorage(map['mode'] as String),
    category: map['category'] as String,
    subcategory: map['subcategory'] as String?,
    targetDurationSeconds: map['target_duration_seconds'] as int?,
    sessionKey: map['session_key'] as String?,
  );

  Map<String, Object?> toMap() => {
    'started_at': startedAt.toIso8601String(),
    'duration_seconds': durationSeconds,
    'mode': mode.name,
    'category': category,
    'subcategory': _normalizedSubcategory,
    'target_duration_seconds': targetDurationSeconds,
    'session_key': _normalizedSessionKey,
  };

  String? get _normalizedSubcategory {
    final value = subcategory?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get _normalizedSessionKey {
    final value = sessionKey?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
