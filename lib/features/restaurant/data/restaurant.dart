import '../../../core/api/api_client.dart';
import '../../../core/format/time.dart';

/// `GET /restaurant`: everything needed to render the restaurant and explain each charge.
class Restaurant {
  const Restaurant({
    required this.name,
    required this.tagline,
    required this.phone,
    required this.address,
    required this.hours,
    required this.openNow,
    required this.nextReadyAt,
    required this.serverTime,
    required this.ordering,
    required this.charges,
    required this.demo,
  });

  factory Restaurant.fromJson(Json json) {
    final address = json['address']! as Json;
    return Restaurant(
      name: json['name']! as String,
      tagline: json['tagline']! as String,
      phone: json['phone']! as String,
      address: [address['street'], address['city'], address['postalCode']].whereType<String>().join(', '),
      hours: [for (final h in json['hours']! as List) OpeningHours.fromJson(h as Json)],
      openNow: json['openNow']! as bool,
      nextReadyAt: parseInstantOrNull(json['nextReadyAt']),
      serverTime: parseInstant(json['serverTime']! as String),
      ordering: OrderingRules.fromJson(json['ordering']! as Json),
      charges: Charges.fromJson(json['charges']! as Json),
      demo: json['demo'] as bool? ?? false,
    );
  }

  final String name;
  final String tagline;
  final String phone;

  /// One line: "Demo Road, Baner, Pune, 411045".
  final String address;
  final List<OpeningHours> hours;
  final bool openNow;

  /// The "as soon as possible" time, or null when every slot is full.
  final DateTime? nextReadyAt;
  final DateTime serverTime;
  final OrderingRules ordering;
  final Charges charges;

  /// The public demo: show demo codes and the one-tap staff sign-in.
  final bool demo;

  bool get offersPickup => ordering.fulfilment.contains('PICKUP');
  bool get offersDelivery => ordering.fulfilment.contains('DELIVERY');
}

class OpeningHours {
  const OpeningHours({required this.weekday, required this.day, this.open, this.close});

  factory OpeningHours.fromJson(Json json) => OpeningHours(
    weekday: json['weekday']! as int,
    day: json['day']! as String,
    open: json['open'] as String?,
    close: json['close'] as String?,
  );

  /// 0 = Sunday.
  final int weekday;
  final String day;
  final String? open;
  final String? close;

  bool get closed => open == null || close == null;
}

class OrderingRules {
  const OrderingRules({
    required this.fulfilment,
    required this.slotMinutes,
    required this.prepMinutes,
    required this.minimumOrderPaise,
    required this.maxQuantityPerLine,
    required this.maxLines,
  });

  factory OrderingRules.fromJson(Json json) => OrderingRules(
    fulfilment: [for (final f in json['fulfilment']! as List) f as String],
    slotMinutes: json['slotMinutes']! as int,
    prepMinutes: json['prepMinutes']! as int,
    minimumOrderPaise: json['minimumOrderPaise']! as int,
    maxQuantityPerLine: json['maxQuantityPerLine']! as int,
    maxLines: json['maxLines']! as int,
  );

  final List<String> fulfilment;
  final int slotMinutes;
  final int prepMinutes;
  final int minimumOrderPaise;
  final int maxQuantityPerLine;
  final int maxLines;
}

class Charges {
  const Charges({
    required this.packagingPaise,
    required this.gstBasisPoints,
    required this.gstNote,
    required this.freeDeliveryAbovePaise,
    required this.deliveryPincodes,
  });

  factory Charges.fromJson(Json json) {
    final delivery = json['delivery']! as Json;
    return Charges(
      packagingPaise: json['packagingPaise']! as int,
      gstBasisPoints: json['gstBasisPoints']! as int,
      gstNote: json['gstNote']! as String,
      freeDeliveryAbovePaise: delivery['freeAbovePaise'] as int?,
      deliveryPincodes: {
        for (final p in delivery['pincodes']! as List)
          (p as Json)['pincode']! as String: p['feePaise']! as int,
      },
    );
  }

  final int packagingPaise;
  final int gstBasisPoints;
  final String gstNote;
  final int? freeDeliveryAbovePaise;

  /// Pincode -> delivery fee in paise. Delivery goes only to these.
  final Map<String, int> deliveryPincodes;
}

/// `GET /offers`: a coupon the customer could use now.
class Offer {
  const Offer({required this.code, required this.description, required this.firstOrderOnly});

  factory Offer.fromJson(Json json) => Offer(
    code: json['code']! as String,
    description: json['description']! as String,
    firstOrderOnly: json['firstOrderOnly'] as bool? ?? false,
  );

  final String code;
  final String description;
  final bool firstOrderOnly;
}

/// `GET /slots` (and `quote.slots`): when an order can be ready.
class SlotOptions {
  const SlotOptions({required this.asap, required this.slots});

  factory SlotOptions.fromJson(Json json) => SlotOptions(
    asap: parseInstantOrNull(json['asap']),
    slots: [for (final s in json['slots']! as List) Slot.fromJson(s as Json)],
  );

  static const empty = SlotOptions(asap: null, slots: []);

  /// When an ASAP order would be ready, or null if nothing has room.
  final DateTime? asap;
  final List<Slot> slots;

  /// Slots grouped by the restaurant-local date, in order.
  Map<String, List<Slot>> get byDate {
    final groups = <String, List<Slot>>{};
    for (final slot in slots) {
      (groups[slot.date] ??= []).add(slot);
    }
    return groups;
  }

  bool offers(String value) => slots.any((s) => s.value == value && !s.full);
}

class Slot {
  const Slot({required this.value, required this.date, required this.startsAt, required this.full});

  factory Slot.fromJson(Json json) => Slot(
    value: json['value']! as String,
    date: json['date']! as String,
    startsAt: parseInstant(json['startsAt']! as String),
    full: json['full'] as bool? ?? false,
  );

  /// What to send as `slot` when ordering.
  final String value;

  /// Restaurant-local `YYYY-MM-DD`.
  final String date;
  final DateTime startsAt;
  final bool full;
}
