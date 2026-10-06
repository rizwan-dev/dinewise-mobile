// Every customer flow, driven in the real app on a device or simulator against a running API
// with the demo seed (the local stack). Another device's actions (the kitchen moving an order,
// marking a dish sold out, other customers filling a slot) are made straight on the API.
//
//   flutter test integration_test/customer_flows_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://localhost:8082/api/v1
//
// The offline check needs the host to stop the API for a moment; see
// `stopsWhenAskedToGoOffline` below (skipped unless OFFLINE_CHECK=true).

import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/router/app_router.dart';
import 'package:dinewise/features/cart/data/cart_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device.dart';

const offlineCheck = bool.fromEnvironment('OFFLINE_CHECK');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> search(WidgetTester tester, String text) async {
    if (find.byTooltip('Clear search').evaluate().isNotEmpty) {
      await tapOn(tester, find.byTooltip('Clear search'));
    }
    await typeInto(tester, find.byType(TextField), text);
    FocusManager.instance.primaryFocus?.unfocus();
    await pause(tester);
  }

  /// Signs in through the sign-in screen with a fresh number and the demo code.
  Future<void> signInWithDemoCode(WidgetTester tester, {bool shotIt = false}) async {
    await waitFor(tester, find.text('Send code'));
    await typeInto(tester, find.byType(TextField), Api.newPhone());
    await tapOn(tester, find.text('Send code'));
    await waitFor(tester, find.text('Fill it in'));
    if (shotIt) await shot(tester, '07-sign-in-demo-code');
    await tapOn(tester, find.text('Fill it in'));
    await waitFor(tester, find.text('Welcome!'));
    await typeInto(tester, find.byType(TextField), 'Asha Kulkarni');
    await tapOn(tester, find.text('Continue'));
  }

  Future<void> addFromMenu(WidgetTester tester, ProviderContainer c, String dish, {int more = 0}) async {
    routerOf(c).go(Routes.menu);
    await search(tester, dish.toLowerCase());
    await tapOn(tester, find.bySemanticsLabel('Add $dish'));
    for (var i = 0; i < more; i++) {
      await tapOn(tester, find.bySemanticsLabel('One more $dish'));
    }
  }

  testWidgets('home, menu, search, veg only, sections', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    await waitFor(tester, find.textContaining('Open now'));
    expect(find.text('WELCOME50'), findsOneWidget);
    await shot(tester, '01-home');

    await tapOn(tester, find.text('Mains'));
    await waitFor(tester, find.text('Dal Makhani'));
    expect(routerOf(c).state.uri.path, Routes.menu);

    await search(tester, 'tikka');
    await waitFor(tester, find.text('Chicken Tikka'));
    await tapOn(tester, find.text('Veg only'));
    await waitGone(tester, find.text('Chicken Tikka'));
    expect(find.text('Paneer Tikka'), findsOneWidget);
    await shot(tester, '02-menu-search-veg');
    await tapOn(tester, find.text('Veg only'));
    await search(tester, 'zzz');
    await waitFor(tester, find.text('Nothing matches'));
    await tapOn(tester, find.text('Show the whole menu'));
    await waitFor(tester, find.text('Hara Bhara Kebab'));
  });

  testWidgets('dish sheet: sizes, add-on limits, live price', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    routerOf(c).go(Routes.menu);
    await search(tester, 'chicken dum');
    await tapOn(tester, find.bySemanticsLabel('Add Chicken Dum Biryani'));
    await tapOn(tester, find.text('Full'));
    await tapOn(tester, find.text('Extra raita'));
    await tapOn(tester, find.text('Boiled egg'));
    final salan = tester.widget<InkWell>(
      find.ancestor(of: find.text('Mirchi salan'), matching: find.byType(InkWell)).first,
    );
    expect(salan.onTap, isNull, reason: '"up to 2" stops at 2');
    expect(find.text('Add · ₹445'), findsOneWidget);
    await tapOn(tester, find.text('Add · ₹445'));
    await waitFor(tester, find.text('1 item · ₹445'));

    await search(tester, 'butter chicken');
    await tapOn(tester, find.bySemanticsLabel('Add Butter Chicken'));
    await tapOn(tester, find.text('Full'));
    await tapOn(tester, find.bySemanticsLabel('One more Butter Chicken').last);
    await waitFor(tester, find.text('Add · ₹760'));
    await shot(tester, '03-dish-sheet');
    await tapOn(tester, find.text('Add · ₹760'));
    expect(c.read(cartProvider).itemCount, 3);
  });

  testWidgets('cart: steppers, pincode, coupons, pickup, slots, sign in, cash order, live tracking', (
    tester,
  ) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    await addFromMenu(tester, c, 'Paneer Tikka', more: 1);
    await addFromMenu(tester, c, 'Garlic Naan');
    await tapOn(tester, find.text('View cart'));
    await waitFor(tester, find.text('Your cart'));

    await tapOn(tester, find.bySemanticsLabel('Remove Garlic Naan'));
    await waitGone(tester, find.text('Garlic Naan'));
    await typeInto(tester, find.widgetWithText(TextField, 'Delivery pincode'), '400001');
    await waitFor(tester, find.text('We do not deliver to that pincode yet. Pickup is available.'));
    await typeInto(tester, find.widgetWithText(TextField, 'Delivery pincode'), '411021');
    await waitFor(tester, find.text('To pay'));
    expect(find.text('Delivery'), findsWidgets);

    await typeInto(tester, find.widgetWithText(TextField, 'Coupon code'), 'FREEFOOD');
    await tapOn(tester, find.text('Apply'));
    await waitFor(tester, find.text('FREEFOOD is not a valid code.'));
    await shot(tester, '05-cart-coupon-error');
    await typeInto(tester, find.widgetWithText(TextField, 'Coupon code'), 'welcome 50');
    await tapOn(tester, find.text('Apply'));
    await waitFor(tester, find.text('WELCOME50 applied'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await pause(tester);
    await shot(tester, '04-cart-bill');

    await tapOn(tester, find.text('Pickup'));
    await waitFor(tester, find.textContaining('Collect it from Tadka Lane'));
    await tapOn(tester, find.text('Pickup time'));
    await tapOn(tester, find.text('Tomorrow'));
    await shot(tester, '06-slot-picker');
    await tapOn(tester, find.text('12:30 pm'));
    await waitFor(tester, find.text('Tomorrow, 12:30 pm'));
    await tapOn(tester, find.text('Pickup time'));
    await tapOn(tester, find.text('As soon as possible').first);
    await waitGone(tester, find.text('Tomorrow, 12:30 pm'));

    await tapOn(tester, find.text('Sign in to checkout'));
    await waitFor(tester, find.text('Send code'));
    await typeInto(tester, find.byType(TextField), '12');
    await tapOn(tester, find.text('Send code'));
    await waitFor(tester, find.textContaining('mobile number'));
    await typeInto(tester, find.byType(TextField), Api.newPhone());
    await tapOn(tester, find.text('Send code'));
    await waitFor(tester, find.text('Fill it in'));
    await typeInto(tester, find.byType(TextField), '111111');
    await waitFor(tester, find.textContaining('not right'));
    await shot(tester, '07-sign-in-demo-code');
    await tapOn(tester, find.text('Fill it in'));
    await waitFor(tester, find.text('Welcome!'));
    await typeInto(tester, find.byType(TextField), 'Asha Kulkarni');
    await tapOn(tester, find.text('Continue'));

    await waitFor(tester, find.text('Pay at pickup'));
    await typeInto(tester, find.widgetWithText(TextFormField, 'Less oil please'), 'Less oil please');
    await shot(tester, '08-checkout');
    await tapOn(tester, find.text('Place order'));
    await waitFor(tester, find.textContaining('Order TL-'), seconds: 30);
    final code = tester.widget<Text>(find.textContaining('Order TL-')).data!.replaceFirst('Order ', '');
    await waitFor(tester, find.text('Live'));

    await Api.move(code, 'PREPARING');
    await waitFor(tester, find.text('Being prepared'));
    await shot(tester, '09-order-live');
    await Api.move(code, 'READY');
    await waitFor(tester, find.textContaining('Ready for pickup around'));

    routerOf(c).go(Routes.orders);
    await waitFor(tester, find.text(code));
    expect(find.text('On its way'), findsOneWidget);
    await shot(tester, '10-my-orders');

    await Api.move(code, 'COLLECTED');
    routerOf(c).go(Routes.order(code));
    await waitFor(tester, find.textContaining('Enjoy your meal'));
  });

  testWidgets('a cash delivery order to a new address, then cancel while new', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    await addFromMenu(tester, c, 'Dal Makhani', more: 1);
    c.read(cartProvider.notifier).setPincode('411045');
    await tapOn(tester, find.text('View cart'));
    await waitFor(tester, find.text('To pay'));
    await tapOn(tester, find.text('Sign in to checkout'));
    await signInWithDemoCode(tester);
    await waitFor(tester, find.text('Cash on delivery'));
    await tapOn(tester, find.text('Place order'));
    await waitFor(tester, find.text('Please enter the flat, building and street.'));
    await typeInto(
      tester,
      find.widgetWithText(TextFormField, 'Flat, building and street'),
      'Flat 7, Aundh Road',
    );
    await tapOn(tester, find.text('Place order'));
    await waitFor(tester, find.textContaining('Expected at your door around'), seconds: 30);

    await tapOn(tester, find.text('Cancel order'));
    await tapOn(tester, find.widgetWithText(TextButton, 'Cancel order'));
    await waitFor(tester, find.text('You cancelled this order. Nothing to pay.'));

    // The address was saved: the next checkout offers it.
    routerOf(c).go(Routes.account);
    await waitFor(tester, find.textContaining('Flat 7, Aundh Road'));
  });

  testWidgets('sold-out dish: greyed on the menu and a problem in the cart', (tester) async {
    final c = await startApp(tester);
    await Api.setAvailable(29, true);
    await waitFor(tester, find.text('What are you craving?'));
    await addFromMenu(tester, c, 'Garlic Naan', more: 2);
    await Api.setAvailable(29, false);
    try {
      await tapOn(tester, find.text('View cart'));
      await tapOn(tester, find.text('Pickup'));
      await waitFor(tester, find.text('Garlic Naan is sold out right now.'));
      final button = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Sign in to checkout'), matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);

      routerOf(c).go(Routes.menu);
      await waitFor(tester, find.byType(TextField));
      await search(tester, 'garlic');
      await pullToRefresh(tester);
      await waitFor(tester, find.text('Sold out'));
      await shot(tester, '15-menu-sold-out');
    } finally {
      await Api.setAvailable(29, true);
    }
  });

  testWidgets('a full slot: slots fetched again, the full time disabled', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    await addFromMenu(tester, c, 'Dal Makhani');
    await tapOn(tester, find.text('View cart'));
    await tapOn(tester, find.text('Pickup'));
    await tapOn(tester, find.text('Pickup time'));
    await tapOn(tester, find.text('Tomorrow'));
    // The latest time still open tomorrow (earlier runs may have filled some).
    final open = [
      for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
        if (chip.onSelected != null && (chip.label as Text).data!.endsWith('m')) (chip.label as Text).data!,
    ];
    final time = open.last;
    await tapOn(tester, find.text(time));
    final slot = c.read(cartProvider).slot;
    await tapOn(tester, find.text('Sign in to checkout'));
    await signInWithDemoCode(tester);
    await waitFor(tester, find.text('Place order'));

    // Eight other customers take that slot first.
    for (var i = 0; i < 8; i++) {
      await Api.order(slot: slot, name: 'Slot Filler');
    }
    await tapOn(tester, find.text('Place order'));
    await waitFor(tester, find.text('When should it be ready?'));
    await tapOn(tester, find.text('Tomorrow'));
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, time));
    expect(chip.onSelected, isNull, reason: 'the full slot cannot be chosen');
    await shot(tester, '17-slot-full');
    await tapOn(tester, find.text('As soon as possible').first);
    await tapOn(tester, find.text('Place order'));
    await waitFor(tester, find.textContaining('Order TL-'), seconds: 30);
  });

  testWidgets('401 after the session is revoked elsewhere, and sign out', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    routerOf(c).go(Routes.signIn);
    await signInWithDemoCode(tester);
    await waitFor(tester, find.text('Asha Kulkarni'));
    await shot(tester, '18-account');

    // Signed out on another device: the next call is 401 and the app shows signed out.
    final token = c.read(customerSessionProvider)!.token;
    final (status, _) = await Api.call('POST', '/auth/sign-out', token: token);
    expect(status, 204);
    await tapOn(tester, find.text('Orders'));
    await waitFor(tester, find.text('Your orders live here'));
    expect(c.read(customerSessionProvider), isNull);

    // Sign in again, then sign out from the account page: the token dies on the server.
    routerOf(c).go(Routes.signIn);
    await signInWithDemoCode(tester);
    final second = c.read(customerSessionProvider)!.token;
    routerOf(c).go(Routes.account);
    await tapOn(tester, find.text('Sign out'));
    await tapOn(tester, find.widgetWithText(TextButton, 'Sign out'));
    await waitFor(tester, find.text('Sign in to order'));
    final (meStatus, _) = await Api.call('GET', '/me', token: second);
    expect(meStatus, 401);
  });

  testWidgets('offline while following an order: reconnects and catches up', (tester) async {
    final c = await startApp(tester);
    await waitFor(tester, find.text('What are you craving?'));
    await addFromMenu(tester, c, 'Dal Makhani');
    await tapOn(tester, find.text('View cart'));
    await tapOn(tester, find.text('Pickup'));
    await tapOn(tester, find.text('Sign in to checkout'));
    await signInWithDemoCode(tester);
    // The host watches for this note, stops the API for 20 s, then starts it again.
    await typeInto(tester, find.widgetWithText(TextFormField, 'Less oil please'), 'Please ring the bell');
    await tapOn(tester, find.text('Place order'));
    await waitFor(tester, find.textContaining('Order TL-'), seconds: 30);
    final code = tester.widget<Text>(find.textContaining('Order TL-')).data!.replaceFirst('Order ', '');
    await waitFor(tester, find.text('Reconnecting…'), seconds: 60);
    await shot(tester, '19-reconnecting');
    await waitFor(tester, find.text('Live'), seconds: 120);
    await Api.move(code, 'PREPARING');
    await waitFor(tester, find.text('Being prepared'));
  }, skip: !offlineCheck);
}
