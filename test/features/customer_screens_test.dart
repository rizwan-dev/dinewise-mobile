import 'dart:async';

import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/auth/session.dart';
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
  CartLine line(int id, {int variant = -1, int quantity = 1}) {
    final dish = menu.dish(id)!;
    return CartLine.fromChoice(
      dish,
      variant: variant < 0 ? null : dish.variants[variant],
      quantity: quantity,
    );
  }

  group('Home', () {
    testWidgets('shows the open-now hero, offers, section tiles and the demo kitchen card', (tester) async {
      await pumpApp(tester, api);
      expect(find.textContaining('Open now'), findsOneWidget);
      expect(find.textContaining('next ready by'), findsOneWidget);
      expect(find.text('WELCOME50'), findsOneWidget);
      expect(find.text('What are you craving?'), findsOneWidget);
      expect(find.text('Starters'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('See the kitchen side'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open kitchen mode'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('offline at launch: the offline screen, and Try again fails calmly', (tester) async {
      api.offline = true;
      await pumpApp(tester, api);
      expect(find.text('You seem to be offline'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('You seem to be offline'), findsOneWidget);
      api.offline = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('What are you craving?'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('"Use code" puts the coupon in the cart', (tester) async {
      final container = await pumpApp(tester, api);
      await tester.tap(find.text('Use code').first);
      await tester.pump();
      expect(container.read(cartProvider).couponCode, 'WELCOME50');
      await tearDownApp(tester);
    });
  });

  group('Menu', () {
    testWidgets('lists sections with chips, and filters by search and veg only', (tester) async {
      await pumpApp(tester, api, location: Routes.menu);
      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Starters'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'naan');
      await settle(tester, frames: 3);
      expect(find.text('Garlic Naan'), findsOneWidget);
      expect(find.text('Paneer Tikka'), findsNothing);

      await tester.enterText(find.byType(TextField), 'tikka');
      await settle(tester, frames: 3);
      expect(find.text('Chicken Tikka'), findsOneWidget);
      await tester.tap(find.text('Veg only'));
      await settle(tester, frames: 3);
      expect(find.text('Chicken Tikka'), findsNothing);
      expect(find.text('Paneer Tikka'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await settle(tester, frames: 3);
      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.tap(find.text('Show the whole menu'));
      await settle(tester, frames: 3);
      expect(find.text('Hara Bhara Kebab'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('ADD puts a simple dish in the cart and the cart bar appears', (tester) async {
      final container = await pumpApp(tester, api, location: Routes.menu);
      await tester.tap(find.bySemanticsLabel('Add Paneer Tikka'));
      await settle(tester, frames: 3);
      expect(container.read(cartProvider).itemCount, 1);
      expect(find.text('1 item · ₹280'), findsOneWidget);
      // The ADD button becomes a stepper.
      await tester.tap(find.bySemanticsLabel('One more Paneer Tikka').first);
      await settle(tester, frames: 3);
      expect(find.text('2 items · ₹560'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('sold-out dishes are greyed out and cannot be added', (tester) async {
      api.setAvailable(1, false);
      await pumpApp(tester, api, location: Routes.menu);
      expect(find.text('Sold out'), findsOneWidget);
      expect(find.bySemanticsLabel('Add Paneer Tikka'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('the dish sheet prices sizes and add-ons live', (tester) async {
      final container = await pumpApp(tester, api, location: Routes.menu);
      await tester.enterText(find.byType(TextField), 'butter chicken');
      await settle(tester, frames: 3);
      await tester.tap(find.bySemanticsLabel('Add Butter Chicken'));
      await settle(tester);
      expect(find.text('Add · ₹260'), findsOneWidget);
      await tester.tap(find.text('Full'));
      await tester.pump();
      expect(find.text('Add · ₹380'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('One more Butter Chicken').last);
      await tester.pump();
      expect(find.text('Add · ₹760'), findsOneWidget);
      await tester.tap(find.text('Add · ₹760'));
      await settle(tester);
      final cart = container.read(cartProvider);
      expect(cart.lines.single.variantName, 'Full');
      expect(cart.lines.single.quantity, 2);
      await tearDownApp(tester);
    });

    testWidgets('a "choose up to" group stops at its maximum', (tester) async {
      await pumpApp(tester, api, location: Routes.menu);
      await tester.enterText(find.byType(TextField), 'chicken dum');
      await settle(tester, frames: 3);
      await tester.tap(find.bySemanticsLabel('Add Chicken Dum Biryani'));
      await settle(tester);
      expect(find.text('Optional · up to 2'), findsOneWidget);
      await tester.tap(find.text('Extra raita'));
      await tester.tap(find.text('Boiled egg'));
      await tester.pump();
      final salan = tester.widget<InkWell>(
        find.ancestor(of: find.text('Mirchi salan'), matching: find.byType(InkWell)).first,
      );
      expect(salan.onTap, isNull);
      await tearDownApp(tester);
    });
  });

  group('Cart', () {
    Future<ProviderContainer> openCart(WidgetTester tester, List<CartLine> lines, {String? coupon}) async {
      final container = await pumpApp(tester, api);
      final cart = container.read(cartProvider.notifier);
      for (final l in lines) {
        cart.add(l);
      }
      if (coupon != null) cart.applyCoupon(coupon);
      unawaited(container.read(routerProvider).push(Routes.cart));
      await settle(tester);
      return container;
    }

    testWidgets('asks for a pincode, then shows the server bill', (tester) async {
      final container = await openCart(tester, [line(19, variant: 1), line(29, quantity: 2)]);
      await tester.scrollUntilVisible(
        find.textContaining('Enter your delivery pincode'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Delivery pincode'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.widgetWithText(TextField, 'Delivery pincode'), '411021');
      await settle(tester);
      expect(container.read(cartProvider).pincode, '411021');
      await tester.scrollUntilVisible(find.text('To pay'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Item total'), findsOneWidget);
      expect(find.text('₹530'), findsWidgets);
      expect(find.text('Delivery'), findsWidgets);
      await tearDownApp(tester);
    });

    testWidgets('pickup is priced without a pincode or delivery fee', (tester) async {
      await openCart(tester, [line(19, variant: 1)]);
      await tester.tap(find.text('Pickup'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('To pay'), 300, scrollable: find.byType(Scrollable).first);
      // 380 + 20 packing + 5% GST = 420.
      expect(find.text('₹420'), findsWidgets);
      expect(find.text('Sign in to checkout'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('shows the server message for a coupon that does not apply', (tester) async {
      await openCart(tester, [line(19, variant: 1)], coupon: 'BADCODE');
      await tester.tap(find.text('Pickup'));
      await settle(tester);
      expect(find.text('BADCODE is not a valid code.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Coupon code'), 'welcome 50');
      await tester.tap(find.text('Apply'));
      await settle(tester);
      expect(find.text('WELCOME50 applied'), findsOneWidget);
      expect(find.text('You save ₹50'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('shows quote problems: no delivery to a pincode, a sold-out dish', (tester) async {
      await openCart(tester, [line(19, variant: 1)]);
      await tester.enterText(find.widgetWithText(TextField, 'Delivery pincode'), '400001');
      await settle(tester);
      expect(find.text('We do not deliver to that pincode yet. Pickup is available.'), findsOneWidget);
      api.setAvailable(19, false);
      await tester.tap(find.text('Pickup'));
      await settle(tester);
      expect(find.text('Butter Chicken is sold out right now.'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in to checkout'));
      expect(button.onPressed, isNull);
      await tearDownApp(tester);
    });

    testWidgets('the slot picker offers ASAP and open times, not full ones', (tester) async {
      final container = await openCart(tester, [line(19, variant: 1)]);
      await tester.tap(find.text('Pickup'));
      await settle(tester);
      await tester.tap(find.text('Pickup time'));
      await settle(tester);
      expect(find.text('As soon as possible'), findsWidgets);
      await tester.tap(find.text('1:15 pm'));
      await settle(tester);
      expect(container.read(cartProvider).slot, isNot(Cart.asap));
      expect(find.text('Today, 1:15 pm'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('an empty cart invites the customer to the menu', (tester) async {
      final container = await pumpApp(tester, api);
      unawaited(container.read(routerProvider).push(Routes.cart));
      await settle(tester);
      expect(find.text('Your cart is empty'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('Sign in', () {
    testWidgets('phone, demo code "Fill it in", then a name for a new customer', (tester) async {
      final container = await pumpApp(tester, api, location: Routes.signIn);
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Send code'));
      await settle(tester);
      expect(find.text('Enter a 10-digit Indian mobile number.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '98220 22314');
      await tester.tap(find.text('Send code'));
      await settle(tester);
      expect(find.textContaining('Your code is ${FakeApi.demoCode}'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '111111');
      await settle(tester);
      expect(find.text('That code is not right. 4 tries left.'), findsOneWidget);

      await tester.tap(find.text('Fill it in'));
      await settle(tester);
      expect(find.text('Welcome!'), findsOneWidget);
      expect(container.read(customerSessionProvider)!.token, FakeApi.customerToken);

      await tester.enterText(find.byType(TextField), 'Asha Kulkarni');
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(container.read(customerSessionProvider)!.customer.name, 'Asha Kulkarni');
      expect(find.text('Asha Kulkarni'), findsOneWidget); // The account page.
      await tearDownApp(tester);
    });

    testWidgets('checkout redirects to sign-in when signed out', (tester) async {
      final container = await pumpApp(tester, api);
      unawaited(container.read(routerProvider).push(Routes.checkout));
      await settle(tester);
      expect(find.text('Send code'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('Account', () {
    testWidgets('signs out on the server and on the device', (tester) async {
      final container = await pumpApp(tester, api, customer: signedInCustomer, location: Routes.account);
      expect(find.text('Asha Kulkarni'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await settle(tester, frames: 3);
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await settle(tester);
      expect(api.requests, contains('POST /auth/sign-out'));
      expect(container.read(customerSessionProvider), isNull);
      expect(find.text('Sign in to order'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('a 401 drops the session and shows the signed-out state', (tester) async {
      final container = await pumpApp(
        tester,
        api,
        customer: CustomerSession(
          token: 'revoked',
          expiresAt: DateTime.utc(2099),
          customer: signedInCustomer.customer,
        ),
        location: Routes.orders,
      );
      expect(container.read(customerSessionProvider), isNull);
      expect(find.text('Your orders live here'), findsOneWidget);
      await tearDownApp(tester);
    });
  });
}
