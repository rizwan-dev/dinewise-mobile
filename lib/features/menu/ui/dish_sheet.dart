import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/dish_photo.dart';
import '../../../core/widgets/food_marks.dart';
import '../../../core/widgets/states.dart';
import '../../cart/data/cart.dart';
import '../../cart/data/cart_providers.dart';
import '../data/dish_choice.dart';
import '../data/menu.dart';

/// Opens the dish sheet: photo, description, size, add-ons, quantity and a live price.
Future<void> showDishSheet(BuildContext context, Dish dish) {
  // Close the keyboard, and do not hand focus back to the search box when the sheet closes.
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => DishSheet(dish: dish),
  );
}

/// Adds [line] to the cart and says what happened.
void addToCart(BuildContext context, WidgetRef ref, CartLine line) {
  final outcome = ref.read(cartProvider.notifier).add(line);
  HapticFeedback.lightImpact();
  switch (outcome) {
    case AddOutcome.added || AddOutcome.merged:
      showMessage(context, '${line.name} added to your cart');
    case AddOutcome.capped:
      showMessage(context, 'That is the most of ${line.name} one order can take.', error: true);
    case AddOutcome.tooManyLines:
      showMessage(context, 'Your cart is full. Remove something to add more.', error: true);
  }
}

class DishSheet extends ConsumerStatefulWidget {
  const DishSheet({super.key, required this.dish});

  final Dish dish;

  @override
  ConsumerState<DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends ConsumerState<DishSheet> {
  late DishChoice choice = DishChoice.initial(widget.dish);

  void _add() {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final outcome = ref.read(cartProvider.notifier).add(choice.toLine());
    HapticFeedback.lightImpact();
    final text = switch (outcome) {
      AddOutcome.added || AddOutcome.merged => '${widget.dish.name} added to your cart',
      AddOutcome.capped => 'That is the most of ${widget.dish.name} one order can take.',
      AddOutcome.tooManyLines => 'Your cart is full. Remove something to add more.',
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    final palette = context.palette;
    final text = context.text;
    final height = MediaQuery.sizeOf(context).height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * 0.92),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: CustomScrollView(
              shrinkWrap: true,
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 10,
                        child: DishPhoto(url: dish.photoUrl, greyedOut: !dish.available),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton.filledTonal(
                          tooltip: 'Close',
                          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.9)),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.black87),
                        ),
                      ),
                      if (dish.bestseller)
                        const Positioned(left: 16, bottom: 14, child: BestsellerBadge(onPhoto: true)),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          VegMark(veg: dish.veg),
                          const SizedBox(width: 8),
                          SpiceMeter(spice: dish.spice),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(dish.name, style: text.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        dish.variants.isEmpty
                            ? formatPaise(dish.pricePaise)
                            : 'from ${formatPaise(dish.fromPricePaise)}',
                        style: text.titleMedium,
                      ),
                      if (dish.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(dish.description, style: text.bodyMedium!.copyWith(color: palette.muted)),
                      ],
                      if (!dish.available) ...[
                        const SizedBox(height: 16),
                        const Notice(
                          icon: Icons.do_not_disturb_on_outlined,
                          tone: NoticeTone.danger,
                          text: 'Sold out right now. Please check back later.',
                        ),
                      ],
                    ],
                  ),
                ),
                if (dish.available && dish.variants.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _OptionGroup(
                      title: 'Size',
                      hint: 'Choose one',
                      children: [
                        for (final v in dish.variants)
                          _OptionTile(
                            label: v.name,
                            price: formatPaise(v.pricePaise),
                            selected: choice.variant?.id == v.id,
                            radio: true,
                            onTap: () => setState(() => choice = choice.withVariant(v)),
                          ),
                      ],
                    ),
                  ),
                if (dish.available)
                  for (final group in dish.addonGroups)
                    SliverToBoxAdapter(
                      child: _OptionGroup(
                        title: group.name,
                        hint: group.hint,
                        needsPick: choice.missing?.id == group.id,
                        children: [
                          for (final addon in group.addons)
                            _OptionTile(
                              label: addon.name,
                              price: addon.pricePaise == 0 ? null : '+${formatPaise(addon.pricePaise)}',
                              selected: choice.isChosen(group, addon),
                              radio: group.isSingleChoice,
                              enabled: choice.isChosen(group, addon) || !choice.isFull(group),
                              onTap: () => setState(() => choice = choice.toggle(group, addon)),
                            ),
                        ],
                      ),
                    ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ),
          ),
          if (dish.available)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: palette.hairline)),
              ),
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
              child: Row(
                children: [
                  QuantityStepper(
                    quantity: choice.quantity,
                    min: 1,
                    itemName: dish.name,
                    onChanged: (q) => setState(() => choice = choice.withQuantity(q)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: choice.isValid ? _add : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          choice.isValid
                              ? 'Add · ${formatPaise(choice.totalPaise)}'
                              : 'Choose ${choice.missing?.name.toLowerCase() ?? 'an option'}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({
    required this.title,
    required this.hint,
    required this.children,
    this.needsPick = false,
  });

  final String title;
  final String hint;
  final bool needsPick;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.hairline),
        ),
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text(title, style: context.text.titleMedium)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: needsPick
                          ? palette.accentSoft
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      hint,
                      style: context.text.labelSmall!.copyWith(
                        color: needsPick ? palette.accentOnSoft : palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.radio,
    required this.onTap,
    this.price,
    this.enabled = true,
  });

  final String label;
  final String? price;
  final bool selected;
  final bool radio;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = radio
        ? (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded)
        : (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded);
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: radio,
      enabled: enabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(icon, color: selected ? palette.action : (enabled ? palette.subtle : palette.hairline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: context.text.bodyLarge!.copyWith(
                      color: enabled ? null : palette.subtle,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (price != null)
                  Text(price!, style: context.text.bodyMedium!.copyWith(color: palette.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
