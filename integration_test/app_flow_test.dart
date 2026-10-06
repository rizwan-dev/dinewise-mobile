// The happy path end to end against a running API (the local stack or the demo):
// menu -> cart -> sign in with the demo code -> place a cash order -> the kitchen moves it ->
// the customer's order screen follows live.
//
//   flutter test integration_test --dart-define=API_BASE_URL=http://10.0.2.2:8082/api/v1

import 'dart:convert';

import 'package:dinewise/app.dart';
import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/auth/token_store.dart';
import 'package:dinewise/core/config/env.dart';
import 'package:dinewise/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'support/device.dart' as device;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [finder] shows (live streams keep animating, so pumpAndSettle never ends).
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isNotEmpty) return;
    }
    final texts = [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText(),
    ];
    final fields = [
      for (final f in tester.widgetList<EditableText>(find.byType(EditableText))) f.controller.text,
    ];
    throw TestFailure('Timed out waiting for $finder. On screen: $texts; fields: $fields');
  }

  Future<void> waitForGone(WidgetTester tester, Finder finder) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end) && finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> tapWhenShown(WidgetTester tester, Finder finder) async {
    await waitFor(tester, finder);
    // Close the keyboard so it does not cover what is tapped.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder.first);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
    await waitFor(tester, field);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(field.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(field.first, text);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      tester
          .widget<EditableText>(find.descendant(of: field.first, matching: find.byType(EditableText)))
          .controller
          .text,
      text,
    );
  }

  testWidgets('order, cook and follow it live', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore())],
        child: const DinewiseApp(),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(DinewiseApp)));
    final router = container.read(routerProvider);

    // Menu: add two Garlic Naan and a Full Butter Chicken.
    await waitFor(tester, find.text('What are you craving?'));
    router.go(Routes.menu);
    await waitFor(tester, find.text('Search dishes'));
    await typeInto(tester, find.byType(TextField), 'butter chicken');
    await tapWhenShown(tester, find.bySemanticsLabel('Add Butter Chicken'));
    await tapWhenShown(tester, find.text('Full'));
    await tapWhenShown(tester, find.textContaining('Add · ₹'));
    await waitForGone(tester, find.text('Full'));
    await typeInto(tester, find.byType(TextField), 'garlic naan');
    await tapWhenShown(tester, find.bySemanticsLabel('Add Garlic Naan'));
    await tapWhenShown(tester, find.bySemanticsLabel('One more Garlic Naan'));

    // Cart: pickup, priced by the server.
    await tapWhenShown(tester, find.text('View cart'));
    await tapWhenShown(tester, find.text('Pickup'));
    await waitFor(tester, find.text('Sign in to checkout'));
    await waitFor(tester, find.text('To pay'));
    await tapWhenShown(tester, find.text('Sign in to checkout'));

    // Sign in with a fresh phone number and the demo code.
    final phone = '9${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';
    await waitFor(tester, find.text('Send code'));
    await typeInto(tester, find.byType(TextField), phone);
    await tapWhenShown(tester, find.text('Send code'));
    await tapWhenShown(tester, find.text('Fill it in'));
    await waitFor(tester, find.text('Welcome!'));
    await typeInto(tester, find.byType(TextField), 'Test Customer');
    await tapWhenShown(tester, find.text('Continue'));

    // Checkout: cash at pickup.
    await waitFor(tester, find.text('Pay at pickup'));
    await tapWhenShown(tester, find.text('Place order'));
    await waitFor(tester, find.textContaining('Order TL-'), timeout: const Duration(seconds: 30));
    final title = tester.widget<Text>(find.textContaining('Order TL-')).data!;
    final code = title.replaceFirst('Order ', '');
    await waitFor(tester, find.text('Live'));
    expect(find.text('Order received'), findsWidgets);

    // The kitchen starts cooking (straight on the API, as another device would)...
    const api = Env.apiBaseUrl;
    final signIn = await http.post(
      Uri.parse('$api/staff/demo-sign-in'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'role': 'KITCHEN'}),
    );
    final staffToken = (jsonDecode(signIn.body) as Map<String, Object?>)['accessToken']! as String;
    final move = await http.post(
      Uri.parse('$api/kitchen/orders/$code/move'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $staffToken'},
      body: jsonEncode({'to': 'PREPARING'}),
    );
    expect(move.statusCode, 200);

    // ...and the customer's screen changes without a refresh.
    await waitFor(tester, find.text('Being prepared'));

    // Then kitchen mode in the app marks it ready.
    router.go(Routes.kitchen);
    await tapWhenShown(tester, find.text('Try as kitchen'));
    final ticket = find.byKey(ValueKey(code));
    // On a phone the board has tabs. After closing time an ASAP order is due tomorrow, so it
    // waits under "Later" rather than "Cooking".
    if (find.byType(TabBar).evaluate().isNotEmpty) {
      await tapWhenShown(tester, find.textContaining('Cooking ·'));
      await device.pause(tester, 1500);
      if (ticket.evaluate().isEmpty && find.textContaining('Later ·').evaluate().isNotEmpty) {
        await tapWhenShown(tester, find.textContaining('Later ·'));
      }
    }
    await device.reveal(tester, ticket);
    await tapWhenShown(tester, find.descendant(of: ticket, matching: find.text('Mark ready')));
    final end = DateTime.now().add(const Duration(seconds: 15));
    while ((await device.Api.orderStatus(code)) != 'READY') {
      if (DateTime.now().isAfter(end)) throw TestFailure('$code was not marked ready');
      await device.pause(tester, 500);
    }

    // Back as the customer: Ready.
    router.go(Routes.order(code));
    await waitFor(tester, find.textContaining('Ready for pickup around'));
    expect(container.read(customerSessionProvider), isNotNull);
    expect(container.read(staffSessionProvider), isNotNull);
  });
}
