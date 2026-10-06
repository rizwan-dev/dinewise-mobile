import '../../../core/api/api_client.dart';
import '../../cart/data/cart.dart';

/// What the checkout form holds, its checks (the server's rules, so most mistakes are caught
/// before a round trip) and the `POST /orders` body it makes.
class CheckoutForm {
  const CheckoutForm({
    required this.name,
    this.addressId,
    this.label = 'Home',
    this.line1 = '',
    this.line2 = '',
    this.landmark = '',
    this.pincode = '',
    this.saveAddress = true,
    this.notes = '',
  });

  final String name;

  /// A saved address; null means [line1]… make a new one.
  final int? addressId;
  final String label;
  final String line1;
  final String line2;
  final String landmark;
  final String pincode;
  final bool saveAddress;
  final String notes;

  /// Fields the server may name in an `INVALID` error that the form can show inline.
  static const fields = {'name', 'label', 'line1', 'line2', 'landmark', 'pincode', 'notes'};

  static String? validateName(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 2) return 'Please enter your name.';
    if (v.length > 60) return 'That name is too long (60 letters at most).';
    return null;
  }

  static String? validateLine1(String? value) {
    final v = value?.trim() ?? '';
    if (v.length < 3) return 'Please enter the flat, building and street.';
    if (v.length > 120) return 'Please shorten this (120 characters at most).';
    return null;
  }

  static String? validatePincode(String? value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')) return 'Enter the six-digit pincode.';
    return null;
  }

  Json toBody(Cart cart) {
    final delivery = cart.fulfilment == Fulfilment.delivery;
    String? blankToNull(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'lines': [for (final l in cart.lines) l.toRequest()],
      'fulfilment': cart.fulfilment.wire,
      'slot': cart.slot,
      'name': name.trim(),
      if (delivery && addressId != null) 'addressId': addressId,
      if (delivery && addressId == null) ...{
        'newAddress': {
          'label': blankToNull(label) ?? 'Home',
          'line1': line1.trim(),
          'line2': ?blankToNull(line2),
          'landmark': ?blankToNull(landmark),
          'pincode': pincode.trim(),
        },
        'saveAddress': saveAddress,
      },
      'couponCode': cart.couponCode,
      'notes': ?blankToNull(notes),
    };
  }
}
