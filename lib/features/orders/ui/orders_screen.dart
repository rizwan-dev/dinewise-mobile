import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/format/money.dart';
import '../../../core/format/time.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../cart/data/cart.dart';
import '../data/order.dart';
import '../data/orders_repository.dart';
import 'status_chip.dart';

/// My orders: what is on its way first, then the past.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(customerSessionProvider) != null;
    final orders = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Orders', style: context.text.headlineMedium)),
      body: !signedIn
          ? MessageView(
              icon: Icons.receipt_long_outlined,
              title: 'Your orders live here',
              message: 'Sign in to follow an order live and see what you ordered before.',
              action: FilledButton(
                onPressed: () => context.push(Routes.signIn),
                child: const Text('Sign in'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(myOrdersProvider.future),
              child: switch (orders) {
                AsyncValue(:final value?) when value.isEmpty => ListView(
                  children: [
                    MessageView(
                      icon: Icons.ramen_dining_outlined,
                      title: 'No orders yet',
                      message: 'Your first order is a few taps away.',
                      action: FilledButton(
                        onPressed: () => context.go(Routes.menu),
                        child: const Text('See the menu'),
                      ),
                    ),
                  ],
                ),
                AsyncValue(:final value?) => _OrderList(orders: value),
                AsyncValue(:final error?) => ListView(
                  children: [ErrorView(error: error, onRetry: () => ref.invalidate(myOrdersProvider))],
                ),
                _ => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (var i = 0; i < 4; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Skeleton(child: Bone(height: 92, radius: 20)),
                      ),
                  ],
                ),
              },
            ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  const _OrderList({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = orders.where((o) => !o.isFinal).toList();
    final past = orders.where((o) => o.isFinal).toList();
    final now = ref.watch(clockProvider)();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        if (active.isNotEmpty) ...[
          const SectionTitle('On its way', padding: EdgeInsets.fromLTRB(0, 8, 0, 12)),
          for (final o in active) _OrderTile(order: o, now: now),
        ],
        if (past.isNotEmpty) ...[
          SectionTitle('Past orders', padding: EdgeInsets.fromLTRB(0, active.isEmpty ? 8 : 20, 0, 12)),
          for (final o in past) _OrderTile(order: o, now: now),
        ],
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.now});

  final OrderSummary order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: () => context.go(Routes.order(order.code)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: order.isFinal
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : palette.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    statusIcon(order.status),
                    color: order.isFinal ? palette.subtle : palette.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(order.code, style: context.text.titleMedium),
                          const SizedBox(width: 8),
                          Flexible(
                            child: StatusChip(status: order.status, label: order.statusLabel),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          order.fulfilment == Fulfilment.delivery ? 'Delivery' : 'Pickup',
                          if (!order.isFinal && order.readyBy != null)
                            'by ${formatTime(order.readyBy!)}'
                          else
                            formatAgo(order.createdAt, now: now),
                        ].join(' · '),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatPaise(order.totalPaise), style: context.text.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
