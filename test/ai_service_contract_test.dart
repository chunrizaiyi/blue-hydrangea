import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blue_hydrangea/features/daily_phrase/daily_phrase_service.dart';
import 'package:blue_hydrangea/features/emotion_support/emotion_support_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _envelope(Object content, {String finishReason = 'stop'}) => jsonEncode({
  'choices': [
    {
      'finish_reason': finishReason,
      'message': {'content': content is String ? content : jsonEncode(content)},
    },
  ],
});

Future<HttpServer> _server(
  Future<void> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handle(request);
    } catch (_) {
      request.response.statusCode = 500;
      await request.response.close();
    }
  });
  return server;
}

Uri _uri(HttpServer server) =>
    Uri.parse('http://127.0.0.1:${server.port}/chat/completions');

const _input = EmotionSupportInput(
  mode: 'self',
  goal: '整理想法',
  situation: '今天发生了一件小事',
  feelings: ['委屈'],
);

Map<String, Object?> _analysis() => {
  'questions': <String>[],
  'analysis': {
    'holding': '被忽略时感到委屈是可以理解的。',
    'possible_origins': ['也许双方对回应时间有不同期待'],
    'core_need': '希望自己的感受被认真听见。',
    'openers': {
      'gentle': '我想和你说说今天的感受。',
      'direct': '我希望我们能讨论回应方式。',
      'pause': '我需要先休息，晚点再谈。',
    },
    'next_steps': ['先说明事实，再说自己的感受'],
    'reminder': '慢慢说也可以。',
    'safety': {'level': 'normal', 'message': ''},
  },
};

void main() {
  test('A-01/A-11 今日花语只发送本次选择的材料并解析合法响应', () async {
    late Map<String, dynamic> body;
    final server = await _server((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer fake-test-key',
      );
      body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      request.response.write(_envelope({'content': '今天的心情值得被温柔接住，慢慢来就很好。'}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = await DailyPhraseService(
      endpoint: _uri(server),
      readKey: () async => 'fake-test-key',
    ).generate(text: '今天有点累', tone: '安静');
    expect(result, contains('慢慢来'));
    final messages = body['messages'] as List;
    final user = jsonDecode((messages.last as Map)['content'] as String) as Map;
    expect(user, {'tone': '安静', 'selected_text': '今天有点累'});
    expect(jsonEncode(body), isNot(contains('照片')));
  });

  test('A-03 上游错误状态逐一转为可理解提示且不泄露响应原文', () async {
    for (final code in [401, 402, 403, 429, 500]) {
      final server = await _server((request) async {
        request.response.statusCode = code;
        request.response.write('sensitive-upstream-body');
        await request.response.close();
      });
      try {
        await expectLater(
          DailyPhraseService(
            endpoint: _uri(server),
            readKey: () async => 'fake-test-key',
          ).generate(text: '今天想歇一会儿', tone: '温柔'),
          throwsA(
            isA<DailyPhraseException>().having(
              (error) => error.message,
              'message',
              isNot(contains('sensitive-upstream-body')),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    }
  });

  test('A-05 取消旧请求后，旧结果不可返回', () async {
    final firstReceived = Completer<void>();
    final releaseFirst = Completer<void>();
    var count = 0;
    final server = await _server((request) async {
      count++;
      if (count == 1) {
        firstReceived.complete();
        await releaseFirst.future;
      }
      request.response.write(_envelope({'content': '这是一段足够长的温柔测试花语。'}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final service = DailyPhraseService(
      endpoint: _uri(server),
      readKey: () async => 'fake-test-key',
    );
    final first = service.generate(text: '第一次', tone: '温柔');
    final firstAssertion = expectLater(
      first,
      throwsA(isA<DailyPhraseException>()),
    );
    await firstReceived.future;
    final second = service.generate(text: '第二次', tone: '温柔');
    releaseFirst.complete();
    expect(await second, contains('温柔测试花语'));
    await firstAssertion;
  });

  test('A-08/A-12 非法返回与无效输入不会被当作花语展示', () async {
    final server = await _server((request) async {
      request.response.write('{"choices":[]}');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final service = DailyPhraseService(
      endpoint: _uri(server),
      readKey: () async => 'fake-test-key',
    );
    await expectLater(
      service.generate(text: '  ', tone: '温柔'),
      throwsA(isA<DailyPhraseException>()),
    );
    await expectLater(
      service.generate(text: '字' * 1401, tone: '温柔'),
      throwsA(isA<DailyPhraseException>()),
    );
    await expectLater(
      service.generate(text: '今天有点累', tone: '温柔'),
      throwsA(isA<DailyPhraseException>()),
    );
  });

  test('A-06 情绪解语解析完整卡片且请求不夹带其他本地记录', () async {
    late String requestBody;
    final server = await _server((request) async {
      requestBody = await utf8.decoder.bind(request).join();
      request.response.write(_envelope(_analysis()));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final response = await EmotionSupportService(
      endpoint: _uri(server),
      readKey: () async => 'fake-test-key',
    ).analyze(input: _input);
    expect(response.analysis?.coreNeed, contains('认真听见'));
    expect(response.analysis?.safetyLevel, 'normal');
    expect(requestBody, isNot(contains('memory_images')));
    expect(requestBody, isNot(contains('anniversaries')));
  });

  test('A-07 追问后才生成完整分析', () async {
    var requestCount = 0;
    final server = await _server((request) async {
      requestCount++;
      request.response.write(
        _envelope(
          requestCount == 1
              ? {
                  'questions': ['当时你最希望对方怎么回应？'],
                  'analysis': null,
                }
              : _analysis(),
        ),
      );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final service = EmotionSupportService(
      endpoint: _uri(server),
      readKey: () async => 'fake-test-key',
    );
    final first = await service.analyze(input: _input);
    expect(first.questions, hasLength(1));
    expect(first.analysis, isNull);
    final second = await service.analyze(
      input: _input,
      questions: first.questions,
      answers: ['希望他先听我说完'],
    );
    expect(second.analysis, isNotNull);
  });

  test('A-08 情绪解语缺失必填字段时明确失败', () async {
    final server = await _server((request) async {
      request.response.write(
        _envelope({
          'questions': [],
          'analysis': {'holding': '测试'},
        }),
      );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    await expectLater(
      EmotionSupportService(
        endpoint: _uri(server),
        readKey: () async => 'fake-test-key',
      ).analyze(input: _input),
      throwsA(isA<EmotionSupportException>()),
    );
  });
}
