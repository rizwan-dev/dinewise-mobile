import 'dart:async';
import 'dart:convert';

import 'package:dinewise/core/api/api_client.dart';
import 'package:dinewise/core/format/money.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

/// An in-memory Dinewise `/api/v1`, following the contract in `docs/api.md` of the web repo
/// closely enough for widget tests: the demo menu and restaurant (recorded), quotes with the
/// real charges, one-time codes, orders, the kitchen board and both event streams.
class FakeApi {
  FakeApi() {
    restaurant = fixture('restaurant');
    menu = menuJson(photos: false);
    offers = fixture('offers');
  }

  static const demoCode = '645104';
  static const customerToken = 'customer-token';
  static const staffToken = 'staff-token';

  late final Json restaurant;
  late final Json menu;
  late final Json offers;

  /// Every request seen, as "METHOD /path".
  final requests = <String>[];

  /// When true, every request fails as if the phone were offline.
  bool offline = false;

  /// When set, the next `POST /orders` fails with this code (`SLOT_FULL`…).
  String? failNextOrder;

  String? customerName;
  final addresses = <Json>[];
  final _orders = <String, Json>{};
  var _orderCount = 0;
  final _orderStreams = <String, List<StreamController<List<int>>>>{};
  final _kitchenStreams = <StreamController<List<int>>>[];
  final _now = DateTime.utc(2026, 10, 5, 6, 53);

  http.Client client() => MockClient.streaming(_handle);

  Iterable<Json> get _dishes => [
    for (final s in menu['sections']! as List)
      for (final i in (s as Json)['items']! as List) i as Json,
  ];

  Json? _dish(int id) => _dishes.where((d) => d['id'] == id).firstOrNull;

  /// Marks a dish sold out or back, as the kitchen's switch does.
  void setAvailable(int itemId, bool available) => _dish(itemId)!['available'] = available;

  Json order(String code) => _orders[code]!;

  /// Moves an order (as the kitchen would) and tells both streams.
  void move(String code, String to, {String? reason}) {
    final o = _orders[code]!;
    o['status'] = to;
    o['rejectReason'] = reason;
    (o['timeline']! as List).add({
      'status': to,
      'label': _labels[to],
      'actor': 'KITCHEN',
      'note': reason,
      'at': _now.add(const Duration(minutes: 1)).toIso8601String(),
    });
    _decorate(o);
    final event = utf8.encode(
      'event: order\ndata: ${jsonEncode({'id': 1, 'code': code, 'status': to, 'paymentStatus': 'NOT_REQUIRED'})}\n\n',
    );
    for (final c in [...?_orderStreams[code], ..._kitchenStreams]) {
      if (!c.isClosed) c.add(event);
    }
  }

  /// Ends every open stream, as the server does after ~4.5 minutes.
  Future<void> endStreams() async {
    for (final c in [..._orderStreams.values.expand((l) => l), ..._kitchenStreams]) {
      await c.close();
    }
    _orderStreams.clear();
    _kitchenStreams.clear();
  }

  Future<http.StreamedResponse> _handle(http.BaseRequest request, http.ByteStream bodyStream) async {
    if (offline) throw http.ClientException('Connection refused', request.url);
    final path = request.url.path.replaceFirst('/api/v1', '');
    requests.add('${request.method} $path');
    final text = await bodyStream.bytesToString();
    final body = text.isEmpty ? null : jsonDecode(text) as Json;
    final auth = request.headers['Authorization'];
    final customer = auth == 'Bearer $customerToken';
    final staff = auth == 'Bearer $staffToken';

    http.StreamedResponse json(Object? value, [int status = 200]) => http.StreamedResponse(
      Stream.value(value == null ? <int>[] : utf8.encode(jsonEncode(value))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    http.StreamedResponse error(int status, String code, String message, [String? field]) => json({
      'error': {'code': code, 'message': message, 'field': ?field},
    }, status);
    http.StreamedResponse unauthenticated() => error(401, 'UNAUTHENTICATED', 'Please sign in again.');

    final m = request.method;
    final orderMatch = RegExp(r'^/orders/(TL-[A-Z0-9]+)(/cancel|/events)?$').firstMatch(path);
    final moveMatch = RegExp(r'^/kitchen/orders/(TL-[A-Z0-9]+)/move$').firstMatch(path);
    final availabilityMatch = RegExp(r'^/kitchen/menu/(\d+)/availability$').firstMatch(path);

    switch ((m, path)) {
      case ('GET', '/restaurant'):
        return json(restaurant);
      case ('GET', '/menu'):
        return json(menu);
      case ('GET', '/offers'):
        return json(offers);
      case ('GET', '/slots'):
        return json(_slots());
      case ('POST', '/quote'):
        return json(_quote(body!, signedIn: customer));
      case ('POST', '/auth/otp'):
        final digits = (body!['phone']! as String).replaceAll(RegExp(r'\D'), '');
        final national = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
        if (national.length != 10) {
          return error(400, 'INVALID_PHONE', 'Enter a 10-digit Indian mobile number.', 'phone');
        }
        return json({'phone': '+91$national', 'expiresInSeconds': 300, 'demoCode': demoCode});
      case ('POST', '/auth/otp/verify'):
        if (body!['code'] != demoCode) {
          return error(422, 'WRONG_CODE', 'That code is not right. 4 tries left.', 'code');
        }
        return json({
          'accessToken': customerToken,
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'isNewCustomer': customerName == null,
          'customer': {'id': 25, 'phone': body['phone'], 'name': customerName},
        });
      case ('POST', '/auth/sign-out'):
        return customer ? json(null, 204) : unauthenticated();
      case ('GET', '/me'):
        if (!customer) return unauthenticated();
        return json({
          'customer': {'id': 25, 'phone': '+919822022314', 'name': customerName},
          'addresses': addresses,
        });
      case ('POST', '/orders'):
        if (!customer) return unauthenticated();
        return _placeOrder(body!, json, error);
      case ('GET', '/orders'):
        if (!customer) return unauthenticated();
        return json({
          'currency': 'INR',
          'orders': [
            for (final o in _orders.values.toList().reversed)
              {
                for (final k in [
                  'code',
                  'status',
                  'statusLabel',
                  'final',
                  'fulfilment',
                  'readyBy',
                  'createdAt',
                ])
                  k: o[k],
                'totalPaise': (o['totals']! as Json)['totalPaise'],
              },
          ],
        });
      case ('POST', '/staff/demo-sign-in'):
        final role = body!['role'];
        return json({
          'accessToken': staffToken,
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'staff': {
            'id': role == 'MANAGER' ? 1 : 2,
            'name': role == 'MANAGER' ? 'Manager' : 'Kitchen',
            'email': '${(role as String).toLowerCase()}@tadkalane.example',
            'role': role,
          },
        });
      case ('POST', '/staff/sign-in'):
        if (body!['password'] != 'tadka-demo-2026') {
          return error(401, 'INVALID_CREDENTIALS', 'Email or password is incorrect.');
        }
        return json({
          'accessToken': staffToken,
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'staff': {'id': 2, 'name': 'Kitchen', 'email': body['email'], 'role': 'KITCHEN'},
        });
      case ('POST', '/staff/sign-out'):
        return staff ? json(null, 204) : unauthenticated();
      case ('GET', '/kitchen/board'):
        if (!staff) return unauthenticated();
        return json(_board());
      case ('GET', '/kitchen/events'):
        if (!staff) return unauthenticated();
        return _stream(_kitchenStreams);
    }

    if (orderMatch != null) {
      if (!customer) return unauthenticated();
      final code = orderMatch.group(1)!;
      final o = _orders[code];
      if (o == null) return error(404, 'ORDER_NOT_FOUND', 'We could not find that order.');
      switch (orderMatch.group(2)) {
        case null:
          return json({'order': o});
        case '/cancel':
          if (o['status'] != 'PLACED') {
            return error(
              409,
              'INVALID_TRANSITION',
              'The kitchen has started on this order, so it can no longer be cancelled.',
            );
          }
          move(code, 'CANCELLED');
          return json({'order': o});
        case '/events':
          return _stream(_orderStreams.putIfAbsent(code, () => []));
      }
    }
    if (moveMatch != null) {
      if (!staff) return unauthenticated();
      final code = moveMatch.group(1)!;
      final to = body!['to']! as String;
      final o = _orders[code];
      if (o == null) return error(404, 'ORDER_NOT_FOUND', 'We could not find that order.');
      if (to == 'REJECTED' && (body['reason'] as String?) == null) {
        return error(422, 'REASON_REQUIRED', 'Say why the order is rejected.', 'note');
      }
      if (to != 'REJECTED' && _next(o) != to) {
        return error(
          409,
          'INVALID_TRANSITION',
          'This order has already moved on. Refresh to see its current state.',
        );
      }
      move(code, to, reason: body['reason'] as String?);
      return json({'code': code, 'status': to, 'statusLabel': _labels[to], 'kitchenNext': _next(o)});
    }
    if (availabilityMatch != null) {
      if (!staff) return unauthenticated();
      final id = int.parse(availabilityMatch.group(1)!);
      if (_dish(id) == null) return error(404, 'NOT_FOUND', 'No such dish.');
      setAvailable(id, body!['available']! as bool);
      return json({'itemId': id, 'available': body['available']});
    }
    return error(404, 'NOT_FOUND', 'No such endpoint: $m $path');
  }

  http.StreamedResponse _stream(List<StreamController<List<int>>> listeners) {
    final controller = StreamController<List<int>>();
    listeners.add(controller);
    controller.add(utf8.encode('retry: 3000\n\n'));
    return http.StreamedResponse(controller.stream, 200, headers: {'content-type': 'text/event-stream'});
  }

  Json _slots() => {
    'asap': '2026-10-05T07:30:00.000Z',
    'slots': [
      for (var i = 0; i < 6; i++)
        {
          'value': _now.add(Duration(minutes: 37 + 15 * i)).toIso8601String(),
          'date': '2026-10-05',
          'startsAt': _now.add(Duration(minutes: 37 + 15 * i)).toIso8601String(),
          'full': i == 2,
        },
    ],
  };

  Json _quote(Json body, {required bool signedIn}) {
    Json fail(String code, String message) => {
      'currency': 'INR',
      'ok': false,
      'problem': {'code': code, 'message': message},
      'coupon': {'applied': false, 'code': null, 'problem': null},
      'lines': <Object>[],
      'totals': null,
      'slots': _slots(),
    };

    final lines = <Json>[];
    var subtotal = 0;
    for (final l in body['lines']! as List) {
      final line = l as Json;
      final dish = _dish(line['itemId']! as int);
      if (dish == null) return fail('UNKNOWN_ITEM', 'That dish is no longer on the menu.');
      if (dish['available'] != true) return fail('UNAVAILABLE', '${dish['name']} is sold out right now.');
      final variants = dish['variants']! as List;
      Json? variant;
      if (variants.isNotEmpty) {
        variant = variants.cast<Json>().where((v) => v['id'] == line['variantId']).firstOrNull;
        if (variant == null) return fail('CHOOSE_VARIANT', 'Choose a size for ${dish['name']}.');
      }
      final addonIds = (line['addonIds'] as List?)?.cast<int>() ?? const [];
      final addons = [
        for (final g in dish['addonGroups']! as List)
          for (final a in (g as Json)['addons']! as List)
            if (addonIds.contains((a as Json)['id'])) a,
      ];
      final unit = (variant?['pricePaise'] ?? dish['pricePaise'])! as int;
      final unitTotal = unit + addons.fold<int>(0, (s, a) => s + (a['pricePaise']! as int));
      final quantity = line['quantity']! as int;
      subtotal += unitTotal * quantity;
      lines.add({
        'itemId': dish['id'],
        'name': dish['name'],
        'variantId': variant?['id'],
        'variantName': variant?['name'],
        'addons': addons,
        'quantity': quantity,
        'unitPricePaise': unitTotal,
        'lineTotalPaise': unitTotal * quantity,
      });
    }
    if (lines.isEmpty) return fail('EMPTY_CART', 'Your cart is empty.');

    final charges = restaurant['charges']! as Json;
    final delivery = charges['delivery']! as Json;
    var deliveryFee = 0;
    if (body['fulfilment'] == 'DELIVERY') {
      final pin = (delivery['pincodes']! as List)
          .cast<Json>()
          .where((p) => p['pincode'] == body['pincode'])
          .firstOrNull;
      if (pin == null) {
        return fail('NO_DELIVERY', 'We do not deliver to that pincode yet. Pickup is available.');
      }
      deliveryFee = subtotal >= (delivery['freeAbovePaise']! as int) ? 0 : pin['feePaise']! as int;
    }
    if (subtotal < 20000) return fail('MINIMUM_ORDER', 'The minimum order is ₹200.');

    final code = (body['couponCode'] as String?)?.replaceAll(' ', '').toUpperCase();
    var discount = 0;
    Json coupon = {'applied': false, 'code': null, 'problem': null};
    if (code != null) {
      Json problem(String c, String msg) => {
        'applied': false,
        'code': null,
        'problem': {'code': c, 'message': msg},
      };
      if (code == 'WELCOME50') {
        if (signedIn && _orders.isNotEmpty) {
          coupon = problem('COUPON_FIRST_ORDER_ONLY', 'WELCOME50 is for your first order only.');
        } else {
          discount = 5000;
          coupon = {'applied': true, 'code': code, 'problem': null};
        }
      } else if (code == 'TADKA10') {
        if (subtotal < 50000) {
          coupon = problem('COUPON_MIN_ORDER', 'TADKA10 needs an item total of ₹500 or more.');
        } else {
          discount = (subtotal ~/ 10).clamp(0, 10000);
          coupon = {'applied': true, 'code': code, 'problem': null};
        }
      } else {
        coupon = problem('COUPON_NOT_FOUND', '$code is not a valid code.');
      }
    }
    final packing = charges['packagingPaise']! as int;
    final tax = percentOf(subtotal - discount + packing + deliveryFee, charges['gstBasisPoints']! as int);
    return {
      'currency': 'INR',
      'ok': true,
      'problem': null,
      'coupon': coupon,
      'lines': lines,
      'totals': {
        'subtotalPaise': subtotal,
        'discountPaise': discount,
        'packagingPaise': packing,
        'deliveryFeePaise': deliveryFee,
        'taxPaise': tax,
        'totalPaise': subtotal - discount + packing + deliveryFee + tax,
      },
      'slots': _slots(),
    };
  }

  Future<http.StreamedResponse> _placeOrder(
    Json body,
    http.StreamedResponse Function(Object?, [int]) json,
    http.StreamedResponse Function(int, String, String, [String?]) error,
  ) async {
    if (failNextOrder != null) {
      final code = failNextOrder!;
      failNextOrder = null;
      return error(409, code, 'That time has just filled up. Please pick another.', 'slot');
    }
    if (body['paymentMethod'] == 'ONLINE') {
      return error(
        422,
        'ONLINE_PAYMENT_NOT_SUPPORTED',
        'Online payment is not available in the app yet.',
        'paymentMethod',
      );
    }
    final saved = addresses.where((a) => a['id'] == body['addressId']).firstOrNull;
    final fresh = body['newAddress'] as Json?;
    final pincode = saved != null ? saved['pincode'] : (fresh == null ? null : fresh['pincode']);
    final quote = _quote({...body, 'pincode': pincode}, signedIn: true);
    if (quote['ok'] != true) {
      final p = quote['problem']! as Json;
      return error(422, p['code']! as String, p['message']! as String);
    }
    final couponProblem = (quote['coupon']! as Json)['problem'] as Json?;
    if (couponProblem != null) {
      return error(422, couponProblem['code']! as String, couponProblem['message']! as String);
    }
    final name = body['name'] as String?;
    if (name != null) customerName = name;
    if (customerName == null) return error(400, 'INVALID', 'Please tell us your name.', 'name');

    Json? address;
    if (body['fulfilment'] == 'DELIVERY') {
      if (body['addressId'] != null) {
        address = addresses.where((a) => a['id'] == body['addressId']).firstOrNull;
        if (address == null) {
          return error(404, 'ADDRESS_NOT_FOUND', 'That address is no longer saved.', 'address');
        }
      } else if (body['newAddress'] is Json) {
        final n = body['newAddress']! as Json;
        address = {
          'label': n['label'] ?? 'Home',
          'line1': n['line1'],
          'line2': n['line2'],
          'pincode': n['pincode'],
          'landmark': n['landmark'],
        };
        if (body['saveAddress'] == true) addresses.add({'id': 12 + addresses.length, ...address});
      } else {
        return error(422, 'ADDRESS_REQUIRED', 'Add a delivery address.');
      }
    }

    _orderCount++;
    final code = 'TL-ABCD${const ['23', '24', '25', '26', '27', '28', '29', '32', '33'][_orderCount % 9]}';
    final created = _now.toIso8601String();
    final order = <String, Object?>{
      'code': code,
      'status': 'PLACED',
      'fulfilment': body['fulfilment'],
      'paymentMethod': 'ON_DELIVERY',
      'paymentStatus': 'NOT_REQUIRED',
      'readyBy': body['slot'] == 'ASAP' ? '2026-10-05T07:30:00.000Z' : body['slot'],
      'scheduled': body['slot'] != 'ASAP',
      'createdAt': created,
      'updatedAt': created,
      'customerName': customerName,
      'customerPhone': '+919822022314',
      'address': address,
      'notes': body['notes'],
      'currency': 'INR',
      'items': [
        for (final (i, l) in (quote['lines']! as List).cast<Json>().indexed) {'id': 160 + i, ...l},
      ],
      'couponCode': (quote['coupon']! as Json)['code'],
      'totals': quote['totals'],
      'rejectReason': null,
      'timeline': [
        {'status': 'PLACED', 'label': 'Order received', 'actor': 'CUSTOMER', 'note': null, 'at': created},
      ],
    };
    _decorate(order);
    _orders[code] = order;
    for (final c in _kitchenStreams) {
      c.add(
        utf8.encode(
          'event: order\ndata: {"id":1,"code":"$code","status":"PLACED","paymentStatus":"NOT_REQUIRED"}\n\n',
        ),
      );
    }
    return json({'order': order}, 201);
  }

  static const _labels = {
    'PLACED': 'Order received',
    'PREPARING': 'Being prepared',
    'READY': 'Ready',
    'OUT_FOR_DELIVERY': 'On the way',
    'DELIVERED': 'Delivered',
    'COLLECTED': 'Collected',
    'CANCELLED': 'Cancelled',
    'REJECTED': 'Could not be accepted',
  };
  static const _nextLabels = {
    'PREPARING': 'Start cooking',
    'READY': 'Mark ready',
    'OUT_FOR_DELIVERY': 'Out for delivery',
    'DELIVERED': 'Delivered',
    'COLLECTED': 'Collected',
  };

  static String? _next(Json o) {
    final delivery = o['fulfilment'] == 'DELIVERY';
    return switch (o['status']) {
      'PLACED' => 'PREPARING',
      'PREPARING' => 'READY',
      'READY' => delivery ? 'OUT_FOR_DELIVERY' : 'COLLECTED',
      'OUT_FOR_DELIVERY' => delivery ? 'DELIVERED' : null,
      _ => null,
    };
  }

  /// Fills the derived fields (labels, steps, final, canCancel, cash due).
  void _decorate(Json o) {
    final status = o['status']! as String;
    final delivery = o['fulfilment'] == 'DELIVERY';
    final flow = delivery
        ? ['PLACED', 'PREPARING', 'READY', 'OUT_FOR_DELIVERY', 'DELIVERED']
        : ['PLACED', 'PREPARING', 'READY', 'COLLECTED'];
    final isFinal = const {'DELIVERED', 'COLLECTED', 'CANCELLED', 'REJECTED', 'EXPIRED'}.contains(status);
    final at = flow.indexOf(status);
    o['statusLabel'] = _labels[status];
    o['final'] = isFinal;
    o['canCancel'] = status == 'PLACED';
    o['cashDuePaise'] = isFinal ? null : (o['totals']! as Json)['totalPaise'];
    o['steps'] = at == -1
        ? <Object>[]
        : [
            for (final (i, s) in flow.indexed)
              {
                'status': s,
                'label': _labels[s],
                'done': i < at || (isFinal && i == at),
                'current': i == at && !isFinal,
              },
          ];
  }

  Json _board() {
    final open = _orders.values.where(
      (o) => const {'PLACED', 'PREPARING', 'READY', 'OUT_FOR_DELIVERY'}.contains(o['status']),
    );
    return {
      'serverTime': _now.toIso8601String(),
      'currency': 'INR',
      'rejectReasons': ['Item out of stock', 'Kitchen too busy', 'Outside delivery area', 'Closing soon'],
      'current': [
        for (final o in open)
          {
            'code': o['code'],
            'status': o['status'],
            'fulfilment': o['fulfilment'],
            'customerName': o['customerName'],
            'dueAt': o['readyBy'],
            'placedAt': o['createdAt'],
            'later': false,
            'late': false,
            'paidOnline': false,
            'totalPaise': (o['totals']! as Json)['totalPaise'],
            'cashToCollectPaise': (o['totals']! as Json)['totalPaise'],
            'notes': o['notes'],
            'pincode': (o['address'] as Json?)?['pincode'],
            'items': [
              for (final i in o['items']! as List)
                {
                  'id': (i as Json)['id'],
                  'quantity': i['quantity'],
                  'name': i['name'],
                  'details': [
                    ?i['variantName'],
                    for (final a in i['addons']! as List) (a as Json)['name'],
                  ].join(' · '),
                },
            ],
            'kitchenNext': _next(o),
            'kitchenNextLabel': _nextLabels[_next(o)],
            'canReject': o['status'] == 'PLACED' || o['status'] == 'PREPARING',
          },
      ],
      'later': <Object>[],
    };
  }
}
