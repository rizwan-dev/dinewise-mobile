import 'dart:convert';

import '../../../core/api/api_client.dart';
import '../../menu/data/menu.dart';

enum Fulfilment {
  delivery('DELIVERY', 'Delivery'),
  pickup('PICKUP', 'Pickup');

  const Fulfilment(this.wire, this.label);

  final String wire;
  final String label;

  static Fulfilment parse(String value) => value == 'PICKUP' ? pickup : delivery;

  /// The only payment in v1 is cash, named for how it is paid.
  String get cashLabel => this == delivery ? 'Cash on delivery' : 'Pay at pickup';
}

/// One line of the cart: a dish, its chosen size and add-ons, and how many.
///
/// The dish's name, photo and veg mark are kept so the cart renders without the menu. Prices
/// here are only the app's estimate for the "Add ₹…" button and the cart bar; the bill always
/// comes from the server's quote.
class CartLine {
  CartLine({
    required this.itemId,
    required this.name,
    required this.veg,
    required this.unitPricePaise,
    this.photoUrl,
    this.variantId,
    this.variantName,
    List<int> addonIds = const [],
    this.addonNames = const [],
    this.quantity = 1,
  }) : addonIds = List.unmodifiable([...addonIds]..sort());

  /// Builds the line for [dish] with the choices made in the dish sheet.
  factory CartLine.fromChoice(
    Dish dish, {
    Variant? variant,
    List<Addon> addons = const [],
    int quantity = 1,
  }) {
    return CartLine(
      itemId: dish.id,
      name: dish.name,
      veg: dish.veg,
      photoUrl: dish.photoUrl,
      variantId: variant?.id,
      variantName: variant?.name,
      addonIds: [for (final a in addons) a.id],
      addonNames: [for (final a in addons) a.name],
      unitPricePaise: unitPrice(dish, variant: variant, addons: addons),
      quantity: quantity,
    );
  }

  /// Unit price = (variant or dish price) + chosen add-ons.
  static int unitPrice(Dish dish, {Variant? variant, List<Addon> addons = const []}) =>
      (variant?.pricePaise ?? dish.pricePaise) + addons.fold(0, (sum, a) => sum + a.pricePaise);

  final int itemId;
  final String name;
  final bool veg;
  final String? photoUrl;
  final int? variantId;
  final String? variantName;
  final List<int> addonIds;
  final List<String> addonNames;
  final int quantity;
  final int unitPricePaise;

  /// Two lines with the same dish and the same choices merge into one.
  String get key => '$itemId|${variantId ?? ''}|${addonIds.join(',')}';

  int get lineTotalPaise => unitPricePaise * quantity;

  /// "Full · Extra butter", or empty.
  String get optionsLabel => [?variantName, ...addonNames].join(' · ');

  /// The line as `/quote` and `/orders` take it.
  Json toRequest() => {
    'itemId': itemId,
    'variantId': ?variantId,
    if (addonIds.isNotEmpty) 'addonIds': addonIds,
    'quantity': quantity,
  };

  CartLine withQuantity(int quantity) => CartLine(
    itemId: itemId,
    name: name,
    veg: veg,
    photoUrl: photoUrl,
    variantId: variantId,
    variantName: variantName,
    addonIds: addonIds,
    addonNames: addonNames,
    unitPricePaise: unitPricePaise,
    quantity: quantity,
  );
}

/// What happened when a line was added.
enum AddOutcome {
  added,
  merged,

  /// Merged, but the quantity hit the per-line maximum.
  capped,

  /// Not added: the cart already has the maximum number of lines.
  tooManyLines,
}

/// The cart: lines plus how and when the customer wants it. Immutable; every change returns a
/// new cart.
class Cart {
  const Cart({
    this.lines = const [],
    this.fulfilment = Fulfilment.delivery,
    this.pincode,
    this.couponCode,
    this.slot = asap,
  });

  static const asap = 'ASAP';

  /// Defaults from `/restaurant` (`maxQuantityPerLine`, `maxLines`).
  static const defaultMaxQuantity = 20;
  static const defaultMaxLines = 30;

  final List<CartLine> lines;
  final Fulfilment fulfilment;

  /// The delivery pincode, six digits, or null.
  final String? pincode;

  /// The coupon the customer typed, normalised (upper case, no spaces).
  final String? couponCode;

  /// `ASAP`, or a slot `value` for a scheduled order.
  final String slot;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (n, l) => n + l.quantity);

  /// The app's own sum, for the cart bar only.
  int get estimatedSubtotalPaise => lines.fold(0, (sum, l) => sum + l.lineTotalPaise);

  int quantityOf(int itemId) => lines.where((l) => l.itemId == itemId).fold(0, (n, l) => n + l.quantity);

  bool get hasValidPincode => pincode != null && RegExp(r'^\d{6}$').hasMatch(pincode!);

  /// Delivery needs a pincode before it can be priced.
  bool get readyToQuote => lines.isNotEmpty && (fulfilment == Fulfilment.pickup || hasValidPincode);

  (Cart, AddOutcome) add(
    CartLine line, {
    int maxQuantity = defaultMaxQuantity,
    int maxLines = defaultMaxLines,
  }) {
    final index = lines.indexWhere((l) => l.key == line.key);
    if (index == -1) {
      if (lines.length >= maxLines) return (this, AddOutcome.tooManyLines);
      final quantity = line.quantity.clamp(1, maxQuantity);
      return (
        _with(lines: [...lines, line.withQuantity(quantity)]),
        quantity < line.quantity ? AddOutcome.capped : AddOutcome.added,
      );
    }
    final existing = lines[index];
    final wanted = existing.quantity + line.quantity;
    final quantity = wanted.clamp(1, maxQuantity);
    final next = [...lines]..[index] = existing.withQuantity(quantity);
    return (_with(lines: next), quantity < wanted ? AddOutcome.capped : AddOutcome.merged);
  }

  /// Sets a line's quantity; 0 or less removes it.
  Cart setQuantity(String key, int quantity, {int maxQuantity = defaultMaxQuantity}) {
    if (quantity <= 0) return remove(key);
    return _with(
      lines: [for (final l in lines) l.key == key ? l.withQuantity(quantity.clamp(1, maxQuantity)) : l],
    );
  }

  Cart remove(String key) => _with(
    lines: [
      for (final l in lines)
        if (l.key != key) l,
    ],
  );

  Cart withFulfilment(Fulfilment value) => _with(fulfilment: value);

  Cart withPincode(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s'), '');
    return _with(
      pincode: cleaned == null || cleaned.isEmpty ? null : cleaned,
      clearPincode: cleaned == null || cleaned.isEmpty,
    );
  }

  /// Case and spaces do not matter to the server (`welcome 50` = `WELCOME50`).
  Cart withCoupon(String? code) {
    final cleaned = code?.replaceAll(RegExp(r'\s'), '').toUpperCase();
    return _with(couponCode: cleaned, clearCoupon: cleaned == null || cleaned.isEmpty);
  }

  Cart withSlot(String value) => _with(slot: value);

  /// Empty lines; how the customer orders (delivery, pincode) is kept for next time.
  Cart cleared() => Cart(fulfilment: fulfilment, pincode: pincode);

  /// The `/quote` body. Equal carts give equal requests, so a quote is only fetched again when
  /// something that changes the price changed.
  QuoteRequest get quoteRequest => QuoteRequest({
    'lines': [for (final l in lines) l.toRequest()],
    'fulfilment': fulfilment.wire,
    'pincode': fulfilment == Fulfilment.delivery && hasValidPincode ? pincode : null,
    'couponCode': couponCode,
  });

  Cart _with({
    List<CartLine>? lines,
    Fulfilment? fulfilment,
    String? pincode,
    bool clearPincode = false,
    String? couponCode,
    bool clearCoupon = false,
    String? slot,
  }) => Cart(
    lines: lines ?? this.lines,
    fulfilment: fulfilment ?? this.fulfilment,
    pincode: clearPincode ? null : (pincode ?? this.pincode),
    couponCode: clearCoupon ? null : (couponCode ?? this.couponCode),
    slot: slot ?? this.slot,
  );
}

/// A `/quote` body with value equality.
class QuoteRequest {
  QuoteRequest(this.body) : _canonical = jsonEncode(body);

  final Json body;
  final String _canonical;

  @override
  bool operator ==(Object other) => other is QuoteRequest && other._canonical == _canonical;

  @override
  int get hashCode => _canonical.hashCode;
}
