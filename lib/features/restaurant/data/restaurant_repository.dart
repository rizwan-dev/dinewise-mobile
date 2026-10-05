import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import 'restaurant.dart';

class RestaurantRepository {
  const RestaurantRepository(this._api);

  final ApiClient _api;

  Future<Restaurant> restaurant() async => Restaurant.fromJson(await _api.get('/restaurant'));

  Future<List<Offer>> offers() async {
    final json = await _api.get('/offers');
    return [for (final o in json['offers']! as List) Offer.fromJson(o as Json)];
  }

  Future<SlotOptions> slots() async => SlotOptions.fromJson(await _api.get('/slots'));
}

final restaurantRepositoryProvider = Provider(
  (ref) => RestaurantRepository(ref.watch(apiClientProvider)),
);

/// The restaurant, its hours, charges and whether this is the public demo.
final restaurantProvider = FutureProvider<Restaurant>(
  (ref) => ref.watch(restaurantRepositoryProvider).restaurant(),
);

final offersProvider = FutureProvider<List<Offer>>(
  (ref) => ref.watch(restaurantRepositoryProvider).offers(),
);

/// Whether demo-only helpers (code fill-in, one-tap staff sign-in) may be shown.
final isDemoProvider = Provider<bool>((ref) => ref.watch(restaurantProvider).value?.demo ?? false);
