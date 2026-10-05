import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dish_photo.dart';
import '../../../core/widgets/food_marks.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../menu/data/menu.dart';
import '../../menu/data/menu_repository.dart';
import '../data/kitchen_repository.dart';

/// Mark dishes sold out (or back on). The change reaches the website and the app at once.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  /// Dish id -> the value being saved, shown at once while the request runs.
  final _pending = <int, bool>{};
  String _query = '';

  Future<void> _set(Dish dish, bool available) async {
    setState(() => _pending[dish.id] = available);
    try {
      await ref.read(availabilityProvider).set(dish.id, available: available);
      await ref.read(menuProvider.future);
      if (mounted) {
        showMessage(context, available ? '${dish.name} is back on the menu' : '${dish.name} is sold out');
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _pending.remove(dish.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Menu availability')),
      body: switch (menu) {
        AsyncValue(:final value?) => _list(context, value),
        AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(menuProvider)),
        _ => const SingleChildScrollView(child: MenuSkeleton()),
      },
    );
  }

  Widget _list(BuildContext context, Menu menu) {
    final sections = menu.filter(query: _query);
    final soldOut = menu.dishes.where((d) => !d.available).length;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(menuProvider.future),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Find a dish',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              soldOut == 0
                  ? 'Everything is available.'
                  : '$soldOut ${soldOut == 1 ? 'dish is' : 'dishes are'} sold out.',
              style: context.text.bodyMedium!.copyWith(color: context.palette.muted),
            ),
          ),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Semantics(header: true, child: Text(section.name, style: context.text.titleLarge)),
            ),
            for (final dish in section.items)
              Builder(
                builder: (context) {
                  final value = _pending[dish.id] ?? dish.available;
                  return SwitchListTile(
                    value: value,
                    onChanged: _pending.containsKey(dish.id) ? null : (v) => _set(dish, v),
                    secondary: SizedBox(
                      width: 48,
                      height: 48,
                      child: DishPhoto(
                        url: dish.photoUrl,
                        borderRadius: BorderRadius.circular(12),
                        greyedOut: !value,
                        memCacheWidth: 144,
                      ),
                    ),
                    title: Row(
                      children: [
                        VegMark(veg: dish.veg, size: 13),
                        const SizedBox(width: 6),
                        Expanded(child: Text(dish.name)),
                      ],
                    ),
                    subtitle: Text(
                      value ? 'Available' : 'Sold out',
                      style: TextStyle(color: value ? context.palette.success : context.palette.danger),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}
