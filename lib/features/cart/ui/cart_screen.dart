import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/format/money.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/dish_photo.dart';
import '../../../core/widgets/food_marks.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../restaurant/data/restaurant.dart';
import '../../restaurant/data/restaurant_repository.dart';
import '../data/cart.dart';
import '../data/cart_providers.dart';
import '../data/quote.dart';
import 'bill.dart';
import 'slot_picker.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final restaurant = ref.watch(restaurantProvider).value;

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your cart')),
        body: MessageView(
          icon: Icons.shopping_bag_outlined,
          title: 'Your cart is empty',
          message: 'Dal makhani, butter chicken, garlic naan… the menu is one tap away.',
          action: FilledButton(
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.menu),
            child: const Text('Browse the menu'),
          ),
        ),
      );
    }

    final quote = ref.watch(quoteProvider);
    final q = quote.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Empty your cart?'),
                  content: const Text('Everything in it will be removed.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Empty')),
                  ],
                ),
              );
              if (ok ?? false) ref.read(cartProvider.notifier).clear();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(quoteProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (i, line) in cart.lines.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    _LineTile(line: line, quoted: _quotedLine(q, line)),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.go(Routes.menu),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add more'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FulfilmentCard(cart: cart, restaurant: restaurant),
            const SizedBox(height: 16),
            _WhenCard(cart: cart, quote: q),
            const SizedBox(height: 16),
            _CouponCard(cart: cart, quote: q),
            const SizedBox(height: 16),
            _BillArea(cart: cart, quote: quote),
          ],
        ),
      ),
      bottomNavigationBar: _CheckoutBar(cart: cart, quote: quote),
    );
  }

  /// The server's line for a cart line (same dish, size and add-on names).
  static QuoteLine? _quotedLine(Quote? quote, CartLine line) {
    if (quote == null || !quote.ok) return null;
    for (final l in quote.lines) {
      if (l.itemId == line.itemId &&
          l.variantName == line.variantName &&
          l.addonNames.join('|') == line.addonNames.join('|')) {
        return l;
      }
    }
    return null;
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.line, required this.quoted});

  final CartLine line;
  final QuoteLine? quoted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = quoted?.lineTotalPaise ?? line.lineTotalPaise;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: DishPhoto(url: line.photoUrl, borderRadius: BorderRadius.circular(14), memCacheWidth: 168),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    VegMark(veg: line.veg, size: 13),
                    const SizedBox(width: 6),
                    Expanded(child: Text(line.name, style: context.text.titleMedium)),
                  ],
                ),
                if (line.optionsLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(line.optionsLabel, style: context.text.bodySmall),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    QuantityStepper(
                      compact: true,
                      quantity: line.quantity,
                      itemName: line.name,
                      onChanged: (q) => ref.read(cartProvider.notifier).setQuantity(line.key, q),
                    ),
                    const Spacer(),
                    Text(formatPaise(total), style: context.text.titleMedium),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FulfilmentCard extends ConsumerStatefulWidget {
  const _FulfilmentCard({required this.cart, required this.restaurant});

  final Cart cart;
  final Restaurant? restaurant;

  @override
  ConsumerState<_FulfilmentCard> createState() => _FulfilmentCardState();
}

class _FulfilmentCardState extends ConsumerState<_FulfilmentCard> {
  late final _pincode = TextEditingController(text: widget.cart.pincode ?? '');

  @override
  void dispose() {
    _pincode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final r = widget.restaurant;
    final palette = context.palette;
    final options = [
      if (r == null || r.offersDelivery) Fulfilment.delivery,
      if (r == null || r.offersPickup) Fulfilment.pickup,
    ];
    final pincodes = r?.charges.deliveryPincodes.keys.toList() ?? const <String>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How would you like it?', style: context.text.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<Fulfilment>(
                showSelectedIcon: false,
                segments: [
                  for (final f in options)
                    ButtonSegment(
                      value: f,
                      label: Text(f.label),
                      icon: Icon(
                        f == Fulfilment.delivery ? Icons.delivery_dining_outlined : Icons.storefront_outlined,
                      ),
                    ),
                ],
                selected: {cart.fulfilment},
                onSelectionChanged: (s) => ref.read(cartProvider.notifier).setFulfilment(s.first),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: cart.fulfilment == Fulfilment.delivery
                  ? Column(
                      key: const ValueKey('delivery'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _pincode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          autofillHints: const [AutofillHints.postalCode],
                          decoration: const InputDecoration(
                            labelText: 'Delivery pincode',
                            prefixIcon: Icon(Icons.pin_drop_outlined),
                          ),
                          onChanged: (v) {
                            if (v.length == 6 || v.isEmpty || cart.pincode != null) {
                              ref.read(cartProvider.notifier).setPincode(v);
                            }
                          },
                        ),
                        if (pincodes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('We deliver to ${pincodes.join(', ')}.', style: context.text.bodySmall),
                          if (r?.charges.freeDeliveryAbovePaise case final free?)
                            Text(
                              'Free delivery on item totals of ${formatPaise(free)} or more.',
                              style: context.text.bodySmall,
                            ),
                        ],
                      ],
                    )
                  : Row(
                      key: const ValueKey('pickup'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.storefront_outlined, color: palette.subtle, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Collect it from ${r?.name ?? 'the restaurant'}, ${r?.address ?? 'Baner, Pune'}.',
                            style: context.text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhenCard extends ConsumerWidget {
  const _WhenCard({required this.cart, required this.quote});

  final Cart cart;
  final Quote? quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = quote?.slots ?? SlotOptions.empty;
    final now = ref.watch(clockProvider)();
    final stale = cart.slot != Cart.asap && quote != null && !options.offers(cart.slot);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const Icon(Icons.schedule_rounded),
        title: Text(cart.fulfilment == Fulfilment.delivery ? 'Delivery time' : 'Pickup time'),
        subtitle: Text(
          stale
              ? 'That time is no longer available. Pick another.'
              : describeSlot(cart.slot, options, now: now),
          style: stale ? TextStyle(color: context.palette.danger) : null,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: quote == null
            ? null
            : () async {
                final picked = await showSlotPicker(context, options: options, current: cart.slot, now: now);
                if (picked != null) ref.read(cartProvider.notifier).setSlot(picked);
              },
      ),
    );
  }
}

class _CouponCard extends ConsumerStatefulWidget {
  const _CouponCard({required this.cart, required this.quote});

  final Cart cart;
  final Quote? quote;

  @override
  ConsumerState<_CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends ConsumerState<_CouponCard> {
  late final _code = TextEditingController(text: widget.cart.couponCode ?? '');

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _apply() {
    FocusScope.of(context).unfocus();
    ref.read(cartProvider.notifier).applyCoupon(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final applied = widget.quote?.coupon.applied ?? false;
    final problem = widget.quote?.coupon.problem;
    final code = widget.cart.couponCode;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: applied && code != null
            ? Row(
                children: [
                  Icon(Icons.verified_rounded, color: palette.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$code applied', style: context.text.titleMedium),
                        if (widget.quote?.totals case final t? when t.discountPaise > 0)
                          Text(
                            'You save ${formatPaise(t.discountPaise)}',
                            style: TextStyle(color: palette.success),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _code.clear();
                      ref.read(cartProvider.notifier).applyCoupon(null);
                    },
                    child: const Text('Remove'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _apply(),
                          decoration: InputDecoration(
                            labelText: 'Coupon code',
                            prefixIcon: const Icon(Icons.local_offer_outlined),
                            errorText: code != null ? problem?.message : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: OutlinedButton(onPressed: _apply, child: const Text('Apply')),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _BillArea extends ConsumerWidget {
  const _BillArea({required this.cart, required this.quote});

  final Cart cart;
  final AsyncValue<Quote?> quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!cart.readyToQuote) {
      return const Notice(
        icon: Icons.pin_drop_outlined,
        text: 'Enter your delivery pincode to see the bill, or choose Pickup.',
      );
    }
    return switch (quote) {
      AsyncValue(:final error?) when !quote.hasValue => Card(
        child: ErrorView(error: error, compact: true, onRetry: () => ref.invalidate(quoteProvider)),
      ),
      AsyncValue(value: final Quote q) => AnimatedOpacity(
        opacity: quote.isLoading ? 0.6 : 1,
        duration: const Duration(milliseconds: 150),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (q.problem case final p?) ...[
              Notice(icon: Icons.error_outline_rounded, tone: NoticeTone.danger, text: p.message),
              const SizedBox(height: 12),
            ],
            if (q.totals case final t?)
              BillCard(totals: t, couponCode: q.coupon.applied ? q.coupon.code : null),
          ],
        ),
      ),
      _ => const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Skeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: 60, height: 20),
                SizedBox(height: 14),
                Bone(),
                SizedBox(height: 10),
                Bone(),
                SizedBox(height: 10),
                Bone(width: 200),
              ],
            ),
          ),
        ),
      ),
    };
  }
}

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({required this.cart, required this.quote});

  final Cart cart;
  final AsyncValue<Quote?> quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = quote.value;
    final signedIn = ref.watch(customerSessionProvider) != null;
    final ready = q != null && q.ok && !quote.isLoading;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: context.palette.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: BusyButton(
        label: signedIn ? 'Continue to checkout' : 'Sign in to checkout',
        trailing: q?.totals == null ? null : formatPaise(q!.totals!.totalPaise),
        busy: quote.isLoading && q == null && cart.readyToQuote,
        onPressed: ready
            ? () => context.push(signedIn ? Routes.checkout : Routes.signInThen(Routes.checkout))
            : null,
      ),
    );
  }
}
