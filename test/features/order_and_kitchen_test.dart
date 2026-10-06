import 'dart:async';

import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/router/app_router.dart';
import 'package:dinewise/features/cart/data/cart.dart';
import 'package:dinewise/features/cart/data/cart_providers.dart';
import 'package:dinewise/features/menu/data/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  late FakeApi api;
  setUp(() => api = FakeApi());

  final menu = Menu.fromJson(menuJson(photos: false));

  /// Signed in, with Butter Chicken (Full) and two Garlic Naan in the cart, at checkout.
  Future<ProviderContainer> openCheckout(
    WidgetTester tester, {
    Fulfilment fulfilment = Fulfilment.delivery,
  }) async {
    final container = await pumpApp(tester, api, customer: signedInCustomer);
    final cart = container.read(cartProvider.notifier);
    final chicken = menu.dish(19)!;
    cart
      ..add(CartLine.fromChoice(chicken, variant: chicken.variants[1]))
      ..add(CartLine.fromChoice(menu.dish(29)!, quantity: 2))
      ..setFulfilment(fulfilment)
      ..setPincode('411021');
    unawaited(container.read(routerProvider).push(Routes.checkout));
    await settle(tester);
    return container;
  }

  Future<void> placeOrder(WidgetTester tester) async {
    if (find.widgetWithText(TextFormField, 'Flat, building and street').evaluate().isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Flat, building and street'),
        'Flat 7, Aundh Road',
      );
    }
    await tester.tap(find.text('Place order'));
    await settle(tester);
  }

  group('Checkout and order tracking', () {
    testWidgets('places a cash delivery order and opens it', (tester) async {
      final container = await openCheckout(tester);
      expect(find.text('Cash on delivery'), findsOneWidget);
      await placeOrder(tester);
      expect(api.requests, contains('POST /orders'));
      expect(find.text('Order TL-ABCD24'), findsOneWidget);
      expect(find.text('Order received'), findsWidgets);
      expect(find.textContaining('Expected at your door around'), findsOneWidget);
      expect(find.textContaining('ready in cash'), findsOneWidget);
      expect(container.read(cartProvider).isEmpty, isTrue);
      expect(api.addresses, hasLength(1));
      await tearDownApp(tester);
    });

    testWidgets('the order screen updates live when the kitchen moves the order', (tester) async {
      await openCheckout(tester, fulfilment: Fulfilment.pickup);
      await placeOrder(tester);
      expect(find.text('Order received'), findsWidgets);
      expect(find.text('Live'), findsOneWidget);

      api.move('TL-ABCD24', 'PREPARING');
      await settle(tester);
      expect(find.text('Being prepared'), findsWidgets);
      expect(find.text('Cancel order'), findsNothing);

      api.move('TL-ABCD24', 'READY');
      await settle(tester);
      expect(find.textContaining('Ready for pickup around'), findsOneWidget);

      // The server ends the stream: the app reconnects after 3 s and fetches again.
      await api.endStreams();
      api.move('TL-ABCD24', 'COLLECTED');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.text('Collected'), findsWidgets);
      expect(find.textContaining('Enjoy your meal'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('cancels while the order is still new', (tester) async {
      await openCheckout(tester, fulfilment: Fulfilment.pickup);
      await placeOrder(tester);
      await tester.scrollUntilVisible(
        find.text('Cancel order'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Cancel order'));
      await settle(tester, frames: 3);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel order'));
      await settle(tester);
      expect(api.order('TL-ABCD24')['status'], 'CANCELLED');
      await tester.scrollUntilVisible(
        find.text('Cancelled'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cancelled'), findsWidgets);
      await tearDownApp(tester);
    });

    testWidgets('a full slot fetches slots again and asks for another time', (tester) async {
      final container = await openCheckout(tester, fulfilment: Fulfilment.pickup);
      api.failNextOrder = 'SLOT_FULL';
      await placeOrder(tester);
      expect(api.requests, contains('GET /slots'));
      expect(find.text('When should it be ready?'), findsOneWidget);
      await tester.tap(find.text('1:45 pm'));
      await settle(tester);
      expect(container.read(cartProvider).slot, isNot(Cart.asap));
      await placeOrder(tester);
      expect(find.text('Order TL-ABCD24'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('My orders lists the order, newest first', (tester) async {
      await openCheckout(tester, fulfilment: Fulfilment.pickup);
      await placeOrder(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      container.read(routerProvider).go(Routes.orders);
      await settle(tester);
      expect(find.text('On its way'), findsOneWidget);
      expect(find.text('TL-ABCD24'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('My orders is fresh when its tab is opened after the kitchen moved an order', (tester) async {
      await openCheckout(tester, fulfilment: Fulfilment.pickup);
      await placeOrder(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      container.read(routerProvider).go(Routes.orders);
      await settle(tester);
      expect(find.text('Order received'), findsOneWidget);
      container.read(routerProvider).go(Routes.home);
      await settle(tester);
      api.move('TL-ABCD24', 'PREPARING');
      await tester.tap(find.text('Orders'));
      await settle(tester);
      expect(find.text('Being prepared'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('Kitchen', () {
    testWidgets('the demo buttons sign in to the board, apart from the customer session', (tester) async {
      final container = await pumpApp(tester, api, customer: signedInCustomer, location: Routes.kitchen);
      expect(find.text('Kitchen mode'), findsOneWidget);
      await tester.tap(find.text('Try as kitchen'));
      await settle(tester);
      expect(container.read(staffSessionProvider)!.staff.name, 'Kitchen');
      expect(container.read(customerSessionProvider), isNotNull);
      expect(find.textContaining('New · 0'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('opened from the account page, staff sign-in replaces itself with the board', (tester) async {
      await pumpApp(tester, api, location: Routes.account);
      await tester.tap(find.text('Restaurant staff?'));
      await settle(tester);
      expect(find.text('Kitchen mode'), findsOneWidget);
      await tester.tap(find.text('Try as manager'));
      await settle(tester);
      expect(find.textContaining('New · 0'), findsOneWidget);
      expect(find.text('Kitchen mode'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('an open order screen goes to sign-in when the session ends', (tester) async {
      await openCheckout(tester, fulfilment: Fulfilment.pickup);
      await placeOrder(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
      await container.read(customerSessionProvider.notifier).clear();
      await settle(tester);
      expect(find.text('Send code'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('wrong staff password shows the server message', (tester) async {
      await pumpApp(tester, api, location: Routes.kitchenSignIn);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'kitchen@tadkalane.example');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'nope');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('a new order appears live, and each move takes it along the columns', (tester) async {
      await pumpApp(tester, api, staff: signedInKitchen, location: Routes.kitchen);
      expect(find.text('New · 0'), findsOneWidget);

      // A customer orders: the kitchen stream says so and the board refetches.
      await _placeViaApi(api);
      await settle(tester);
      expect(find.text('New · 1'), findsOneWidget);
      expect(find.text('Asha Kulkarni · Pickup · placed 12:23 pm'), findsOneWidget);
      expect(find.text('Collect ₹420 cash'), findsOneWidget);

      await tester.tap(find.text('Start cooking'));
      await settle(tester);
      expect(api.order('TL-ABCD24')['status'], 'PREPARING');
      expect(find.text('Cooking · 1'), findsOneWidget);

      await tester.tap(find.text('Cooking · 1'));
      await settle(tester);
      await tester.tap(find.text('Mark ready'));
      await settle(tester);
      expect(find.text('Ready · 1'), findsOneWidget);
      await tester.tap(find.text('Ready · 1'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Collected'));
      await settle(tester);
      expect(api.order('TL-ABCD24')['status'], 'COLLECTED');
      expect(find.text('Ready · 0'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('rejects with a one-tap reason', (tester) async {
      await _placeViaApi(api);
      await pumpApp(tester, api, staff: signedInKitchen, location: Routes.kitchen);
      await tester.tap(find.text('Reject'));
      await settle(tester);
      await tester.tap(find.text('Kitchen too busy'));
      await settle(tester);
      expect(api.order('TL-ABCD24')['status'], 'REJECTED');
      expect(api.order('TL-ABCD24')['rejectReason'], 'Kitchen too busy');
      expect(find.text('New · 0'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('a move that already happened says so and refreshes', (tester) async {
      await _placeViaApi(api);
      await pumpApp(tester, api, staff: signedInKitchen, location: Routes.kitchen);
      api.order('TL-ABCD24')['status'] = 'PREPARING'; // Moved on another tablet, no event yet.
      await tester.tap(find.text('Start cooking'));
      await settle(tester);
      expect(find.text('This order has already moved on. Refresh to see its current state.'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('on a tablet in landscape the columns sit side by side', (tester) async {
      await _placeViaApi(api);
      await pumpApp(
        tester,
        api,
        staff: signedInKitchen,
        location: Routes.kitchen,
        size: const Size(1280, 800),
      );
      expect(find.byType(TabBar), findsNothing);
      for (final label in ['New', 'Cooking', 'Ready', 'Out']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Start cooking'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('the sold-out switch reaches the customer menu', (tester) async {
      final container = await pumpApp(tester, api, staff: signedInKitchen, location: Routes.kitchenMenu);
      await tester.enterText(find.byType(TextField), 'paneer tikka');
      await settle(tester, frames: 3);
      await tester.tap(find.byType(Switch).first);
      await settle(tester);
      expect(api.requests, contains('POST /kitchen/menu/1/availability'));
      expect(find.text('Sold out'), findsOneWidget);
      container.read(routerProvider).go(Routes.menu);
      await settle(tester);
      expect(find.text('Sold out'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('signing out of the kitchen keeps the customer signed in', (tester) async {
      final container = await pumpApp(
        tester,
        api,
        customer: signedInCustomer,
        staff: signedInKitchen,
        location: Routes.kitchen,
      );
      await tester.tap(find.byTooltip('More'));
      await settle(tester, frames: 3);
      await tester.tap(find.text('Sign out of kitchen'));
      await settle(tester);
      expect(container.read(staffSessionProvider), isNull);
      expect(container.read(customerSessionProvider), isNotNull);
      expect(find.text('Kitchen mode'), findsOneWidget);
      await tearDownApp(tester);
    });
  });
}

/// A pickup order for Butter Chicken (Full), placed straight on the fake API.
Future<void> _placeViaApi(FakeApi api) async {
  final client = api.client();
  await client.post(
    Uri.parse('http://fake.test/api/v1/orders'),
    headers: {'Authorization': 'Bearer ${FakeApi.customerToken}', 'Content-Type': 'application/json'},
    body:
        '{"lines":[{"itemId":19,"variantId":4,"quantity":1}],"fulfilment":"PICKUP","slot":"ASAP",'
        '"name":"Asha Kulkarni","paymentMethod":"ON_DELIVERY"}',
  );
}
