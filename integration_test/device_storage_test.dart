import 'dart:convert';
import 'dart:io';

import 'package:blue_hydrangea/models/garden_models.dart';
import 'package:blue_hydrangea/services/local_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late Directory support;
  setUpAll(() async {
    support = await getApplicationSupportDirectory();
    // Abort before any writes if a developer accidentally targets the real app.
    expect(support.path, contains('com.example.blue_hydrangea.stage3test/'));
    scratch = await (await getTemporaryDirectory()).createTemp(
      'stage3-storage-',
    );
  });
  tearDownAll(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  testWidgets(
    'A-02 native credential roundtrip replacement and tamper rejection',
    (tester) async {
      const channel = MethodChannel('blue_hydrangea/daily_phrase_credentials');
      const first = 'invalid-stage3-credential-one';
      const second = 'invalid-stage3-credential-two';
      final file = File(
        p.join(support.parent.path, 'no_backup', 'deepseek_credential_v1'),
      );
      try {
        await channel.invokeMethod<void>('removeKey');
        expect(await channel.invokeMethod<bool>('hasKey'), false);
        await channel.invokeMethod<void>('saveKey', first);
        expect(await channel.invokeMethod<String>('readKey'), first);
        final encrypted = await file.readAsString();
        expect(encrypted.contains(first), false);
        final envelope = jsonDecode(encrypted) as Map<String, dynamic>;
        expect(base64Decode(envelope['iv'] as String), hasLength(12));
        await channel.invokeMethod<void>('saveKey', first);
        expect(await file.readAsString(), isNot(encrypted));
        await channel.invokeMethod<void>('saveKey', second);
        expect(await channel.invokeMethod<String>('readKey'), second);
        await expectLater(
          channel.invokeMethod<void>('saveKey', 'bad'),
          throwsA(isA<PlatformException>()),
        );
        expect(await channel.invokeMethod<String>('readKey'), second);
        final tampered =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final bytes = base64Decode(tampered['value'] as String);
        bytes[0] ^= 1;
        tampered['value'] = base64Encode(bytes);
        await file.writeAsString(jsonEncode(tampered), flush: true);
        await expectLater(
          channel.invokeMethod<String>('readKey'),
          throwsA(isA<PlatformException>()),
        );
      } finally {
        await channel.invokeMethod<void>('removeKey');
      }
      expect(await channel.invokeMethod<bool>('hasKey'), false);
      expect(await channel.invokeMethod<String>('readKey'), isNull);
      expect(await file.exists(), false);
    },
  );

  for (final table in ['tender_notes', 'memories', 'moods', 'anniversaries']) {
    testWidgets(
      'LIMIT $table native SQLite boundary and rejected insert preservation',
      (tester) async {
        final path = p.join(scratch.path, '$table.db');
        final store = LocalDatabase.atPath(path);
        final db = await store.database;
        final date = DateTime(2026, 9, 26);
        final limit = table == 'anniversaries' ? 100 : 1500;
        final values = switch (table) {
          'tender_notes' => {
            'title': 'synthetic',
            'content': '',
            'date': date.toIso8601String(),
          },
          'memories' => {'note': 'synthetic', 'date': date.toIso8601String()},
          'moods' => {
            'mood': 'happy',
            'note': 'synthetic',
            'date': date.toIso8601String(),
          },
          _ => {'message': 'synthetic', 'date': date.toIso8601String()},
        };
        Future<bool> add() => switch (table) {
          'tender_notes' => store.addTenderNote(
            TenderNote(title: 'boundary', content: '', date: date),
          ),
          'memories' => store.addMemory(Memory(note: 'boundary', date: date)),
          'moods' => store.saveMood(
            mood: 'happy',
            note: 'boundary',
            date: date,
          ),
          _ => store.addAnniversary(
            Anniversary(message: 'boundary', date: date),
          ),
        };
        try {
          await db.delete(table);
          final batch = db.batch();
          for (var i = 0; i < limit - 1; i++) {
            batch.insert(table, values);
          }
          await batch.commit(noResult: true);
          expect(await add(), true);
          final before = await db.query(table, orderBy: 'id');
          expect(before, hasLength(limit));
          expect(await add(), false);
          expect(await db.query(table, orderBy: 'id'), before);
        } finally {
          await db.close();
          await deleteDatabase(path);
        }
      },
    );
  }

  testWidgets(
    'M-04 M-10 ordered images edit and reopen with real private files',
    (tester) async {
      final path = p.join(scratch.path, 'images.db');
      final store = LocalDatabase.atPath(path);
      final db = await store.database;
      final paths = <String>[];
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jP00AAAAASUVORK5CYII=',
      );
      for (var i = 0; i < 20; i++) {
        final file = File(p.join(scratch.path, 'synthetic-$i.png'));
        await file.writeAsBytes(png);
        paths.add(file.path);
      }
      final date = DateTime(2026, 9, 26);
      await db.delete('memories');
      expect(
        await store.addMemory(
          Memory(note: 'synthetic', date: date, imagePaths: paths),
        ),
        true,
      );
      final saved = (await store.memories()).single;
      expect(saved.allImagePaths, paths);
      final editedPaths = paths.reversed.skip(1).toList();
      await store.updateMemory(
        Memory(
          id: saved.id,
          note: '',
          date: date,
          place: '',
          imagePaths: editedPaths,
        ),
      );
      await db.close();
      final reopened = LocalDatabase.atPath(path);
      try {
        final result = (await reopened.memories()).single;
        expect(result.note, '');
        expect(result.allImagePaths, editedPaths);
        for (final path in result.allImagePaths) {
          expect(await File(path).readAsBytes(), png);
        }
        await reopened.deleteMemory(result.id!);
        expect(await reopened.memories(), isEmpty);
        expect(await (await reopened.database).query('memory_images'), isEmpty);
      } finally {
        await (await reopened.database).close();
        await deleteDatabase(path);
      }
    },
  );
}
