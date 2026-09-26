import 'dart:convert';
import 'dart:io';

import 'package:blue_hydrangea/features/daily_phrase/daily_phrase_service.dart';
import 'package:blue_hydrangea/features/emotion_support/emotion_support_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _input = EmotionSupportInput(
  mode: 'self',
  goal: '整理想法',
  situation: '虚构的网络测试材料',
  feelings: ['普通'],
);

Future<Object?> _request(String scene, Uri endpoint) {
  if (scene == 'phrase') {
    return DailyPhraseService(
      endpoint: endpoint,
      readKey: () async => 'invalid-test-key',
    ).generate(text: '虚构的网络测试材料', tone: '安静');
  }
  return EmotionSupportService(
    endpoint: endpoint,
    readKey: () async => 'invalid-test-key',
  ).analyze(input: _input);
}

String _message(Object error) => switch (error) {
  DailyPhraseException() => error.message,
  EmotionSupportException() => error.message,
  _ => throw StateError('Unexpected exception type: ${error.runtimeType}'),
};

Future<void> _expectSafeFailure(
  Future<Object?> request, {
  String? containsText,
}) async {
  Object? failure;
  try {
    await request;
  } catch (error) {
    failure = error;
  }
  expect(failure, isNotNull);
  final message = _message(failure!);
  expect(message, isNot(contains('invalid-test-key')));
  expect(message, isNot(contains('private-upstream-body')));
  if (containsText != null) expect(message, contains(containsText));
}

Future<HttpServer> _listen(Future<void> Function(HttpRequest) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await request.drain<void>();
      await handle(request);
    } catch (_) {
      // Client cancellation deliberately closes these synthetic connections.
    }
  });
  return server;
}

Uri _url(HttpServer server) =>
    Uri.parse('http://127.0.0.1:${server.port}/chat/completions');

void main() {
  for (final scene in ['phrase', 'emotion']) {
    test('A-04 $scene refused connection returns a safe error', () async {
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = reserved.port;
      await reserved.close();
      await _expectSafeFailure(
        _request(scene, Uri.parse('http://127.0.0.1:$port/')),
      );
    });

    test('A-04 $scene oversized body is rejected', () async {
      final limit = scene == 'phrase' ? 128 * 1024 : 256 * 1024;
      final server = await _listen((request) async {
        request.response.write('x' * (limit + 1));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      await _expectSafeFailure(
        _request(scene, _url(server)),
        containsText: '过长',
      );
    });

    test(
      'A-04 $scene interrupted response does not remain loading',
      () async {
        final server = await _listen((request) async {
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Length: 99999\r\n\r\n{"choices":',
          );
          await socket.flush();
          socket.destroy();
        });
        addTearDown(() => server.close(force: true));
        await _expectSafeFailure(_request(scene, _url(server)));
      },
      timeout: const Timeout(Duration(seconds: 65)),
    );

    test('A-04 $scene redirect does not forward credentials', () async {
      var destinationCalls = 0;
      final destination = await _listen((request) async {
        destinationCalls++;
        await request.response.close();
      });
      final source = await _listen((request) async {
        request.response.statusCode = 307;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          _url(destination).toString(),
        );
        await request.response.close();
      });
      addTearDown(() async {
        await source.close(force: true);
        await destination.close(force: true);
      });
      await _expectSafeFailure(_request(scene, _url(source)));
      expect(destinationCalls, 0);
    });

    test('A-08 $scene malformed envelope variants are rejected', () async {
      for (final body in [
        'not-json',
        jsonEncode({'choices': []}),
        jsonEncode({
          'choices': [7],
        }),
        jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 7},
            },
          ],
        }),
      ]) {
        final server = await _listen((request) async {
          request.response.write(body);
          await request.response.close();
        });
        try {
          await _expectSafeFailure(_request(scene, _url(server)));
        } finally {
          await server.close(force: true);
        }
      }
    });

    test(
      'A-04 $scene real response deadline is bounded',
      () async {
        final server = await _listen((request) async {
          // Hold the response open: exercise the production deadline unchanged.
        });
        addTearDown(() => server.close(force: true));
        final watch = Stopwatch()..start();
        await _expectSafeFailure(
          _request(scene, _url(server)),
          containsText: '久',
        );
        watch.stop();
        final expected = scene == 'phrase' ? 35 : 50;
        expect(
          watch.elapsed.inMilliseconds,
          greaterThanOrEqualTo((expected - 1) * 1000),
        );
        expect(watch.elapsed.inMilliseconds, lessThan((expected + 5) * 1000));
        // A duration is evidence, not a production performance benchmark.
        // ignore: avoid_print
        print('AI_TIMEOUT scene=$scene elapsedMs=${watch.elapsedMilliseconds}');
      },
      timeout: const Timeout(Duration(seconds: 65)),
    );
  }
}
