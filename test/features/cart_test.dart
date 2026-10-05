import 'package:dinewise/features/cart/data/cart.dart';
import 'package:dinewise/features/checkout/data/checkout_form.dart';
import 'package:dinewise/features/menu/data/dish_choice.dart';
import 'package:dinewise/features/menu/data/menu.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  final menu = Menu.fromJson(menuJson());
  final paneerTikka = menu.dish(1)!;
  final butterChicken = menu.dish(19)!;
  final kadaiMushroom = menu.dish(18)!;
  final garlicNaan = menu.dish(29)!;

  group('CartLine', () {
    test('prices a size and add-ons on top of the dish', () {
      final line = CartLine.fromChoice(butterChicken, variant: butterChicken.variants[1]);
      expect(line.unitPricePaise, 38000);
      expect(line.optionsLabel, 'Full');
      final mushroom = CartLine.fromChoice(kadaiMushroom, addons: [kadaiMushroom.addonGroups.first.addons[2]]);
      expect(mushroom.optionsLabel, 'Hot');
      expect(mushroom.toRequest(), {'itemId': 18, 'addonIds': [9], 'quantity': 1});
    });

    test('the request leaves out an absent variant and empty add-ons', () {
      expect(CartLine.fromChoice(garlicNaan, quantity: 2).toRequest(), {'itemId': 29, 'quantity': 2});
      expect(
        CartLine.fromChoice(butterChicken, variant: butterChicken.variants.first).toRequest(),
        {'itemId': 19, 'variantId': 3, 'quantity': 1},
      );
    });

    test('add-on order does not change the line key', () {
      final a = CartLine(itemId: 8, name: 'Thali', veg: true, unitPricePaise: 1, addonIds: [3, 1]);
      final b = CartLine(itemId: 8, name: 'Thali', veg: true, unitPricePaise: 1, addonIds: [1, 3]);
      expect(a.key, b.key);
    });
  });

  group('Cart', () {
    test('merges the same dish with the same choices, keeps different sizes apart', () {
      var cart = const Cart();
      AddOutcome outcome;
      (cart, outcome) = cart.add(CartLine.fromChoice(paneerTikka));
      expect(outcome, AddOutcome.added);
      (cart, outcome) = cart.add(CartLine.fromChoice(paneerTikka, quantity: 2));
      expect(outcome, AddOutcome.merged);
      (cart, _) = cart.add(CartLine.fromChoice(butterChicken, variant: butterChicken.variants[0]));
      (cart, _) = cart.add(CartLine.fromChoice(butterChicken, variant: butterChicken.variants[1]));
      expect(cart.lines, hasLength(3));
      expect(cart.lines.first.quantity, 3);
      expect(cart.itemCount, 5);
      expect(cart.quantityOf(19), 2);
      expect(cart.estimatedSubtotalPaise, 3 * 28000 + 26000 + 38000);
    });

    test('caps a line at the per-line maximum', () {
      var cart = const Cart();
      (cart, _) = cart.add(CartLine.fromChoice(garlicNaan, quantity: 19));
      final (capped, outcome) = cart.add(CartLine.fromChoice(garlicNaan, quantity: 5));
      expect(outcome, AddOutcome.capped);
      expect(capped.lines.single.quantity, 20);
      expect(capped.setQuantity(capped.lines.single.key, 99).lines.single.quantity, 20);
    });

    test('refuses a line beyond the maximum number of lines', () {
      var cart = const Cart();
      (cart, _) = cart.add(CartLine.fromChoice(paneerTikka), maxLines: 1);
      final (same, outcome) = cart.add(CartLine.fromChoice(garlicNaan), maxLines: 1);
      expect(outcome, AddOutcome.tooManyLines);
      expect(same.lines, hasLength(1));
    });

    test('a quantity of zero removes the line', () {
      var cart = const Cart();
      (cart, _) = cart.add(CartLine.fromChoice(paneerTikka));
      expect(cart.setQuantity(cart.lines.single.key, 0).isEmpty, isTrue);
    });

    test('coupons are normalised the way the server reads them', () {
      expect(const Cart().withCoupon(' welcome 50 ').couponCode, 'WELCOME50');
      expect(const Cart().withCoupon('TADKA10').withCoupon('').couponCode, isNull);
    });

    test('delivery needs a six-digit pincode before it can be quoted', () {
      var cart = const Cart();
      (cart, _) = cart.add(CartLine.fromChoice(paneerTikka));
      expect(cart.readyToQuote, isFalse);
      expect(cart.withPincode('4110').readyToQuote, isFalse);
      expect(cart.withPincode('411 045').readyToQuote, isTrue);
      expect(cart.withFulfilment(Fulfilment.pickup).readyToQuote, isTrue);
    });

    test('quote requests compare by value, and ignore the slot', () {
      var cart = const Cart(pincode: '411045');
      (cart, _) = cart.add(CartLine.fromChoice(paneerTikka));
      final request = cart.quoteRequest;
      expect(request, cart.withSlot('2026-10-05T08:00:00.000Z').quoteRequest);
      expect(request, isNot(cart.withCoupon('TADKA10').quoteRequest));
      expect(request.body, {
        'lines': [
          {'itemId': 1, 'quantity': 1},
        ],
        'fulfilment': 'DELIVERY',
        'pincode': '411045',
        'couponCode': null,
      });
      expect(cart.withFulfilment(Fulfilment.pickup).quoteRequest.body['pincode'], isNull);
    });

    test('clearing keeps how the customer orders', () {
      var cart = const Cart(fulfilment: Fulfilment.pickup, couponCode: 'TADKA10', slot: 'x');
      (cart, _) = cart.add(CartLine.fromChoice(paneerTikka));
      final cleared = cart.cleared();
      expect(cleared.isEmpty, isTrue);
      expect(cleared.fulfilment, Fulfilment.pickup);
      expect(cleared.couponCode, isNull);
      expect(cleared.slot, Cart.asap);
    });
  });

  group('DishChoice', () {
    test('pre-selects the first size and the first "choose one" add-on', () {
      final chicken = DishChoice.initial(butterChicken);
      expect(chicken.variant!.name, 'Half');
      expect(chicken.unitPricePaise, 26000);
      final mushroom = DishChoice.initial(kadaiMushroom);
      expect(mushroom.addons.single.name, 'Mild');
      expect(mushroom.isValid, isTrue);
    });

    test('choose-one groups swap; optional groups stop at their maximum', () {
      final group = kadaiMushroom.addonGroups.first;
      final hot = DishChoice.initial(kadaiMushroom).toggle(group, group.addons[2]);
      expect(hot.addons.single.name, 'Hot');

      final biryani = menu.dish(24)!;
      final extras = biryani.addonGroups.first;
      var choice = DishChoice.initial(biryani);
      for (final addon in extras.addons) {
        choice = choice.toggle(extras, addon);
      }
      expect(choice.addons, hasLength(extras.maxSelect));
      expect(choice.isFull(extras), isTrue);
      // Unticking frees a place again.
      choice = choice.toggle(extras, choice.addons.first);
      expect(choice.isFull(extras), isFalse);
    });

    test('live price = (size or dish) + add-ons, times quantity', () {
      final pavBhaji = menu.dish(22)!;
      final extras = pavBhaji.addonGroups.first;
      final choice = DishChoice.initial(pavBhaji).toggle(extras, extras.addons[1]).withQuantity(2);
      expect(choice.totalPaise, (19000 + 4000) * 2);
      final biryani = DishChoice.initial(menu.dish(24)!);
      expect(biryani.unitPricePaise, biryani.variant!.pricePaise);
      expect(choice.toLine().quantity, 2);
    });

    test('a sold-out dish cannot be chosen', () {
      expect(DishChoice.initial(paneerTikka.copyWith(available: false)).isValid, isFalse);
    });
  });

  group('CheckoutForm', () {
    test('builds a delivery order with a new address', () {
      var cart = const Cart(pincode: '411021', couponCode: 'WELCOME50');
      (cart, _) = cart.add(CartLine.fromChoice(butterChicken, variant: butterChicken.variants[1]));
      final body = const CheckoutForm(
        name: ' Asha Kulkarni ',
        line1: 'Flat 7, Aundh Road',
        landmark: 'Near the park',
        pincode: '411021',
        notes: 'Less oil please',
      ).toBody(cart);
      expect(body, {
        'lines': [
          {'itemId': 19, 'variantId': 4, 'quantity': 1},
        ],
        'fulfilment': 'DELIVERY',
        'slot': 'ASAP',
        'name': 'Asha Kulkarni',
        'newAddress': {
          'label': 'Home',
          'line1': 'Flat 7, Aundh Road',
          'landmark': 'Near the park',
          'pincode': '411021',
        },
        'saveAddress': true,
        'couponCode': 'WELCOME50',
        'notes': 'Less oil please',
      });
    });

    test('uses a saved address by id, and sends no address for pickup', () {
      var cart = const Cart(slot: '2026-10-05T08:00:00.000Z');
      (cart, _) = cart.add(CartLine.fromChoice(paneerTikka));
      final saved = const CheckoutForm(name: 'Asha', addressId: 12).toBody(cart);
      expect(saved['addressId'], 12);
      expect(saved.containsKey('newAddress'), isFalse);
      expect(saved['slot'], '2026-10-05T08:00:00.000Z');

      final pickup = const CheckoutForm(name: 'Asha', addressId: 12).toBody(cart.withFulfilment(Fulfilment.pickup));
      expect(pickup.containsKey('addressId'), isFalse);
      expect(pickup.containsKey('newAddress'), isFalse);
    });

    test('validates like the server', () {
      expect(CheckoutForm.validateName('A'), isNotNull);
      expect(CheckoutForm.validateName('Asha'), isNull);
      expect(CheckoutForm.validateLine1('7'), isNotNull);
      expect(CheckoutForm.validatePincode('41102'), isNotNull);
      expect(CheckoutForm.validatePincode('411021'), isNull);
    });
  });
}
