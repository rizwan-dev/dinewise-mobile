import 'dart:convert';

import 'package:dinewise/core/api/api_client.dart';
import 'package:dinewise/core/api/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  ApiClient clientFor(
    http.Client mock, {
    String? customerToken = 'cust',
    void Function(AuthKind)? onUnauthenticated,
  }) => ApiClient(
    baseUrl: 'https://example.test/api/v1/',
    clientFactory: () => mock,
    tokenFor: (kind) => kind == AuthKind.customer ? customerToken : 'staff',
    onUnauthenticated: onUnauthenticated,
  );

  http.Response json(Object body, int status) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  group('ApiException.fromResponse', () {
    test('keeps the server code, message and field', () {
      final e = ApiException.fromResponse(422, {
        'error': {'code': 'WRONG_CODE', 'message': 'That code is not right. 4 tries left.', 'field': 'code'},
      });
      expect(e.status, 422);
      expect(e.code, 'WRONG_CODE');
      expect(e.message, 'That code is not right. 4 tries left.');
      expect(e.field, 'code');
    });

    test('falls back by status when the body is not the error shape', () {
      expect(ApiException.fromResponse(500, '<html>').code, 'INTERNAL');
      expect(ApiException.fromResponse(401, null).isUnauthenticated, isTrue);
      expect(ApiException.fromResponse(404, {'oops': 1}).isNotFound, isTrue);
      expect(ApiException.fromResponse(409, null).isConflict, isTrue);
      expect(ApiException.fromResponse(418, null).code, ApiErrorCode.unexpected);
    });

    test('classifies slot and coupon problems', () {
      for (final code in ['SLOT_FULL', 'SLOT_UNAVAILABLE', 'KITCHEN_FULL']) {
        expect(ApiException(status: 409, code: code, message: '').isSlotProblem, isTrue);
      }
      expect(const ApiException(status: 422, code: 'COUPON_EXPIRED', message: '').isCouponProblem, isTrue);
      expect(const ApiException(status: 422, code: 'UNAVAILABLE', message: '').isCouponProblem, isFalse);
    });

    test('INVALID_CREDENTIALS is a 401 but not a dead session', () {
      const e = ApiException(
        status: 401,
        code: 'INVALID_CREDENTIALS',
        message: 'Email or password is incorrect.',
      );
      expect(e.isUnauthenticated, isFalse);
    });
  });

  group('ApiClient', () {
    test('sends JSON, the bearer token for the kind asked for, and decodes UTF-8', () async {
      late http.Request seen;
      final api = clientFor(
        MockClient((request) async {
          seen = request;
          return json({'name': 'Tadka Lane', 'note': '₹50 off'}, 200);
        }),
      );
      final body = await api.post('/quote', body: {'lines': []}, auth: AuthKind.customer);
      expect(seen.url.toString(), 'https://example.test/api/v1/quote');
      expect(seen.headers['Authorization'], 'Bearer cust');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {'lines': []});
      expect(body!['note'], '₹50 off');
    });

    test('sends no token on public calls', () async {
      late http.Request seen;
      final api = clientFor(
        MockClient((r) async {
          seen = r;
          return json({}, 200);
        }),
      );
      await api.get('/menu');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('returns null for 204', () async {
      final api = clientFor(MockClient((_) async => http.Response('', 204)));
      expect(await api.post('/auth/sign-out', auth: AuthKind.customer), isNull);
    });

    test('maps error bodies to ApiException', () async {
      final api = clientFor(
        MockClient(
          (_) async => json({
            'error': {'code': 'SLOT_FULL', 'message': 'That time has just filled up.', 'field': 'slot'},
          }, 409),
        ),
      );
      await expectLater(
        api.post('/orders', body: {}, auth: AuthKind.customer),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'SLOT_FULL')
              .having((e) => e.field, 'field', 'slot'),
        ),
      );
    });

    test('reports a dead token once, for the kind that was used', () async {
      final dropped = <AuthKind>[];
      final api = clientFor(
        MockClient(
          (_) async => json({
            'error': {'code': 'UNAUTHENTICATED', 'message': 'Sign in again.'},
          }, 401),
        ),
        onUnauthenticated: dropped.add,
      );
      await expectLater(api.get('/kitchen/board', auth: AuthKind.staff), throwsA(isA<ApiException>()));
      expect(dropped, [AuthKind.staff]);
    });

    test('a 401 on a public sign-in call does not drop any session', () async {
      final dropped = <AuthKind>[];
      final api = clientFor(
        MockClient(
          (_) async => json({
            'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Email or password is incorrect.'},
          }, 401),
        ),
        onUnauthenticated: dropped.add,
      );
      await expectLater(api.post('/staff/sign-in', body: {}), throwsA(isA<ApiException>()));
      expect(dropped, isEmpty);
    });

    test('turns connection failures into a friendly network error', () async {
      final api = clientFor(MockClient((_) async => throw http.ClientException('Connection refused')));
      await expectLater(
        api.get('/menu'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetwork, 'isNetwork', isTrue)
              .having((e) => e.status, 'status', 0),
        ),
      );
    });

    test('a 2xx body that is not JSON is an error, not a crash', () async {
      final api = clientFor(MockClient((_) async => http.Response('<html>', 200)));
      await expectLater(api.get('/menu'), throwsA(isA<ApiException>()));
    });
  });
}
