import 'dart:async';
import 'dart:convert';

import 'package:dinewise/core/api/api_client.dart';
import 'package:dinewise/core/api/api_exception.dart';
import 'package:dinewise/core/live/sse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SseParser', () {
    List<SseEvent> parse(String text) {
      final parser = SseParser();
      return [
        for (final line in const LineSplitter().convert(text)) ?parser.addLine(line),
      ];
    }

    test('parses the stream shown in the API contract', () async {
      const stream =
          'retry: 3000\n'
          '\n'
          'event: order\n'
          'data: {"id":75,"code":"TL-8X2H84","status":"PREPARING","paymentStatus":"NOT_REQUIRED"}\n'
          '\n'
          ': keep-alive\n'
          '\n'
          'event: order\n'
          'data: {"id":75,"code":"TL-8X2H84","status":"READY","paymentStatus":"NOT_REQUIRED"}\n'
          '\n'
          'event: resync\n'
          'data: {}\n'
          '\n';
      final parser = SseParser();
      final events = await parser.bind(Stream.value(utf8.encode(stream))).toList();
      expect(parser.retry, const Duration(seconds: 3));
      expect(events.map((e) => e.event), ['order', 'order', 'resync']);
      expect(events[0].json!['status'], 'PREPARING');
      expect(events[1].json!['code'], 'TL-8X2H84');
      expect(events[2].json, isEmpty);
    });

    test('joins several data lines with a newline and defaults the event name', () {
      expect(parse('data: one\ndata: two\n\n'), [const SseEvent('message', 'one\ntwo')]);
    });

    test('drops only one leading space and handles fields without a colon', () {
      expect(parse('data:  two spaces\n\n'), [const SseEvent('message', ' two spaces')]);
      expect(parse('data\n\n'), [const SseEvent('message', '')]);
    });

    test('ignores comments, unknown fields and messages without data', () {
      expect(parse(': keep-alive\nfoo: bar\nevent: order\n\n'), isEmpty);
    });

    test('an event name does not leak into the next message', () {
      expect(parse('event: order\n\ndata: x\n\n'), [const SseEvent('message', 'x')]);
    });

    test('copes with CRLF line endings and chunks split mid-line', () async {
      final chunks = ['event: ord', 'er\r\ndata: {"a"', ':1}\r\n\r\n'].map(utf8.encode);
      final events = await SseParser().bind(Stream.fromIterable(chunks)).toList();
      expect(events, [const SseEvent('order', '{"a":1}')]);
    });

    test('keeps the id field', () {
      expect(parse('id: 7\ndata: x\n\n').single.id, '7');
    });

    test('ignores a retry that is not a number', () {
      final parser = SseParser()..addLine('retry: soon');
      expect(parser.retry, isNull);
    });
  });

  group('LiveStream', () {
    test('backoff doubles from the base delay up to the cap', () {
      const base = Duration(seconds: 3);
      const max = Duration(seconds: 30);
      expect(LiveStream.backoff(base, 1, max), const Duration(seconds: 3));
      expect(LiveStream.backoff(base, 2, max), const Duration(seconds: 6));
      expect(LiveStream.backoff(base, 3, max), const Duration(seconds: 12));
      expect(LiveStream.backoff(base, 4, max), const Duration(seconds: 24));
      expect(LiveStream.backoff(base, 5, max), max);
      expect(LiveStream.backoff(base, 40, max), max);
    });

    test('reconnects when the server ends the stream, and says so each time', () async {
      var connections = 0;
      final client = MockClient.streaming((request, _) async {
        connections++;
        expect(request.headers['Accept'], 'text/event-stream');
        expect(request.headers['Authorization'], 'Bearer tok');
        final body = connections == 1
            ? 'retry: 3000\n\nevent: order\ndata: {"code":"TL-1"}\n\n'
            : 'event: resync\ndata: {}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final api = ApiClient(baseUrl: 'http://x/api/v1', tokenFor: (_) => 'tok', clientFactory: () => client);
      final waits = <Duration>[];
      final live = LiveStream(api, '/kitchen/events', AuthKind.staff, sleep: (d) async => waits.add(d));

      final updates = await live.updates().take(7).toList();
      expect(updates[0], isA<LiveConnected>());
      expect((updates[1] as LiveMessage).event.event, 'order');
      expect(updates[2], isA<LiveDisconnected>());
      expect(updates[3], isA<LiveConnected>());
      expect((updates[4] as LiveMessage).event.event, 'resync');
      expect(updates[5], isA<LiveDisconnected>());
      expect(updates[6], isA<LiveConnected>());
      // After a clean end the wait is the server's retry, not a growing backoff.
      expect(waits, [const Duration(seconds: 3), const Duration(seconds: 3)]);
      expect(connections, 3);
    });

    test('backs off while the server cannot be reached', () async {
      final client = MockClient.streaming((_, _) async => throw http.ClientException('offline'));
      final api = ApiClient(baseUrl: 'http://x/api/v1', tokenFor: (_) => 'tok', clientFactory: () => client);
      final waits = <Duration>[];
      final live = LiveStream(api, '/orders/TL-1/events', AuthKind.customer, sleep: (d) async => waits.add(d));
      final updates = await live.updates().take(5).toList();
      expect(updates.every((u) => u is LiveDisconnected), isTrue);
      expect(waits, [
        const Duration(seconds: 3),
        const Duration(seconds: 6),
        const Duration(seconds: 12),
        const Duration(seconds: 24),
        const Duration(seconds: 30),
      ].take(waits.length));
    });

    test('stops with the error on 401, and tells the client the token is dead', () async {
      AuthKind? dropped;
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"code":"UNAUTHENTICATED","message":"Please sign in."}}')),
          401,
        ),
      );
      final api = ApiClient(
        baseUrl: 'http://x/api/v1',
        tokenFor: (_) => 'tok',
        clientFactory: () => client,
        onUnauthenticated: (kind) => dropped = kind,
      );
      final live = LiveStream(api, '/orders/TL-1/events', AuthKind.customer, sleep: (_) async {});
      await expectLater(
        live.updates(),
        emitsError(isA<ApiException>().having((e) => e.isUnauthenticated, 'isUnauthenticated', isTrue)),
      );
      expect(dropped, AuthKind.customer);
    });

    test('closes the connection when the listener cancels', () async {
      final controller = StreamController<List<int>>();
      var closed = false;
      final client = _ClosingClient(
        MockClient.streaming((_, _) async => http.StreamedResponse(controller.stream, 200)),
        onClose: () => closed = true,
      );
      final api = ApiClient(baseUrl: 'http://x/api/v1', tokenFor: (_) => 't', clientFactory: () => client);
      final sub = LiveStream(api, '/kitchen/events', AuthKind.staff).updates().listen((_) {});
      controller.add(utf8.encode('retry: 3000\n\n'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(closed, isTrue);
      await controller.close();
    });
  });
}

class _ClosingClient extends http.BaseClient {
  _ClosingClient(this._inner, {required this.onClose});

  final http.Client _inner;
  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  @override
  void close() {
    onClose();
    _inner.close();
  }
}
