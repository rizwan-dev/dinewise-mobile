import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../data/quote.dart';

/// The bill in the order the website shows it: Item total, Discount (CODE), Packing, Delivery,
/// GST, To pay. Discount and delivery rows are hidden when zero.
class BillCard extends StatelessWidget {
  const BillCard({super.key, required this.totals, this.couponCode, this.gstLabel = 'GST (5%)', this.title = 'Bill'});

  final Totals totals;
  final String? couponCode;
  final String gstLabel;
  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget row(String label, String value, {bool strong = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? context.text.titleMedium
                  : context.text.bodyMedium!.copyWith(color: color ?? palette.muted),
            ),
          ),
          Text(
            value,
            style: strong
                ? context.text.titleMedium
                : context.text.bodyMedium!.copyWith(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
            const SizedBox(height: 10),
            row('Item total', formatPaise(totals.subtotalPaise)),
            if (totals.discountPaise > 0)
              row(
                couponCode == null ? 'Discount' : 'Discount ($couponCode)',
                '−${formatPaise(totals.discountPaise)}',
                color: palette.success,
              ),
            row('Packing', formatPaise(totals.packagingPaise)),
            if (totals.deliveryFeePaise > 0) row('Delivery', formatPaise(totals.deliveryFeePaise)),
            row(gstLabel, formatPaise(totals.taxPaise)),
            const Divider(height: 20),
            row('To pay', formatPaise(totals.totalPaise), strong: true),
          ],
        ),
      ),
    );
  }
}
