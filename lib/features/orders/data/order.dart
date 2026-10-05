import '../../../core/api/api_client.dart';
import '../../../core/format/time.dart';
import '../../cart/data/cart.dart';
import '../../cart/data/quote.dart';

/// Order statuses. Unknown future statuses parse as [unknown] rather than failing.
enum OrderStatus {
  awaitingPayment('AWAITING_PAYMENT'),
  placed('PLACED'),
  preparing('PREPARING'),
  ready('READY'),
  outForDelivery('OUT_FOR_DELIVERY'),
  delivered('DELIVERED'),
  collected('COLLECTED'),
  cancelled('CANCELLED'),
  rejected('REJECTED'),
  expired('EXPIRED'),
  unknown('UNKNOWN');

  const OrderStatus(this.wire);

  final String wire;

  static OrderStatus parse(String? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => unknown);

  bool get isFinal => switch (this) {
    delivered || collected || cancelled || rejected || expired => true,
    _ => false,
  };

  bool get isProblem => this == cancelled || this == rejected || this == expired;
}

/// A row of `GET /orders`.
class OrderSummary {
  const OrderSummary({
    required this.code,
    required this.status,
    required this.statusLabel,
    required this.isFinal,
    required this.fulfilment,
    required this.totalPaise,
    required this.readyBy,
    required this.createdAt,
  });

  factory OrderSummary.fromJson(Json json) => OrderSummary(
    code: json['code']! as String,
    status: OrderStatus.parse(json['status'] as String?),
    statusLabel: json['statusLabel'] as String? ?? '',
    isFinal: json['final'] as bool? ?? false,
    fulfilment: Fulfilment.parse(json['fulfilment']! as String),
    totalPaise: json['totalPaise']! as int,
    readyBy: parseInstantOrNull(json['readyBy']),
    createdAt: parseInstant(json['createdAt']! as String),
  );

  final String code;
  final OrderStatus status;
  final String statusLabel;
  final bool isFinal;
  final Fulfilment fulfilment;
  final int totalPaise;
  final DateTime? readyBy;
  final DateTime createdAt;
}

class OrderStep {
  const OrderStep({required this.status, required this.label, required this.done, required this.current});

  factory OrderStep.fromJson(Json json) => OrderStep(
    status: OrderStatus.parse(json['status'] as String?),
    label: json['label']! as String,
    done: json['done'] as bool? ?? false,
    current: json['current'] as bool? ?? false,
  );

  final OrderStatus status;
  final String label;
  final bool done;
  final bool current;
}

class TimelineEntry {
  const TimelineEntry({
    required this.status,
    required this.label,
    required this.actor,
    required this.note,
    required this.at,
  });

  factory TimelineEntry.fromJson(Json json) => TimelineEntry(
    status: OrderStatus.parse(json['status'] as String?),
    label: json['label']! as String,
    actor: json['actor'] as String? ?? 'SYSTEM',
    note: json['note'] as String?,
    at: parseInstant(json['at']! as String),
  );

  final OrderStatus status;
  final String label;

  /// `CUSTOMER`, `KITCHEN` or `SYSTEM`.
  final String actor;
  final String? note;
  final DateTime at;
}

class OrderItem {
  const OrderItem({
    required this.name,
    required this.variantName,
    required this.addonNames,
    required this.quantity,
    required this.lineTotalPaise,
  });

  factory OrderItem.fromJson(Json json) => OrderItem(
    name: json['name']! as String,
    variantName: json['variantName'] as String?,
    addonNames: [for (final a in json['addons'] as List? ?? const []) (a as Json)['name']! as String],
    quantity: json['quantity']! as int,
    lineTotalPaise: json['lineTotalPaise']! as int,
  );

  final String name;
  final String? variantName;
  final List<String> addonNames;
  final int quantity;
  final int lineTotalPaise;

  String get optionsLabel => [?variantName, ...addonNames].join(' · ');
}

class OrderAddress {
  const OrderAddress({required this.label, required this.line1, this.line2, this.landmark, required this.pincode});

  factory OrderAddress.fromJson(Json json) => OrderAddress(
    label: json['label'] as String? ?? 'Home',
    line1: json['line1']! as String,
    line2: json['line2'] as String?,
    landmark: json['landmark'] as String?,
    pincode: json['pincode']! as String,
  );

  final String label;
  final String line1;
  final String? line2;
  final String? landmark;
  final String pincode;

  String get oneLine => [line1, line2, landmark, pincode].whereType<String>().where((s) => s.isNotEmpty).join(', ');
}

/// `GET /orders/{code}`: everything the order page shows.
class Order {
  const Order({
    required this.code,
    required this.status,
    required this.statusLabel,
    required this.isFinal,
    required this.fulfilment,
    required this.readyBy,
    required this.scheduled,
    required this.createdAt,
    required this.canCancel,
    required this.steps,
    required this.rejectReason,
    required this.customerName,
    required this.address,
    required this.notes,
    required this.items,
    required this.couponCode,
    required this.totals,
    required this.cashDuePaise,
    required this.timeline,
  });

  factory Order.fromJson(Json json) => Order(
    code: json['code']! as String,
    status: OrderStatus.parse(json['status'] as String?),
    statusLabel: json['statusLabel'] as String? ?? '',
    isFinal: json['final'] as bool? ?? false,
    fulfilment: Fulfilment.parse(json['fulfilment']! as String),
    readyBy: parseInstantOrNull(json['readyBy']),
    scheduled: json['scheduled'] as bool? ?? false,
    createdAt: parseInstant(json['createdAt']! as String),
    canCancel: json['canCancel'] as bool? ?? false,
    steps: [for (final s in json['steps'] as List? ?? const []) OrderStep.fromJson(s as Json)],
    rejectReason: json['rejectReason'] as String?,
    customerName: json['customerName'] as String?,
    address: json['address'] is Json ? OrderAddress.fromJson(json['address']! as Json) : null,
    notes: json['notes'] as String?,
    items: [for (final i in json['items'] as List? ?? const []) OrderItem.fromJson(i as Json)],
    couponCode: json['couponCode'] as String?,
    totals: Totals.fromJson(json['totals']! as Json),
    cashDuePaise: json['cashDuePaise'] as int?,
    timeline: [for (final t in json['timeline'] as List? ?? const []) TimelineEntry.fromJson(t as Json)],
  );

  final String code;
  final OrderStatus status;
  final String statusLabel;

  /// No more changes will come: stop listening.
  final bool isFinal;
  final Fulfilment fulfilment;
  final DateTime? readyBy;
  final bool scheduled;
  final DateTime createdAt;
  final bool canCancel;

  /// The progress bar; empty for cancelled, rejected and expired orders.
  final List<OrderStep> steps;
  final String? rejectReason;
  final String? customerName;

  /// Null for pickup.
  final OrderAddress? address;
  final String? notes;
  final List<OrderItem> items;
  final String? couponCode;
  final Totals totals;

  /// "Please keep ₹… ready in cash"; null once final.
  final int? cashDuePaise;
  final List<TimelineEntry> timeline;
}
