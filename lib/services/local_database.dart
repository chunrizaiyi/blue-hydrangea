import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/garden_models.dart';

class LocalDatabase {
  LocalDatabase._();

  static final instance = LocalDatabase._();
  static const int databaseVersion = 7;
  static const int recordLimit = 1500;
  static const int anniversaryLimit = 100;
  Future<Database>? _databaseFuture;

  /// Keep the in-flight open operation as well as the opened database.
  ///
  /// Several pages are created together by [AppShell] and can request data in
  /// the same frame. Caching only the resolved [Database] allows those calls to
  /// race and open the same file more than once. A shared future makes database
  /// initialization single-flight.
  Future<Database> get database => _databaseFuture ??= _openWithRetryReset();

  Future<Database> _openWithRetryReset() async {
    try {
      return await _open();
    } catch (_) {
      // A transient storage failure should be retryable on the next page load
      // instead of pinning one failed future for the rest of the process.
      _databaseFuture = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, 'blue_hydrangea.db'),
      version: databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tender_notes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            date TEXT NOT NULL,
            image_path TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE letters(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            content TEXT NOT NULL,
            date TEXT NOT NULL,
            image_path TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE memories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note TEXT NOT NULL,
            date TEXT NOT NULL,
            place TEXT,
            image_path TEXT
          )
        ''');
        await _createMemoryImagesTable(db);
        await db.execute('''
          CREATE TABLE moods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mood TEXT NOT NULL,
            note TEXT NOT NULL,
            date TEXT NOT NULL
          )
        ''');
        await _createAnniversariesTable(db);
        await _createFocusSessionsTable(db);
        await _createSettingsTable(db);
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _removeBuiltInTenderNotes(db);
        }
        if (oldVersion < 3) {
          await _createSettingsTable(db);
        }
        if (oldVersion < 4) {
          await _createAnniversariesTable(db);
        }
        if (oldVersion < 5) {
          await _createFocusSessionsTable(db);
        } else if (oldVersion < 6) {
          await _upgradeFocusSessionsToV6(db);
        }
        if (oldVersion < 7) {
          await _createMemoryImagesTable(db);
          await _migrateLegacyMemoryImages(db);
        }
      },
    );
  }

  static Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings(
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createAnniversariesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS anniversaries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createMemoryImagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_images(
        memory_id INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL CHECK(sort_order >= 0),
        PRIMARY KEY(memory_id, sort_order),
        UNIQUE(memory_id, image_path),
        FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _migrateLegacyMemoryImages(Database db) async {
    await db.execute('''
      INSERT OR IGNORE INTO memory_images(memory_id, image_path, sort_order)
      SELECT id, image_path, 0
      FROM memories
      WHERE image_path IS NOT NULL AND TRIM(image_path) <> ''
    ''');
  }

  static Future<void> _createFocusSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS focus_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL CHECK(duration_seconds >= 0),
        mode TEXT NOT NULL,
        category TEXT NOT NULL,
        subcategory TEXT,
        target_duration_seconds INTEGER
          CHECK(target_duration_seconds IS NULL OR target_duration_seconds > 0),
        session_key TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS focus_sessions_started_at_index
      ON focus_sessions(started_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS focus_sessions_category_index
      ON focus_sessions(category, subcategory)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS focus_sessions_session_key_unique_index
      ON focus_sessions(session_key)
    ''');
  }

  static Future<void> _upgradeFocusSessionsToV6(Database db) async {
    await db.execute('''
      ALTER TABLE focus_sessions
      ADD COLUMN target_duration_seconds INTEGER
        CHECK(target_duration_seconds IS NULL OR target_duration_seconds > 0)
    ''');
    await db.execute('''
      ALTER TABLE focus_sessions
      ADD COLUMN session_key TEXT
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS focus_sessions_session_key_unique_index
      ON focus_sessions(session_key)
    ''');
  }

  static Future<void> _removeBuiltInTenderNotes(Database db) async {
    await db.delete(
      'tender_notes',
      where: '''
        (title = ? AND content = ?)
        OR (title = ? AND content = ?)
      ''',
      whereArgs: const [
        '你认真努力的时候',
        '我喜欢你认真做事情的样子。虽然你有时候会怀疑自己，但在我眼里，你一直都很闪光。',
        '你笑起来的时候',
        '那一刻周围好像都安静下来，只剩下我想把你的笑好好记住。',
      ],
    );
  }

  Future<List<TenderNote>> tenderNotes() async {
    final db = await database;
    final rows = await db.query(
      'tender_notes',
      orderBy: 'date DESC',
      limit: recordLimit,
    );
    return rows.map(TenderNote.fromMap).toList();
  }

  Future<bool> addTenderNote(TenderNote note) async {
    final db = await database;
    return _insertWithinLimit(db, 'tender_notes', note.toMap());
  }

  Future<void> updateTenderNote(TenderNote note) async {
    if (note.id == null) return;
    final db = await database;
    await db.update(
      'tender_notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteTenderNote(int id) async {
    final db = await database;
    await db.delete('tender_notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> hasSeenWelcomeGuide() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['welcome_guide_v1_completed'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['setting_value'] == 'true';
  }

  Future<void> markWelcomeGuideSeen() async {
    final db = await database;
    await db.insert('app_settings', {
      'setting_key': 'welcome_guide_v1_completed',
      'setting_value': 'true',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Letter>> lettersFor(String category) async {
    final db = await database;
    final rows = await db.query(
      'letters',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'date DESC',
    );
    return rows.map(Letter.fromMap).toList();
  }

  Future<List<Memory>> memories() async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'memories',
        orderBy: 'date DESC, id DESC',
        limit: recordLimit,
      );
      if (rows.isEmpty) return const <Memory>[];
      final imageRows = await transaction.rawQuery('''
        SELECT memory_id, image_path
        FROM memory_images
        ORDER BY memory_id, sort_order
      ''');
      final imagesByMemory = <int, List<String>>{};
      for (final imageRow in imageRows) {
        final memoryId = imageRow['memory_id'] as int;
        final path = imageRow['image_path'] as String;
        (imagesByMemory[memoryId] ??= []).add(path);
      }
      return rows
          .map(
            (row) => Memory.fromMap({
              ...row,
              'image_paths':
                  imagesByMemory[row['id'] as int] ?? const <String>[],
            }),
          )
          .toList(growable: false);
    });
  }

  Future<bool> addMemory(Memory memory) async {
    final db = await database;
    return db.transaction((transaction) async {
      final count = Sqflite.firstIntValue(
        await transaction.rawQuery('SELECT COUNT(*) FROM memories'),
      );
      if ((count ?? 0) >= recordLimit) return false;
      final memoryId = await transaction.insert('memories', memory.toMap());
      await _replaceMemoryImages(transaction, memoryId, memory.allImagePaths);
      return true;
    });
  }

  Future<void> updateMemory(Memory memory) async {
    if (memory.id == null) return;
    final db = await database;
    await db.transaction((transaction) async {
      final updated = await transaction.update(
        'memories',
        memory.toMap(),
        where: 'id = ?',
        whereArgs: [memory.id],
      );
      if (updated != 1) {
        throw StateError('Cannot update missing memory ${memory.id}');
      }
      await _replaceMemoryImages(transaction, memory.id!, memory.allImagePaths);
    });
  }

  Future<void> deleteMemory(int id) async {
    final db = await database;
    await db.transaction((transaction) async {
      // Delete explicitly as well as declaring ON DELETE CASCADE because some
      // older Android SQLite builds open databases with foreign keys disabled.
      await transaction.delete(
        'memory_images',
        where: 'memory_id = ?',
        whereArgs: [id],
      );
      await transaction.delete('memories', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Memory?> memoryById(int id) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        'memories',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final imageRows = await transaction.query(
        'memory_images',
        columns: const ['image_path'],
        where: 'memory_id = ?',
        whereArgs: [id],
        orderBy: 'sort_order',
      );
      return Memory.fromMap({
        ...rows.single,
        'image_paths': imageRows
            .map((row) => row['image_path'] as String)
            .toList(growable: false),
      });
    });
  }

  static Future<void> _replaceMemoryImages(
    DatabaseExecutor executor,
    int memoryId,
    List<String> imagePaths,
  ) async {
    await executor.delete(
      'memory_images',
      where: 'memory_id = ?',
      whereArgs: [memoryId],
    );
    final normalized = Memory.normalizeImagePaths(imagePaths);
    for (final indexed in normalized.indexed) {
      await executor.insert('memory_images', {
        'memory_id': memoryId,
        'image_path': indexed.$2,
        'sort_order': indexed.$1,
      });
    }
  }

  Future<List<MoodEntry>> moods() async {
    final db = await database;
    final rows = await db.query(
      'moods',
      orderBy: 'date DESC, id DESC',
      limit: recordLimit,
    );
    return rows.map(MoodEntry.fromMap).toList();
  }

  Future<bool> saveMood({
    required String mood,
    required String note,
    required DateTime date,
  }) async {
    final db = await database;
    final values = {'mood': mood, 'note': note, 'date': date.toIso8601String()};
    return _insertWithinLimit(db, 'moods', values);
  }

  Future<bool> _insertWithinLimit(
    Database db,
    String table,
    Map<String, Object?> values,
  ) {
    return db.transaction((transaction) async {
      final rows = await transaction.rawQuery('SELECT COUNT(*) FROM $table');
      final count = Sqflite.firstIntValue(rows) ?? 0;
      if (count >= recordLimit) return false;
      await transaction.insert(table, values);
      return true;
    });
  }

  Future<void> updateMood(MoodEntry entry) async {
    if (entry.id == null) return;
    final db = await database;
    await db.update(
      'moods',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteMood(int id) async {
    final db = await database;
    await db.delete('moods', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Anniversary>> anniversaries() async {
    final db = await database;
    final rows = await db.query(
      'anniversaries',
      orderBy: 'date ASC, id ASC',
      limit: anniversaryLimit,
    );
    return rows.map(Anniversary.fromMap).toList();
  }

  Future<bool> addAnniversary(Anniversary anniversary) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        'SELECT COUNT(*) FROM anniversaries',
      );
      final count = Sqflite.firstIntValue(rows) ?? 0;
      if (count >= anniversaryLimit) return false;
      await transaction.insert('anniversaries', anniversary.toMap());
      return true;
    });
  }

  Future<void> deleteAnniversary(int id) async {
    final db = await database;
    await db.delete('anniversaries', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FocusSession>> focusSessions({
    DateTime? start,
    DateTime? endExclusive,
    FocusSessionMode? mode,
    String? category,
    String? subcategory,
  }) async {
    if (start != null &&
        endExclusive != null &&
        !start.isBefore(endExclusive)) {
      return const [];
    }

    final db = await database;
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (start != null) {
      whereParts.add('started_at >= ?');
      whereArgs.add(start.toIso8601String());
    }
    if (endExclusive != null) {
      whereParts.add('started_at < ?');
      whereArgs.add(endExclusive.toIso8601String());
    }
    if (mode != null) {
      whereParts.add('mode = ?');
      whereArgs.add(mode.name);
    }
    final normalizedCategory = category?.trim();
    if (normalizedCategory != null && normalizedCategory.isNotEmpty) {
      whereParts.add('category = ?');
      whereArgs.add(normalizedCategory);
    }
    final normalizedSubcategory = subcategory?.trim();
    if (normalizedSubcategory != null && normalizedSubcategory.isNotEmpty) {
      whereParts.add('subcategory = ?');
      whereArgs.add(normalizedSubcategory);
    }

    final rows = await db.query(
      'focus_sessions',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'started_at DESC, id DESC',
      limit: recordLimit,
    );
    return rows.map(FocusSession.fromMap).toList();
  }

  /// Returns true when the record was inserted, or when a record with the same
  /// non-empty session key already exists. The latter makes retries from the
  /// foreground UI and Android background timer idempotent. Returns false only
  /// for invalid data or when the 1500-record limit blocks a new insertion.
  Future<bool> addFocusSession(FocusSession session) async {
    if (session.durationSeconds < 0 ||
        session.category.trim().isEmpty ||
        (session.targetDurationSeconds != null &&
            session.targetDurationSeconds! <= 0)) {
      return false;
    }
    final db = await database;
    final values = session.toMap();
    final sessionKey = values['session_key'] as String?;
    return db.transaction((transaction) async {
      if (sessionKey != null) {
        final existing = await transaction.query(
          'focus_sessions',
          columns: const ['id'],
          where: 'session_key = ?',
          whereArgs: [sessionKey],
          limit: 1,
        );
        if (existing.isNotEmpty) return true;
      }

      final rows = await transaction.rawQuery(
        'SELECT COUNT(*) FROM focus_sessions',
      );
      final count = Sqflite.firstIntValue(rows) ?? 0;
      if (count >= recordLimit) return false;

      final insertedId = await transaction.insert(
        'focus_sessions',
        values,
        conflictAlgorithm: sessionKey == null
            ? ConflictAlgorithm.abort
            : ConflictAlgorithm.ignore,
      );
      if (insertedId != 0) return true;

      if (sessionKey == null) return false;
      final existing = await transaction.query(
        'focus_sessions',
        columns: const ['id'],
        where: 'session_key = ?',
        whereArgs: [sessionKey],
        limit: 1,
      );
      return existing.isNotEmpty;
    });
  }

  Future<void> deleteFocusSession(int id) async {
    final db = await database;
    await db.delete('focus_sessions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _seed(Database db) async {
    final now = DateTime.now();
    const letters = {
      '今天有点累': '如果今天很辛苦，就不要再责怪自己了。你已经做得很好了。累的时候，就先在这里歇一会儿。',
      '今天想被安慰': '不用把所有情绪都解释清楚。我会先抱抱你，再慢慢听你说。',
      '今天有点委屈': '你的委屈不是小题大做。那些让你难过的瞬间，都值得被认真听见。',
      '今天想你了': '我也在想你。思念像一只蓝色蝴蝶，已经先一步飞到了你身边。',
      '今天只是想看看你写的话': '谢谢你点开这里。今天没有特别的理由，只是依然很认真地喜欢你。',
    };
    for (final entry in letters.entries) {
      await db.insert('letters', {
        'category': entry.key,
        'content': entry.value,
        'date': now.toIso8601String(),
      });
    }

    await db.insert('memories', {
      'note': '那天一起吃饭，很普通，但我觉得很幸福。',
      'date': DateTime(now.year, now.month, 1).toIso8601String(),
      'place': '我们喜欢的小店',
    });
  }
}
