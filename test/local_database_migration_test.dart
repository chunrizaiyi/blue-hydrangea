import 'dart:io';

import 'package:blue_hydrangea/models/garden_models.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hydrangea-db-test-');
    path = '${directory.path}${Platform.pathSeparator}isolated.db';
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('M-08/D-07 旧版单图回忆、心情与专注记录升级后完整保留', () async {
    final old = await openDatabase(
      path,
      version: 5,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE memories(id INTEGER PRIMARY KEY AUTOINCREMENT, note TEXT NOT NULL, date TEXT NOT NULL, place TEXT, image_path TEXT)',
        );
        await db.execute(
          'CREATE TABLE moods(id INTEGER PRIMARY KEY AUTOINCREMENT, mood TEXT NOT NULL, note TEXT NOT NULL, date TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE tender_notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, content TEXT NOT NULL, date TEXT NOT NULL, image_path TEXT)',
        );
        await db.execute(
          'CREATE TABLE anniversaries(id INTEGER PRIMARY KEY AUTOINCREMENT, message TEXT NOT NULL, date TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE app_settings(setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE focus_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, started_at TEXT NOT NULL, duration_seconds INTEGER NOT NULL, mode TEXT NOT NULL, category TEXT NOT NULL, subcategory TEXT)',
        );
        await db.execute(
          'CREATE TABLE letters(id INTEGER PRIMARY KEY, content TEXT)',
        );
        await db.insert('memories', {
          'note': '测试回忆',
          'date': '2025-01-02T12:00:00.000',
          'place': '测试地点',
          'image_path': '/isolated/photo.jpg',
        });
        await db.insert('moods', {
          'mood': '开心',
          'note': '虚构的备注',
          'date': '2025-01-02T12:00:00.000',
        });
        await db.insert('focus_sessions', {
          'started_at': '2025-01-02T12:00:00.000',
          'duration_seconds': 600,
          'mode': 'stopwatch',
          'category': '专注',
        });
      },
    );
    await old.close();

    final upgraded = await LocalDatabase.openAtPath(path);
    expect(await upgraded.getVersion(), LocalDatabase.databaseVersion);
    final memories = await upgraded.query('memories');
    final images = await upgraded.query('memory_images');
    final moods = await upgraded.query('moods');
    final sessions = await upgraded.query('focus_sessions');
    expect(memories, hasLength(1));
    expect(images, hasLength(1));
    expect(images.single['image_path'], '/isolated/photo.jpg');
    expect(images.single['sort_order'], 0);
    expect(moods.single['note'], '虚构的备注');
    expect(sessions.single['duration_seconds'], 600);
    expect(sessions.single['target_duration_seconds'], isNull);
    expect(sessions.single['session_key'], isNull);
    expect(
      await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='letters'",
      ),
      isEmpty,
    );
    await upgraded.close();
  });

  test('v7 多图升级到 v8 不重复迁移，原有顺序与其余数据保持不变', () async {
    final old = await openDatabase(
      path,
      version: 7,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE memories(id INTEGER PRIMARY KEY, note TEXT NOT NULL, date TEXT NOT NULL, place TEXT, image_path TEXT)',
        );
        await db.execute(
          'CREATE TABLE memory_images(memory_id INTEGER NOT NULL, image_path TEXT NOT NULL, sort_order INTEGER NOT NULL, PRIMARY KEY(memory_id, sort_order))',
        );
        await db.execute(
          'CREATE TABLE letters(id INTEGER PRIMARY KEY, content TEXT)',
        );
        await db.insert('memories', {
          'id': 7,
          'note': '多图测试',
          'date': '2025-01-02T12:00:00.000',
          'image_path': '/isolated/a.jpg',
        });
        await db.insert('memory_images', {
          'memory_id': 7,
          'image_path': '/isolated/a.jpg',
          'sort_order': 0,
        });
        await db.insert('memory_images', {
          'memory_id': 7,
          'image_path': '/isolated/b.jpg',
          'sort_order': 1,
        });
      },
    );
    await old.close();
    final db = await LocalDatabase.openAtPath(path);
    final imageRows = await db.query('memory_images', orderBy: 'sort_order');
    expect(imageRows.map((row) => row['image_path']), [
      '/isolated/a.jpg',
      '/isolated/b.jpg',
    ]);
    expect(await db.query('memories'), hasLength(1));
    await db.close();
  });

  test('M-01/M-04/M-06 纯文字与多图回忆可新增、修改、删除并持久化', () async {
    final store = LocalDatabase.atPath(path);
    final date = DateTime(2025, 1, 2);
    expect(
      await store.addMemory(Memory(note: '测试文字', date: date, place: '花园')),
      isTrue,
    );
    var records = (await store.memories())
        .where((memory) => memory.note == '测试文字')
        .toList();
    expect(records, hasLength(1));
    final id = records.single.id!;
    await store.updateMemory(
      Memory(
        id: id,
        note: '修改后的文字',
        date: date,
        imagePaths: const ['/isolated/a.jpg', '/isolated/b.jpg'],
      ),
    );
    final loaded = await store.memoryById(id);
    expect(loaded?.note, '修改后的文字');
    expect(loaded?.allImagePaths, ['/isolated/a.jpg', '/isolated/b.jpg']);
    await (await store.database).close();
    final reopened = LocalDatabase.atPath(path);
    expect((await reopened.memoryById(id))?.allImagePaths, [
      '/isolated/a.jpg',
      '/isolated/b.jpg',
    ]);
    await reopened.deleteMemory(id);
    expect(await reopened.memoryById(id), isNull);
    expect(
      await (await reopened.database).query(
        'memory_images',
        where: 'memory_id = ?',
        whereArgs: [id],
      ),
      isEmpty,
    );
    await (await reopened.database).close();
  });

  test('D-01/D-02/D-03 心情新增、空备注修改与删除不会覆盖相邻记录', () async {
    final store = LocalDatabase.atPath(path);
    final date = DateTime(2025, 1, 2);
    expect(await store.saveMood(mood: '开心', note: '第一条', date: date), isTrue);
    expect(await store.saveMood(mood: '普通', note: '第二条', date: date), isTrue);
    final entries = await store.moods();
    expect(entries, hasLength(2));
    final first = entries.singleWhere((entry) => entry.note == '第一条');
    await store.updateMood(
      MoodEntry(id: first.id, mood: first.mood, note: '', date: first.date),
    );
    expect(
      (await store.moods()).singleWhere((entry) => entry.id == first.id).note,
      isEmpty,
    );
    await store.deleteMood(first.id!);
    final remaining = await store.moods();
    expect(remaining, hasLength(1));
    expect(remaining.single.note, '第二条');
    await (await store.database).close();
  });

  test('专注记录重复 session_key 只写入一条', () async {
    final store = LocalDatabase.atPath(path);
    final entry = FocusSession(
      startedAt: DateTime(2025, 1, 2),
      durationSeconds: 600,
      mode: FocusSessionMode.countdown,
      category: '专注',
      targetDurationSeconds: 600,
      sessionKey: 'isolated-123',
    );
    expect(await store.addFocusSession(entry), isTrue);
    expect(await store.addFocusSession(entry), isTrue);
    expect(
      (await store.focusSessions()).where(
        (item) => item.sessionKey == 'isolated-123',
      ),
      hasLength(1),
    );
    await (await store.database).close();
  });
}
