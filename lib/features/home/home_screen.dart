import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/money.dart';
import '../../core/format/time.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_colors.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/dish_photo.dart';
import '../../core/widgets/food_marks.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/states.dart';
import '../cart/data/cart.dart';
import '../cart/data/cart_providers.dart';
import '../menu/data/menu.dart';
import '../menu/data/menu_repository.dart';
import '../menu/ui/dish_sheet.dart';
import '../restaurant/data/restaurant.dart';
import '../restaurant/data/restaurant_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(offersProvider);
    await Future.wait([ref.refresh(restaurantProvider.future), ref.refresh(menuProvider.future)]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(restaurantProvider);
    final menu = ref.watch(menuProvider);
    final offers = ref.watch(offersProvider).value ?? const [];
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);

    if (restaurant.hasError && !restaurant.hasValue) {
      return Scaffold(
        body: SafeArea(child: ErrorView(error: restaurant.error, onRetry: () => _refresh(ref))),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _TopBar(restaurant: restaurant.value)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _Hero(restaurant: restaurant.value),
                ),
              ),
              if (offers.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 150,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      scrollDirection: Axis.horizontal,
                      itemCount: offers.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _OfferCard(offer: offers[i]),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SectionTitle('What are you craving?')),
              switch (menu) {
                AsyncValue(:final value?) => SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.count(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 4 / 3,
                    children: [
                      for (final s in value.sections) _SectionTile(section: s),
                    ],
                  ),
                ),
                AsyncValue(:final error?) => SliverToBoxAdapter(
                  child: ErrorView(error: error, compact: true, onRetry: () => ref.invalidate(menuProvider)),
                ),
                _ => SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.count(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 4 / 3,
                    children: [for (var i = 0; i < 4; i++) const Skeleton(child: Bone(radius: 20, height: double.infinity))],
                  ),
                ),
              },
              if (menu.value case final m? when m.bestsellers.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionTitle(
                    'Most loved',
                    subtitle: 'Our bestsellers, cooked to order.',
                    trailing: TextButton(
                      onPressed: () => context.go(Routes.menu),
                      child: const Text('See menu'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 276,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: m.bestsellers.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _BestsellerCard(dish: m.bestsellers[i]),
                    ),
                  ),
                ),
              ],
              if (restaurant.value?.demo ?? false) const SliverToBoxAdapter(child: _KitchenDemoCard()),
              if (restaurant.value case final r?) SliverToBoxAdapter(child: _HoursCard(restaurant: r)),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.restaurant});

  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider.select((c) => c.itemCount));
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Brand.saffron700, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.ramen_dining_rounded, color: Brand.saffron50),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(restaurant?.name ?? 'Tadka Lane', style: context.text.titleLarge),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: palette.subtle),
                    const SizedBox(width: 2),
                    Text('Baner, Pune', style: context.text.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: Brand.saffron600,
            offset: const Offset(-4, 4),
            child: IconButton(
              tooltip: 'Cart, $count items',
              onPressed: () => context.push(Routes.cart),
              icon: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.restaurant});

  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = restaurant;
    final now = ref.watch(clockProvider)();
    String status;
    if (r == null) {
      status = 'Checking the kitchen…';
    } else {
      status = r.openNow ? 'Open now' : 'Closed now';
      if (r.nextReadyAt != null) status += ' · next ready by ${formatDayAndTime(r.nextReadyAt!, now: now).replaceFirst('Today, ', '')}';
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/hero.webp', fit: BoxFit.cover, excludeFromSemantics: true)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    Brand.stone950.withValues(alpha: 0.92),
                    Brand.stone950.withValues(alpha: 0.55),
                    Brand.stone950.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: (r?.openNow ?? false) ? const Color(0xFF86EFAC) : Brand.stone300,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            status,
                            style: context.text.labelMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 56),
                Text(
                  'Home-style North Indian food, cooked to order.',
                  style: context.text.headlineLarge!.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  r?.tagline ?? 'North Indian home-style cooking, Baner, Pune',
                  style: context.text.bodyMedium!.copyWith(color: Brand.stone200),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.saffron700),
                  onPressed: () => context.go(Routes.menu),
                  icon: const Icon(Icons.restaurant_menu_rounded),
                  label: const Text('Order now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final applied = ref.watch(cartProvider.select((c) => c.couponCode == offer.code));
    return Container(
      width: 272,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.saffron200, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer_outlined, size: 16, color: palette.accentOnSoft),
              const SizedBox(width: 6),
              Text(
                offer.firstOrderOnly ? 'FIRST ORDER' : 'OFFER',
                style: context.text.labelSmall!.copyWith(color: palette.accentOnSoft, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              offer.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleLarge!.copyWith(fontSize: 17),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Brand.saffron200),
                ),
                child: Text(
                  offer.code,
                  style: context.text.labelLarge!.copyWith(fontFamily: 'monospace', letterSpacing: 1),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: applied
                    ? null
                    : () {
                        ref.read(cartProvider.notifier).applyCoupon(offer.code);
                        showMessage(context, '${offer.code} will be applied in your cart');
                      },
                child: Text(applied ? 'Added' : 'Use code'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section});

  final MenuSection section;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${section.name}, ${section.items.length} dishes',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(Routes.menuAt(section.slug)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DishPhoto(url: section.coverPhoto, memCacheWidth: 480),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC0C0A09), Color(0x110C0A09), Colors.transparent],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.name,
                      maxLines: 2,
                      style: context.text.titleLarge!.copyWith(color: Colors.white, fontSize: 17, height: 1.15),
                    ),
                    Text(
                      '${section.items.length} dishes',
                      style: context.text.labelMedium!.copyWith(color: Brand.stone200),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BestsellerCard extends ConsumerWidget {
  const _BestsellerCard({required this.dish});

  final Dish dish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return SizedBox(
      width: 210,
      child: Card(
        child: InkWell(
          onTap: () => showDishSheet(context, dish),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 132, width: double.infinity, child: DishPhoto(url: dish.photoUrl, memCacheWidth: 630)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: const EdgeInsets.only(top: 3), child: VegMark(veg: dish.veg, size: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dish.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dish.variants.isEmpty ? formatPaise(dish.pricePaise) : 'from ${formatPaise(dish.fromPricePaise)}',
                        style: context.text.titleSmall,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: palette.action),
                      onPressed: () => dish.hasOptions
                          ? showDishSheet(context, dish)
                          : addToCart(context, ref, CartLine.fromChoice(dish)),
                      child: Text('ADD', semanticsLabel: 'Add ${dish.name}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KitchenDemoCard extends StatelessWidget {
  const _KitchenDemoCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Brand.stone900, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DEMO',
              style: context.text.labelSmall!.copyWith(color: Brand.saffron200, letterSpacing: 1.2),
            ),
            const SizedBox(height: 4),
            Text('See the kitchen side', style: context.text.headlineSmall!.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              'Place an order, then switch to kitchen mode to accept it, cook it and send it out. '
              'Your order screen follows along live.',
              style: context.text.bodyMedium!.copyWith(color: Brand.stone300),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Brand.stone600),
              ),
              onPressed: () => context.push(Routes.kitchenSignIn),
              icon: const Icon(Icons.soup_kitchen_outlined),
              label: const Text('Open kitchen mode'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoursCard extends StatelessWidget {
  const _HoursCard({required this.restaurant});

  final Restaurant restaurant;

  static String _clock(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.parse(parts[0]);
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${parts[1]} ${h < 12 ? 'am' : 'pm'}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final today = toRestaurantTime(DateTime.now()).weekday % 7;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hours', style: context.text.titleLarge),
              const SizedBox(height: 10),
              for (final h in restaurant.hours)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          h.day,
                          style: context.text.bodyMedium!.copyWith(
                            fontWeight: h.weekday == today ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                      Text(
                        h.closed ? 'Closed' : '${_clock(h.open!)} – ${_clock(h.close!)}',
                        style: context.text.bodyMedium!.copyWith(
                          color: h.weekday == today ? null : palette.muted,
                          fontWeight: h.weekday == today ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined, size: 18, color: palette.subtle),
                  const SizedBox(width: 8),
                  Expanded(child: Text(restaurant.address, style: context.text.bodyMedium)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
