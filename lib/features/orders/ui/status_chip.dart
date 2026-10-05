import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/order.dart';

/// A coloured pill with the order's status label.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, required this.label});

  final OrderStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (bg, fg) = switch (status) {
      OrderStatus.delivered || OrderStatus.collected => (palette.successSoft, palette.success),
      OrderStatus.cancelled || OrderStatus.rejected || OrderStatus.expired => (palette.dangerSoft, palette.danger),
      OrderStatus.ready || OrderStatus.outForDelivery => (palette.successSoft, palette.success),
      _ => (palette.accentSoft, palette.accentOnSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: context.text.labelMedium!.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

IconData statusIcon(OrderStatus status) => switch (status) {
  OrderStatus.placed => Icons.receipt_long_rounded,
  OrderStatus.preparing => Icons.soup_kitchen_rounded,
  OrderStatus.ready => Icons.takeout_dining_rounded,
  OrderStatus.outForDelivery => Icons.delivery_dining_rounded,
  OrderStatus.delivered => Icons.home_rounded,
  OrderStatus.collected => Icons.shopping_bag_rounded,
  OrderStatus.cancelled => Icons.cancel_rounded,
  OrderStatus.rejected => Icons.block_rounded,
  _ => Icons.hourglass_bottom_rounded,
};
