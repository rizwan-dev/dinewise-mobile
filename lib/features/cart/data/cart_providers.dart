import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/providers.dart';
import '../../restaurant/data/restaurant_repository.dart';
import 'cart.dart';
import 'quote.dart';

class CartRepository {
  const CartRepository(this._api);

  final ApiClient _api;

  /// Prices the cart. The customer token is sent when there is one, so coupon rules that
  /// depend on the customer (first order only) are checked for them.
  Future<Quote> quote(QuoteRequest request, {required bool signedIn}) async => Quote.fromJson(
    (await _api.post(
      '/quote',
      body: request.body,
      auth: signedIn ? AuthKind.customer : AuthKind.none,
    ))!,
  );
}

final cartRepositoryProvider = Provider((ref) => CartRepository(ref.watch(apiClientProvider)));

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  (int, int) get _limits {
    final rules = ref.read(restaurantProvider).value?.ordering;
    return (
      rules?.maxQuantityPerLine ?? Cart.defaultMaxQuantity,
      rules?.maxLines ?? Cart.defaultMaxLines,
    );
  }

  AddOutcome add(CartLine line) {
    final (maxQuantity, maxLines) = _limits;
    final (cart, outcome) = state.add(line, maxQuantity: maxQuantity, maxLines: maxLines);
    state = cart;
    return outcome;
  }

  void setQuantity(String key, int quantity) =>
      state = state.setQuantity(key, quantity, maxQuantity: _limits.$1);

  void remove(String key) => state = state.remove(key);
  void setFulfilment(Fulfilment value) => state = state.withFulfilment(value);
  void setPincode(String? value) => state = state.withPincode(value);
  void applyCoupon(String? code) => state = state.withCoupon(code);
  void setSlot(String value) => state = state.withSlot(value);
  void clear() => state = state.cleared();
}

/// The server's bill for the cart, fetched again whenever anything that changes the price
/// changes (lines, fulfilment, pincode, coupon, signing in). Null when there is nothing to
/// price yet (empty cart, or delivery without a pincode).
final quoteProvider = FutureProvider.autoDispose<Quote?>((ref) async {
  final ready = ref.watch(cartProvider.select((c) => c.readyToQuote));
  final request = ref.watch(cartProvider.select((c) => c.quoteRequest));
  final signedIn = ref.watch(customerSessionProvider.select((s) => s != null));
  if (!ready) return null;
  // Let a burst of stepper taps settle into one request.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!ref.mounted) return null;
  return ref.read(cartRepositoryProvider).quote(request, signedIn: signedIn);
});
