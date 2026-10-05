import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/dish_photo.dart';
import '../../../core/widgets/food_marks.dart';
import '../../cart/data/cart.dart';
import '../../cart/data/cart_providers.dart';
import '../data/menu.dart';
import 'dish_sheet.dart';

/// A menu row: name, price and description on the left, the photo with an Add button on the
/// right. Sold-out dishes are greyed out and cannot be added.
class DishCard extends ConsumerWidget {
  const DishCard({super.key, required this.dish});

  final Dish dish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = context.text;
    final simpleKey = CartLine.fromChoice(dish).key;
    final inCart = ref.watch(cartProvider.select((c) => c.quantityOf(dish.id)));
    final simpleLine = ref.watch(
      cartProvider.select((c) => c.lines.where((l) => l.key == simpleKey).firstOrNull?.quantity ?? 0),
    );
    final price = dish.variants.isEmpty ? formatPaise(dish.pricePaise) : 'from ${formatPaise(dish.fromPricePaise)}';

    return Semantics(
      container: true,
      label: '${dish.name}, $price${dish.available ? '' : ', sold out'}${inCart > 0 ? ', $inCart in cart' : ''}',
      child: InkWell(
        onTap: () => showDishSheet(context, dish),
        child: Opacity(
          opacity: dish.available ? 1 : 0.6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          VegMark(veg: dish.veg),
                          if (dish.bestseller) const BestsellerBadge(),
                          SpiceMeter(spice: dish.spice),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(dish.name, style: text.titleLarge!.copyWith(fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(price, style: text.titleSmall),
                      if (dish.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          dish.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!.copyWith(color: palette.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 124,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          SizedBox(
                            width: 124,
                            height: 112,
                            child: DishPhoto(
                              url: dish.photoUrl,
                              borderRadius: BorderRadius.circular(18),
                              greyedOut: !dish.available,
                              memCacheWidth: 372,
                            ),
                          ),
                          Positioned(
                            bottom: -18,
                            child: _AddControl(
                              dish: dish,
                              simpleKey: simpleKey,
                              simpleQuantity: simpleLine,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (dish.available && dish.hasOptions)
                        Text('Customisable', style: text.labelSmall!.copyWith(color: palette.subtle)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddControl extends ConsumerWidget {
  const _AddControl({required this.dish, required this.simpleKey, required this.simpleQuantity});

  final Dish dish;
  final String simpleKey;
  final int simpleQuantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    if (!dish.available) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.hairline),
        ),
        child: Text('Sold out', style: context.text.labelLarge!.copyWith(color: palette.danger)),
      );
    }
    if (!dish.hasOptions && simpleQuantity > 0) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: QuantityStepper(
          compact: true,
          quantity: simpleQuantity,
          itemName: dish.name,
          onChanged: (q) => ref.read(cartProvider.notifier).setQuantity(simpleKey, q),
        ),
      );
    }
    return Material(
      color: palette.card,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => dish.hasOptions ? showDishSheet(context, dish) : addToCart(context, ref, CartLine.fromChoice(dish)),
        child: Container(
          constraints: const BoxConstraints(minWidth: 96, minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.action.withValues(alpha: 0.4)),
          ),
          child: Semantics(
            button: true,
            label: 'Add ${dish.name}',
            excludeSemantics: true,
            child: Text(
              'ADD',
              style: context.text.labelLarge!.copyWith(color: palette.action, fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
