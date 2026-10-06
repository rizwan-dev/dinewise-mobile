import '../../../core/api/api_client.dart';
import '../../restaurant/data/restaurant.dart';

/// A `{code, message}` reason, as `/quote` reports cart and coupon problems.
class Problem {
  const Problem({required this.code, required this.message});

  factory Problem.fromJson(Json json) =>
      Problem(code: json['code']! as String, message: json['message']! as String);

  static Problem? maybe(Object? json) => json is Json ? Problem.fromJson(json) : null;

  final String code;
  final String message;
}

/// The bill. `total = subtotal − discount + packing + delivery + tax`.
class Totals {
  const Totals({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.packagingPaise,
    required this.deliveryFeePaise,
    required this.taxPaise,
    required this.totalPaise,
  });

  factory Totals.fromJson(Json json) => Totals(
    subtotalPaise: json['subtotalPaise']! as int,
    discountPaise: json['discountPaise'] as int? ?? 0,
    packagingPaise: json['packagingPaise'] as int? ?? 0,
    deliveryFeePaise: json['deliveryFeePaise'] as int? ?? 0,
    taxPaise: json['taxPaise'] as int? ?? 0,
    totalPaise: json['totalPaise']! as int,
  );

  final int subtotalPaise;
  final int discountPaise;
  final int packagingPaise;
  final int deliveryFeePaise;
  final int taxPaise;
  final int totalPaise;
}

class QuoteLine {
  const QuoteLine({
    required this.itemId,
    required this.name,
    required this.variantName,
    required this.addonNames,
    required this.quantity,
    required this.unitPricePaise,
    required this.lineTotalPaise,
  });

  factory QuoteLine.fromJson(Json json) => QuoteLine(
    itemId: json['itemId']! as int,
    name: json['name']! as String,
    variantName: json['variantName'] as String?,
    addonNames: [for (final a in json['addons'] as List? ?? const []) (a as Json)['name']! as String],
    quantity: json['quantity']! as int,
    unitPricePaise: json['unitPricePaise']! as int,
    lineTotalPaise: json['lineTotalPaise']! as int,
  );

  final int itemId;
  final String name;
  final String? variantName;
  final List<String> addonNames;
  final int quantity;
  final int unitPricePaise;
  final int lineTotalPaise;
}

class CouponResult {
  const CouponResult({required this.applied, this.code, this.problem});

  factory CouponResult.fromJson(Json json) => CouponResult(
    applied: json['applied'] as bool? ?? false,
    code: json['code'] as String?,
    problem: Problem.maybe(json['problem']),
  );

  final bool applied;
  final String? code;

  /// Why the coupon does not apply; the cart was priced without it.
  final Problem? problem;
}

/// `POST /quote`: the cart priced exactly as the web cart and checkout price it.
class Quote {
  const Quote({
    required this.ok,
    required this.problem,
    required this.coupon,
    required this.lines,
    required this.totals,
    required this.slots,
  });

  factory Quote.fromJson(Json json) => Quote(
    ok: json['ok']! as bool,
    problem: Problem.maybe(json['problem']),
    coupon: CouponResult.fromJson(json['coupon'] as Json? ?? const {}),
    lines: [for (final l in json['lines'] as List? ?? const []) QuoteLine.fromJson(l as Json)],
    totals: json['totals'] is Json ? Totals.fromJson(json['totals']! as Json) : null,
    slots: json['slots'] is Json ? SlotOptions.fromJson(json['slots']! as Json) : SlotOptions.empty,
  );

  /// False when the cart cannot be ordered as it is; [problem] says why.
  final bool ok;
  final Problem? problem;
  final CouponResult coupon;
  final List<QuoteLine> lines;

  /// Null when not [ok].
  final Totals? totals;
  final SlotOptions slots;
}
