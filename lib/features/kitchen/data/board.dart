import '../../../core/api/api_client.dart';
import '../../../core/format/time.dart';
import '../../cart/data/cart.dart';
import '../../orders/data/order.dart';

/// The board's columns, as on the web kitchen screen.
enum BoardColumn {
  newOrders('New', OrderStatus.placed),
  cooking('Cooking', OrderStatus.preparing),
  ready('Ready', OrderStatus.ready),
  out('Out', OrderStatus.outForDelivery);

  const BoardColumn(this.label, this.status);

  final String label;
  final OrderStatus status;
}

class TicketItem {
  const TicketItem({required this.quantity, required this.name, required this.details});

  factory TicketItem.fromJson(Json json) => TicketItem(
    quantity: json['quantity']! as int,
    name: json['name']! as String,
    details: json['details'] as String? ?? '',
  );

  final int quantity;
  final String name;

  /// Size and extras joined with " · ", or empty.
  final String details;
}

/// One order on the kitchen board.
class Ticket {
  const Ticket({
    required this.code,
    required this.status,
    required this.fulfilment,
    required this.customerName,
    required this.dueAt,
    required this.placedAt,
    required this.later,
    required this.paidOnline,
    required this.totalPaise,
    required this.cashToCollectPaise,
    required this.notes,
    required this.pincode,
    required this.items,
    required this.kitchenNext,
    required this.kitchenNextLabel,
    required this.canReject,
  });

  factory Ticket.fromJson(Json json) => Ticket(
    code: json['code']! as String,
    status: OrderStatus.parse(json['status'] as String?),
    fulfilment: Fulfilment.parse(json['fulfilment']! as String),
    customerName: json['customerName'] as String?,
    dueAt: parseInstant(json['dueAt']! as String),
    placedAt: parseInstant(json['placedAt']! as String),
    later: json['later'] as bool? ?? false,
    paidOnline: json['paidOnline'] as bool? ?? false,
    totalPaise: json['totalPaise']! as int,
    cashToCollectPaise: json['cashToCollectPaise'] as int?,
    notes: json['notes'] as String?,
    pincode: json['pincode'] as String?,
    items: [for (final i in json['items'] as List? ?? const []) TicketItem.fromJson(i as Json)],
    kitchenNext: json['kitchenNext'] as String?,
    kitchenNextLabel: json['kitchenNextLabel'] as String?,
    canReject: json['canReject'] as bool? ?? false,
  );

  final String code;
  final OrderStatus status;
  final Fulfilment fulfilment;
  final String? customerName;
  final DateTime dueAt;
  final DateTime placedAt;
  final bool later;
  final bool paidOnline;
  final int totalPaise;

  /// "Collect ₹… cash"; null when paid online.
  final int? cashToCollectPaise;
  final String? notes;
  final String? pincode;
  final List<TicketItem> items;

  /// The status the one big button sends to `move`, or null when there is no next step.
  final String? kitchenNext;
  final String? kitchenNextLabel;
  final bool canReject;

  /// Recomputed on the device as time passes: past due, not cooked yet, not scheduled later.
  bool isLate(DateTime now) =>
      !later && now.isAfter(dueAt) && (status == OrderStatus.placed || status == OrderStatus.preparing);

  int get itemCount => items.fold(0, (n, i) => n + i.quantity);
}

/// `GET /kitchen/board`.
class Board {
  const Board({
    required this.serverTime,
    required this.rejectReasons,
    required this.current,
    required this.later,
  });

  factory Board.fromJson(Json json) => Board(
    serverTime: parseInstant(json['serverTime']! as String),
    rejectReasons: [for (final r in json['rejectReasons'] as List? ?? const []) r as String],
    current: [for (final t in json['current'] as List? ?? const []) Ticket.fromJson(t as Json)],
    later: [for (final t in json['later'] as List? ?? const []) Ticket.fromJson(t as Json)],
  );

  final DateTime serverTime;
  final List<String> rejectReasons;

  /// The live columns, oldest due first.
  final List<Ticket> current;

  /// Scheduled more than an hour ahead.
  final List<Ticket> later;

  List<Ticket> column(BoardColumn column) => [
    for (final t in current)
      if (t.status == column.status) t,
  ];

  /// Codes of every order on the board, to spot new arrivals between fetches.
  Set<String> get codes => {for (final t in current) t.code, for (final t in later) t.code};
}
