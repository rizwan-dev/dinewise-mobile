import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import 'menu.dart';

class MenuRepository {
  const MenuRepository(this._api);

  final ApiClient _api;

  Future<Menu> menu() async => Menu.fromJson(await _api.get('/menu'));
}

final menuRepositoryProvider = Provider((ref) => MenuRepository(ref.watch(apiClientProvider)));

/// The whole menu, sold-out dishes included (shown greyed out).
final menuProvider = FutureProvider<Menu>((ref) => ref.watch(menuRepositoryProvider).menu());
