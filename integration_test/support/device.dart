// Helpers for the on-device suites: driving the real app, talking to the API as "another
// device" would (a kitchen tablet, another customer), and marking screenshot moments.

import 'dart:convert';

import 'package:dinewise/app.dart';
import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/auth/token_store.dart';
import 'package:dinewise/core/config/env.dart';
import 'package:dinewise/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, Object?>;

/// Starts the app with in-memory session storage and returns its container.
Future<ProviderContainer> startApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore())],
      child: const DinewiseApp(),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(DinewiseApp)));
}

GoRouter routerOf(ProviderContainer c) => c.read(routerProvider);

/// Pumps until [finder] shows. Live streams keep animating, so `pumpAndSettle` never ends.
///
/// Lists build lazily, so something below the fold does not exist until scrolled to: every few
/// seconds the visible lists are scrolled to look for it.
Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 20, bool scroll = true}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  var nextScroll = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
    if (scroll && DateTime.now().isAfter(nextScroll)) {
      if (await _scrollTo(tester, finder)) return;
      nextScroll = DateTime.now().add(const Duration(seconds: 3));
    }
  }
  final texts = [
    for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText(),
  ];
  throw TestFailure('Timed out waiting for $finder. On screen: $texts');
}

Future<bool> _scrollTo(WidgetTester tester, Finder target) async {
  final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  final count = lists.evaluate().length;
  for (var i = count - 1; i >= 0; i--) {
    for (final delta in [300.0, -300.0]) {
      try {
        await tester.scrollUntilVisible(target, delta, scrollable: lists.at(i), maxScrolls: 12);
        await tester.pump(const Duration(milliseconds: 300));
        if (target.evaluate().isNotEmpty) return true;
      } on Object {
        // Not in this list, or not in this direction.
      }
    }
  }
  return false;
}

/// Pull to refresh on the first list on screen.
Future<void> pullToRefresh(WidgetTester tester) async {
  final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
  for (var i = 0; i < 6; i++) {
    await tester.drag(list, const Offset(0, 600), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.timedDrag(list, const Offset(0, 500), const Duration(milliseconds: 700), warnIfMissed: false);
  await pause(tester, 3000);
}

Future<void> waitGone(WidgetTester tester, Finder finder, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end) && finder.evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> pause(WidgetTester tester, [int ms = 600]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps [finder] once it shows, scrolling it into view and closing the keyboard first.
Future<void> tapOn(WidgetTester tester, Finder finder, {int index = 0}) async {
  await waitFor(tester, finder);
  FocusManager.instance.primaryFocus?.unfocus();
  await pause(tester, 400);
  await tester.ensureVisible(finder.at(index));
  await pause(tester, 300);
  await tester.tap(finder.at(index), warnIfMissed: false);
  await pause(tester);
}

Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  await waitFor(tester, field);
  await tester.ensureVisible(field.first);
  await tester.tap(field.first, warnIfMissed: false);
  await pause(tester, 300);
  await tester.enterText(field.first, text);
  await pause(tester, 500);
}

/// Scrolls whichever vertical list holds [target] until it is on screen.
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) await waitFor(tester, target);
  await tester.ensureVisible(target.first);
  await pause(tester, 300);
}

/// Marks a screenshot moment: the host runner sees the line and captures the simulator.
Future<void> shot(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await pause(tester, 900);
  // ignore: avoid_print
  print('SHOT:$name');
  await pause(tester, 3000);
}

/// The API, called directly: what the kitchen tablet or another customer would do.
class Api {
  static const base = Env.apiBaseUrl;

  static Future<(int, Json?)> call(String method, String path, {Object? body, String? token}) async {
    final request = http.Request(method, Uri.parse('$base$path'))
      ..headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await request.send());
    final text = utf8.decode(response.bodyBytes);
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text) as Json);
  }

  static String? _staff;

  static Future<String> staffToken() async {
    if (_staff != null) return _staff!;
    final (_, json) = await call('POST', '/staff/demo-sign-in', body: {'role': 'KITCHEN'});
    return _staff = json!['accessToken']! as String;
  }

  static Future<void> move(String code, String to, {String? reason}) async {
    final (status, json) = await call(
      'POST',
      '/kitchen/orders/$code/move',
      body: {'to': to, 'reason': ?reason},
      token: await staffToken(),
    );
    if (status != 200) throw TestFailure('move $code -> $to: $status $json');
  }

  static Future<void> setAvailable(int itemId, bool available) async {
    await call(
      'POST',
      '/kitchen/menu/$itemId/availability',
      body: {'available': available},
      token: await staffToken(),
    );
  }

  static Future<bool> available(int itemId) async {
    final (_, menu) = await call('GET', '/menu');
    for (final s in menu!['sections']! as List) {
      for (final i in (s as Json)['items']! as List) {
        if ((i as Json)['id'] == itemId) return i['available']! as bool;
      }
    }
    throw TestFailure('No dish $itemId');
  }

  static var _phones = DateTime.now().millisecondsSinceEpoch % 100000000;

  /// A fresh demo phone number for each sign-in.
  static String newPhone([String prefix = '93']) => '$prefix${(_phones++).toString().padLeft(8, '0')}';

  /// Signs a new customer in through the API: the `/auth/otp/verify` response.
  static Future<Json> signIn({String name = 'Rohan Joshi'}) async {
    final phone = newPhone('94');
    final (_, otp) = await call('POST', '/auth/otp', body: {'phone': phone});
    final (_, verified) = await call(
      'POST',
      '/auth/otp/verify',
      body: {'phone': phone, 'code': otp!['demoCode'], 'name': name},
    );
    return verified!;
  }

  /// Signs a new customer in through the API and returns the token.
  static Future<String> customer({String name = 'Rohan Joshi'}) async =>
      (await signIn(name: name))['accessToken']! as String;

  /// Places an order as another customer and returns its code.
  static Future<String> order({
    String fulfilment = 'PICKUP',
    String slot = 'ASAP',
    String? notes,
    String name = 'Rohan Joshi',
  }) async {
    final token = await customer(name: name);
    final (status, json) = await call(
      'POST',
      '/orders',
      token: token,
      body: {
        'lines': [
          {'itemId': 12, 'quantity': 1},
          {'itemId': 28, 'quantity': 2},
        ],
        'fulfilment': fulfilment,
        'slot': slot,
        if (fulfilment == 'DELIVERY') 'newAddress': {'line1': 'Flat 3, Baner Road', 'pincode': '411045'},
        'notes': ?notes,
      },
    );
    if (status != 201) throw TestFailure('order: $status $json');
    return (json!['order']! as Json)['code']! as String;
  }

  /// Waits until [code] is on the board's live columns (not "Scheduled for later").
  static Future<void> waitOnBoardNow(String code) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      final (_, board) = await call('GET', '/kitchen/board', token: await staffToken());
      if ((board!['current']! as List).any((t) => (t as Json)['code'] == code)) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    throw TestFailure('$code is not on the live board');
  }

  static Future<String> orderStatus(String code) async {
    final (_, board) = await call('GET', '/kitchen/board', token: await staffToken());
    for (final t in [...board!['current']! as List, ...board['later']! as List]) {
      if ((t as Json)['code'] == code) return t['status']! as String;
    }
    return 'OFF_BOARD';
  }
}
