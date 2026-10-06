import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/live/live_status.dart';
import '../../../core/providers.dart';
import 'order.dart';

class OrdersRepository {
  const OrdersRepository(this._api);

  final ApiClient _api;

  Future<List<OrderSummary>> list() async {
    final json = await _api.get('/orders', auth: AuthKind.customer);
    return [for (final o in json['orders']! as List) OrderSummary.fromJson(o as Json)];
  }

  Future<Order> get(String code) async =>
      Order.fromJson((await _api.get('/orders/$code', auth: AuthKind.customer))['order']! as Json);

  Future<Order> cancel(String code) async =>
      Order.fromJson((await _api.post('/orders/$code/cancel', auth: AuthKind.customer))!['order']! as Json);

  /// Places an order. Cash only in v1, so `paymentMethod` is always `ON_DELIVERY`.
  Future<Order> place(Json body) async => Order.fromJson(
    (await _api.post(
          '/orders',
          body: {...body, 'paymentMethod': 'ON_DELIVERY'},
          auth: AuthKind.customer,
        ))!['order']!
        as Json,
  );
}

final ordersRepositoryProvider = Provider((ref) => OrdersRepository(ref.watch(apiClientProvider)));

/// The customer's recent orders, newest first. Empty when signed out.
final myOrdersProvider = FutureProvider.autoDispose<List<OrderSummary>>((ref) async {
  final signedIn = ref.watch(customerSessionProvider.select((s) => s?.customer.id));
  if (signedIn == null) return const [];
  return ref.watch(ordersRepositoryProvider).list();
});

final orderProvider = AsyncNotifierProvider.autoDispose.family<OrderNotifier, Order, String>(
  OrderNotifier.new,
);

class OrderNotifier extends AsyncNotifier<Order> {
  OrderNotifier(this.code);

  final String code;

  OrdersRepository get _repo => ref.read(ordersRepositoryProvider);

  @override
  Future<Order> build() => _repo.get(code);

  /// Fetches again without showing a loading state (live updates, pull to refresh).
  /// Returns the error when the fetch failed (the last good data is kept), or null.
  Future<Object?> refreshQuietly() async {
    final result = await AsyncValue.guard(() => _repo.get(code));
    if (!ref.mounted) return null;
    // Keep showing the last good order if a refresh fails; the live stream will try again.
    final before = state.value?.status;
    if (result.hasValue || !state.hasValue) state = result;
    if (result.value != null && before != null && result.value!.status != before) {
      ref.invalidate(myOrdersProvider);
    }
    return result.error;
  }

  /// Cancels the order (allowed while it is `PLACED`). Throws [ApiException] on refusal.
  Future<void> cancel() async {
    final order = await _repo.cancel(code);
    if (ref.mounted) state = AsyncData(order);
  }
}

/// The live stream for one order, while it is not final and the app is in the foreground.
final orderLiveProvider = NotifierProvider.autoDispose.family<OrderLive, LiveStatus, String>(OrderLive.new);

class OrderLive extends Notifier<LiveStatus> {
  OrderLive(this.code);

  final String code;

  @override
  LiveStatus build() {
    final isFinal = ref.watch(orderProvider(code).select((o) => o.value?.isFinal));
    if (isFinal != false) return LiveStatus.off;
    return followLive(
      ref,
      (status) => state = status,
      path: '/orders/$code/events',
      auth: AuthKind.customer,
      onChange: (_) => ref.read(orderProvider(code).notifier).refreshQuietly(),
    );
  }
}
