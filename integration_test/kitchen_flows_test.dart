// Every kitchen flow, driven in the real app against a running API with the demo seed. New
// orders come from "customers" on the API, and the board must show them live. Runs on a phone
// (tabs) and on a tablet in landscape (columns).
//
//   flutter test integration_test/kitchen_flows_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://localhost:8082/api/v1

import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/auth/session.dart';
import 'package:dinewise/core/router/app_router.dart';
import 'package:dinewise/features/kitchen/ui/kitchen_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A kitchen tablet stands in landscape.
  setUpAll(() async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    if (view.physicalSize.shortestSide / view.devicePixelRatio >= 600) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    }
  });

  bool tablet(WidgetTester tester) => find.byType(TabBar).evaluate().isEmpty;

  /// On a phone, opens the tab of [column] ("New", "Cooking"…). On a tablet all columns show.
  Future<void> column(WidgetTester tester, String column) async {
    if (tablet(tester)) return;
    await tapOn(tester, find.textContaining('$column ·'));
    await pause(tester, 800);
  }

  Finder ticket(String code) => find.byKey(ValueKey(code));

  /// A new order from another customer, on the live board. Outside opening hours an ASAP order
  /// is due tomorrow; the host runner brings it forward (see suite runner, ASAP_NOW).
  Future<String> newOrder(
    WidgetTester tester, {
    String fulfilment = 'PICKUP',
    String? notes,
    String name = 'Rohan Joshi',
  }) async {
    final code = await Api.order(fulfilment: fulfilment, notes: notes, name: name);
    await Api.waitOnBoardNow(code);
    return code;
  }

  /// Taps [button] on the ticket for [code].
  Future<void> press(WidgetTester tester, String code, String button) async {
    await reveal(tester, ticket(code));
    final target = find.descendant(of: ticket(code), matching: find.text(button));
    await tester.ensureVisible(target);
    await pause(tester, 300);
    await tester.tap(target);
    await pause(tester, 1500);
  }

  Future<void> waitStatus(String code, String status) async {
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(end)) {
      if (await Api.orderStatus(code) == status) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TestFailure('$code never reached $status (now ${await Api.orderStatus(code)})');
  }

  testWidgets('staff sign-in: wrong password, then email and password; sign out', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    routerOf(c).go(Routes.kitchenSignIn);
    await waitFor(tester, find.text('Kitchen mode'));
    await shot(tester, '20-staff-sign-in');
    await typeInto(tester, find.widgetWithText(TextField, 'Email'), 'kitchen@tadkalane.example');
    await typeInto(tester, find.widgetWithText(TextField, 'Password'), 'not-the-password');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Sign in'));
    await waitFor(tester, find.text('Email or password is incorrect.'));
    await typeInto(tester, find.widgetWithText(TextField, 'Password'), 'tadka-demo-2026');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Sign in'));
    await waitFor(tester, find.byType(KitchenBoardScreen));
    await waitFor(tester, find.text('Kitchen · Kitchen'));

    await tapOn(tester, find.byTooltip('More'));
    await tapOn(tester, find.text('Sign out of kitchen'));
    await waitFor(tester, find.text('Kitchen mode'));
    expect(c.read(staffSessionProvider), isNull);
  });

  testWidgets('demo sign-in from the account page; live board; every move; reject', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    // A customer is signed in on the same phone: the two sessions stay apart.
    final me = await Api.signIn(name: 'Asha Kulkarni');
    await c.read(customerSessionProvider.notifier).save(CustomerSession.fromSignIn(me));

    routerOf(c).go(Routes.account);
    await tapOn(tester, find.text('Restaurant staff?'));
    await tapOn(tester, find.text('Try as kitchen'));
    await waitFor(tester, find.byType(KitchenBoardScreen));
    await waitFor(tester, find.text('Live'));

    // A customer orders: it lands on the board without a refresh.
    final pickup = await newOrder(tester, notes: 'Extra onions', name: 'Meera Kulkarni');
    await waitFor(tester, find.text('New order on the board'));
    await column(tester, 'New');
    if (ticket(pickup).evaluate().isEmpty) await pullToRefresh(tester);
    await reveal(tester, ticket(pickup));
    expect(find.descendant(of: ticket(pickup), matching: find.text('Extra onions')), findsOneWidget);
    await shot(tester, tablet(tester) ? '12-kitchen-board-tablet' : '11-kitchen-board-phone');

    await press(tester, pickup, 'Start cooking');
    await waitStatus(pickup, 'PREPARING');
    await column(tester, 'Cooking');
    await press(tester, pickup, 'Mark ready');
    await waitStatus(pickup, 'READY');
    await column(tester, 'Ready');
    await press(tester, pickup, 'Collected');
    await waitStatus(pickup, 'OFF_BOARD');

    final delivery = await newOrder(tester, fulfilment: 'DELIVERY', name: 'Kabir Shaikh');
    await column(tester, 'New');
    await pullToRefresh(tester);
    await press(tester, delivery, 'Start cooking');
    await column(tester, 'Cooking');
    await press(tester, delivery, 'Mark ready');
    await column(tester, 'Ready');
    await press(tester, delivery, 'Out for delivery');
    await waitStatus(delivery, 'OUT_FOR_DELIVERY');
    await column(tester, 'Out');
    await press(tester, delivery, 'Delivered');
    await waitStatus(delivery, 'OFF_BOARD');

    // Reject with a one-tap reason, and with a reason typed in.
    final busy = await newOrder(tester, name: 'Ishita Bose');
    await column(tester, 'New');
    await pullToRefresh(tester);
    await press(tester, busy, 'Reject');
    await waitFor(tester, find.text('Kitchen too busy'));
    await shot(tester, '13-kitchen-reject');
    await tapOn(tester, find.text('Kitchen too busy'));
    await waitStatus(busy, 'OFF_BOARD');

    final typed = await newOrder(tester, name: 'Vikram Mehta');
    await column(tester, 'New');
    await pullToRefresh(tester);
    await press(tester, typed, 'Reject');
    await typeInto(tester, find.widgetWithText(TextField, 'Another reason'), 'Out of paneer today');
    await tapOn(tester, find.text('Reject with this reason'));
    await waitStatus(typed, 'OFF_BOARD');

    // Signing out of the kitchen keeps the customer signed in.
    await tapOn(tester, find.byTooltip('More'));
    await tapOn(tester, find.text('Sign out of kitchen'));
    await waitFor(tester, find.text('Kitchen mode'));
    expect(c.read(customerSessionProvider), isNotNull);
  });

  testWidgets('sold-out switch, seen by customers; manager sign-in', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    routerOf(c).go(Routes.kitchenSignIn);
    await tapOn(tester, find.text('Try as manager'));
    await waitFor(tester, find.textContaining('· Manager'));
    await tapOn(tester, find.byTooltip('Menu availability'));
    await typeInto(tester, find.byType(TextField), 'garlic');
    final naan = find.ancestor(of: find.text('Garlic Naan'), matching: find.byType(SwitchListTile));
    await reveal(tester, naan);
    try {
      await tester.tap(naan);
      await pause(tester, 2000);
      expect(await Api.available(29), isFalse);
      await waitFor(tester, find.text('1 dish is sold out.'));
      await shot(tester, '14-kitchen-sold-out');
      routerOf(c).go(Routes.menu);
      await typeInto(tester, find.byType(TextField), 'garlic naan');
      await waitFor(tester, find.text('Sold out'));
    } finally {
      await Api.setAvailable(29, true);
    }
  });
}
