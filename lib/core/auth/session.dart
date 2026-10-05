import 'dart:convert';

import '../api/api_client.dart';
import '../format/time.dart';

/// A signed-in customer, as `/auth/otp/verify` and `/me` return them.
class Customer {
  const Customer({required this.id, required this.phone, this.name});

  factory Customer.fromJson(Json json) => Customer(
    id: json['id']! as int,
    phone: json['phone']! as String,
    name: json['name'] as String?,
  );

  final int id;

  /// E.164, e.g. `+919822022314`.
  final String phone;

  /// Null until the customer gives one.
  final String? name;

  Json toJson() => {'id': id, 'phone': phone, 'name': name};

  Customer copyWith({String? name}) => Customer(id: id, phone: phone, name: name ?? this.name);

  /// "+91 98220 22314".
  String get displayPhone {
    final digits = phone.startsWith('+91') ? phone.substring(3) : phone;
    if (digits.length != 10) return phone;
    return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
  }
}

enum StaffRole {
  kitchen,
  manager;

  static StaffRole parse(String value) => value == 'MANAGER' ? manager : kitchen;

  String get wire => this == manager ? 'MANAGER' : 'KITCHEN';
  String get label => this == manager ? 'Manager' : 'Kitchen';
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory StaffMember.fromJson(Json json) => StaffMember(
    id: json['id']! as int,
    name: json['name']! as String,
    email: json['email']! as String,
    role: StaffRole.parse(json['role']! as String),
  );

  final int id;
  final String name;
  final String email;
  final StaffRole role;

  Json toJson() => {'id': id, 'name': name, 'email': email, 'role': role.wire};
}

/// An access token and when it stops working. There is no refresh token: sign in again.
sealed class Session {
  const Session({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  Json toJson();
  String encode() => jsonEncode(toJson());
}

class CustomerSession extends Session {
  const CustomerSession({required super.token, required super.expiresAt, required this.customer});

  /// From the `/auth/otp/verify` response.
  factory CustomerSession.fromSignIn(Json json) => CustomerSession(
    token: json['accessToken']! as String,
    expiresAt: parseInstant(json['expiresAt']! as String),
    customer: Customer.fromJson(json['customer']! as Json),
  );

  static CustomerSession? decode(String? stored) {
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored) as Json;
      return CustomerSession(
        token: json['token']! as String,
        expiresAt: parseInstant(json['expiresAt']! as String),
        customer: Customer.fromJson(json['customer']! as Json),
      );
    } on Object {
      return null;
    }
  }

  final Customer customer;

  CustomerSession withCustomer(Customer customer) =>
      CustomerSession(token: token, expiresAt: expiresAt, customer: customer);

  @override
  Json toJson() => {
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
    'customer': customer.toJson(),
  };
}

class StaffSession extends Session {
  const StaffSession({required super.token, required super.expiresAt, required this.staff});

  /// From the `/staff/sign-in` and `/staff/demo-sign-in` responses.
  factory StaffSession.fromSignIn(Json json) => StaffSession(
    token: json['accessToken']! as String,
    expiresAt: parseInstant(json['expiresAt']! as String),
    staff: StaffMember.fromJson(json['staff']! as Json),
  );

  static StaffSession? decode(String? stored) {
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored) as Json;
      return StaffSession(
        token: json['token']! as String,
        expiresAt: parseInstant(json['expiresAt']! as String),
        staff: StaffMember.fromJson(json['staff']! as Json),
      );
    } on Object {
      return null;
    }
  }

  final StaffMember staff;

  @override
  Json toJson() => {
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
    'staff': staff.toJson(),
  };
}
