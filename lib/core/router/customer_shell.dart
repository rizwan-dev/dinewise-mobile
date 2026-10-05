import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/data/cart_providers.dart';
import '../format/money.dart';
import '../theme/app_theme.dart';
import 'app_router.dart';

const _destinations = [
  (Icons.home_outlined, Icons.home_rounded, 'Home'),
  (Icons.restaurant_menu_outlined, Icons.restaurant_menu_rounded, 'Menu'),
  (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
  (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
];

/// Customer mode's frame: bottom navigation on phones, a rail on tablets, and a cart bar
/// whenever the cart has something in it.
class CustomerShell extends ConsumerWidget {
  const CustomerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = Column(
      children: [
        Expanded(child: shell),
        const CartBar(),
      ],
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                backgroundColor: context.palette.card,
                indicatorColor: Theme.of(context).navigationBarTheme.indicatorColor,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Dinewise',
                    style: context.text.titleLarge!.copyWith(color: context.palette.accent),
                  ),
                ),
                destinations: [
                  for (final (icon, selected, label) in _destinations)
                    NavigationRailDestination(
                      icon: Icon(icon),
                      selectedIcon: Icon(selected),
                      label: Text(label),
                    ),
                ],
              ),
              VerticalDivider(width: 1, color: context.palette.hairline),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      ),
    );
  }
}

/// "3 items · ₹1,040   View cart →", above the navigation, when the cart is not empty.
class CartBar extends ConsumerWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider.select((c) => c.itemCount));
    final subtotal = ref.watch(cartProvider.select((c) => c.estimatedSubtotalPaise));
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: count == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Material(
                color: context.palette.action,
                borderRadius: BorderRadius.circular(18),
                elevation: 3,
                shadowColor: Colors.black38,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push(Routes.cart),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$count ${count == 1 ? 'item' : 'items'} · ${formatPaise(subtotal)}',
                              style: context.text.titleMedium!.copyWith(color: Colors.white),
                            ),
                          ),
                          Text('View cart', style: context.text.labelLarge!.copyWith(color: Colors.white)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
