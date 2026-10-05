import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/format/money.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/states.dart';
import '../../account/data/account_repository.dart';
import '../../cart/data/cart.dart';
import '../../cart/data/cart_providers.dart';
import '../../cart/ui/bill.dart';
import '../../cart/ui/slot_picker.dart';
import '../../orders/data/orders_repository.dart';
import '../../restaurant/data/restaurant.dart';
import '../../restaurant/data/restaurant_repository.dart';
import '../data/checkout_form.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(customerSessionProvider)?.customer.name ?? '');
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _landmark = TextEditingController();
  late final _pincode = TextEditingController(text: ref.read(cartProvider).pincode ?? '');
  final _notes = TextEditingController();

  /// A saved address id, or null for a new address.
  int? _addressId;
  bool _addressChosen = false;
  bool _saveAddress = true;
  bool _placing = false;
  Map<String, String> _fieldErrors = const {};
  String? _formError;

  @override
  void dispose() {
    for (final c in [_name, _label, _line1, _line2, _landmark, _pincode, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  CheckoutForm get _formData => CheckoutForm(
    name: _name.text,
    addressId: _addressId,
    label: _label.text,
    line1: _line1.text,
    line2: _line2.text,
    landmark: _landmark.text,
    pincode: _pincode.text,
    saveAddress: _saveAddress,
    notes: _notes.text,
  );

  Future<void> _place() async {
    setState(() {
      _fieldErrors = const {};
      _formError = null;
    });
    if (!(_form.currentState?.validate() ?? false)) return;
    final cart = ref.read(cartProvider);
    setState(() => _placing = true);
    try {
      final order = await ref.read(ordersRepositoryProvider).place(_formData.toBody(cart));
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(myOrdersProvider);
      ref.invalidate(meProvider);
      context.go(Routes.order(order.code));
    } on ApiException catch (e) {
      if (!mounted) return;
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _handleError(ApiException e) async {
    if (e.isSlotProblem) {
      // That time just filled up: fetch the slots again and ask for another.
      showMessage(context, e.message, error: true);
      ref.invalidate(quoteProvider);
      try {
        final fresh = await ref.read(restaurantRepositoryProvider).slots();
        if (!mounted) return;
        ref.read(cartProvider.notifier).setSlot(Cart.asap);
        final picked = await showSlotPicker(
          context,
          options: fresh,
          current: Cart.asap,
          now: ref.read(clockProvider)(),
        );
        if (picked != null) ref.read(cartProvider.notifier).setSlot(picked);
      } on ApiException {
        // The quote refresh will show the problem.
      }
      return;
    }
    if (e.code == 'ADDRESS_NOT_FOUND') ref.invalidate(meProvider);
    if (e.isCouponProblem || e.status == 422) ref.invalidate(quoteProvider);
    final field = e.field;
    setState(() {
      if (field != null && CheckoutForm.fields.contains(field)) {
        _fieldErrors = {field: e.message};
      } else {
        _formError = e.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final quote = ref.watch(quoteProvider);
    final me = ref.watch(meProvider).value;
    final restaurant = ref.watch(restaurantProvider).value;
    final now = ref.watch(clockProvider)();
    final q = quote.value;
    final delivery = cart.fulfilment == Fulfilment.delivery;
    final saved = delivery ? (me?.addresses ?? const []) : const <SavedAddress>[];

    // Default to the first saved address that matches the cart's pincode, once they load.
    if (!_addressChosen && saved.isNotEmpty) {
      _addressChosen = true;
      final match = saved.where((a) => a.pincode == cart.pincode).firstOrNull;
      _addressId = (match ?? saved.first).id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(cartProvider.notifier).setPincode((match ?? saved.first).pincode);
      });
    }

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: MessageView(
          icon: Icons.shopping_bag_outlined,
          title: 'Your cart is empty',
          action: FilledButton(
            onPressed: () => context.go(Routes.menu),
            child: const Text('Browse the menu'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Section(
              title: 'Your details',
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: 'Name',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  errorText: _fieldErrors['name'],
                ),
                validator: CheckoutForm.validateName,
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: delivery ? 'Deliver to' : 'Pick up from',
              child: delivery
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final a in saved)
                          _AddressOption(
                            title: a.label,
                            subtitle: a.oneLine,
                            selected: _addressId == a.id,
                            onTap: () {
                              setState(() => _addressId = a.id);
                              ref.read(cartProvider.notifier).setPincode(a.pincode);
                            },
                          ),
                        if (saved.isNotEmpty)
                          _AddressOption(
                            title: 'A new address',
                            selected: _addressId == null,
                            onTap: () {
                              setState(() => _addressId = null);
                              if (_pincode.text.length == 6) {
                                ref.read(cartProvider.notifier).setPincode(_pincode.text);
                              }
                            },
                          ),
                        if (_addressId == null) ...[
                          if (saved.isNotEmpty) const SizedBox(height: 12),
                          _NewAddressFields(
                            label: _label,
                            line1: _line1,
                            line2: _line2,
                            landmark: _landmark,
                            pincode: _pincode,
                            errors: _fieldErrors,
                            onPincode: (v) {
                              if (v.length == 6) ref.read(cartProvider.notifier).setPincode(v);
                            },
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _saveAddress,
                            onChanged: (v) => setState(() => _saveAddress = v ?? false),
                            title: const Text('Save this address for next time'),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      '${restaurant?.name ?? 'Tadka Lane'}\n${restaurant?.address ?? ''}',
                      style: context.text.bodyLarge,
                    ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: const Icon(Icons.schedule_rounded),
                title: Text(delivery ? 'Delivery time' : 'Pickup time'),
                subtitle: Text(describeSlot(cart.slot, q?.slots ?? SlotOptions.empty, now: now)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: q == null
                    ? null
                    : () async {
                        final picked = await showSlotPicker(
                          context,
                          options: q.slots,
                          current: cart.slot,
                          now: now,
                        );
                        if (picked != null) ref.read(cartProvider.notifier).setSlot(picked);
                      },
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Payment',
              child: Row(
                children: [
                  Icon(Icons.payments_outlined, color: context.palette.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cart.fulfilment.cashLabel, style: context.text.titleMedium),
                        Text(
                          delivery ? 'Pay the rider in cash when it arrives.' : 'Pay in cash at the counter.',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle_rounded, color: context.palette.action),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Note for the kitchen',
              child: TextFormField(
                controller: _notes,
                maxLength: 300,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: 'Less oil please', errorText: _fieldErrors['notes']),
              ),
            ),
            const SizedBox(height: 16),
            if (q?.problem case final p?) ...[
              Notice(icon: Icons.error_outline_rounded, tone: NoticeTone.danger, text: p.message),
              const SizedBox(height: 12),
            ],
            if (q?.coupon.problem case final p? when cart.couponCode != null) ...[
              Notice(
                icon: Icons.local_offer_outlined,
                tone: NoticeTone.danger,
                text: p.message,
                action: TextButton(
                  onPressed: () => ref.read(cartProvider.notifier).applyCoupon(null),
                  child: const Text('Remove'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (q?.totals case final t?)
              BillCard(totals: t, couponCode: q!.coupon.applied ? q.coupon.code : null),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Notice(icon: Icons.error_outline_rounded, tone: NoticeTone.danger, text: _formError!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: context.palette.hairline)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        child: BusyButton(
          label: 'Place order',
          icon: Icons.check_rounded,
          trailing: q?.totals == null ? null : formatPaise(q!.totals!.totalPaise),
          busy: _placing,
          onPressed: q != null && q.ok && !quote.isLoading ? _place : null,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _AddressOption extends StatelessWidget {
  const _AddressOption({required this.title, required this.selected, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? palette.action : palette.subtle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
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

class _NewAddressFields extends StatelessWidget {
  const _NewAddressFields({
    required this.label,
    required this.line1,
    required this.line2,
    required this.landmark,
    required this.pincode,
    required this.errors,
    required this.onPincode,
  });

  final TextEditingController label;
  final TextEditingController line1;
  final TextEditingController line2;
  final TextEditingController landmark;
  final TextEditingController pincode;
  final Map<String, String> errors;
  final ValueChanged<String> onPincode;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        controller: line1,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.streetAddressLine1],
        decoration: InputDecoration(labelText: 'Flat, building and street', errorText: errors['line1']),
        validator: CheckoutForm.validateLine1,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: line2,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.streetAddressLine2],
        decoration: InputDecoration(labelText: 'Area (optional)', errorText: errors['line2']),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: landmark,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Landmark (optional)', errorText: errors['landmark']),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: pincode,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.postalCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              onChanged: onPincode,
              decoration: InputDecoration(labelText: 'Pincode', errorText: errors['pincode']),
              validator: CheckoutForm.validatePincode,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: label,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Save as', hintText: 'Home', errorText: errors['label']),
            ),
          ),
        ],
      ),
    ],
  );
}
