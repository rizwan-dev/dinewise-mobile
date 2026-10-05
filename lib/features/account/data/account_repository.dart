import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/session.dart';
import '../../../core/providers.dart';

/// `POST /auth/otp`'s answer.
class OtpSent {
  const OtpSent({required this.phone, required this.expiresInSeconds, this.demoCode});

  factory OtpSent.fromJson(Json json) => OtpSent(
    phone: json['phone']! as String,
    expiresInSeconds: json['expiresInSeconds'] as int? ?? 300,
    demoCode: json['demoCode'] as String?,
  );

  /// E.164.
  final String phone;
  final int expiresInSeconds;

  /// Only on the public demo, which sends no SMS.
  final String? demoCode;
}

class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.line1,
    required this.pincode,
    this.line2,
    this.landmark,
  });

  factory SavedAddress.fromJson(Json json) => SavedAddress(
    id: json['id']! as int,
    label: json['label'] as String? ?? 'Home',
    line1: json['line1']! as String,
    line2: json['line2'] as String?,
    landmark: json['landmark'] as String?,
    pincode: json['pincode']! as String,
  );

  final int id;
  final String label;
  final String line1;
  final String? line2;
  final String? landmark;
  final String pincode;

  String get oneLine =>
      [line1, line2, landmark, pincode].whereType<String>().where((s) => s.isNotEmpty).join(', ');
}

class Me {
  const Me({required this.customer, required this.addresses});

  factory Me.fromJson(Json json) => Me(
    customer: Customer.fromJson(json['customer']! as Json),
    addresses: [for (final a in json['addresses'] as List? ?? const []) SavedAddress.fromJson(a as Json)],
  );

  final Customer customer;
  final List<SavedAddress> addresses;
}

class AccountRepository {
  const AccountRepository(this._api);

  final ApiClient _api;

  Future<OtpSent> sendCode(String phone) async =>
      OtpSent.fromJson((await _api.post('/auth/otp', body: {'phone': phone}))!);

  Future<(CustomerSession, bool isNew)> verify({
    required String phone,
    required String code,
    String? name,
  }) async {
    final json = (await _api.post(
      '/auth/otp/verify',
      body: {
        'phone': phone,
        'code': code.replaceAll(RegExp(r'\s'), ''),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    ))!;
    return (CustomerSession.fromSignIn(json), json['isNewCustomer'] as bool? ?? false);
  }

  Future<Me> me() async => Me.fromJson(await _api.get('/me', auth: AuthKind.customer));

  Future<void> signOut() async {
    try {
      await _api.post('/auth/sign-out', auth: AuthKind.customer);
    } on ApiException catch (e) {
      // Already revoked or expired: signed out either way.
      if (!e.isUnauthenticated) rethrow;
    }
  }
}

final accountRepositoryProvider = Provider((ref) => AccountRepository(ref.watch(apiClientProvider)));

/// The customer and their saved addresses. Re-fetched when the signed-in customer changes.
final meProvider = FutureProvider.autoDispose<Me?>((ref) async {
  final id = ref.watch(customerSessionProvider.select((s) => s?.customer.id));
  if (id == null) return null;
  return ref.watch(accountRepositoryProvider).me();
});

/// Customer sign-in and sign-out: the repository calls plus keeping the session.
final customerAuthProvider = Provider(CustomerAuth.new);

class CustomerAuth {
  CustomerAuth(this._ref);

  final Ref _ref;

  AccountRepository get _repo => _ref.read(accountRepositoryProvider);

  Future<OtpSent> sendCode(String phone) => _repo.sendCode(phone);

  /// Checks the code and keeps the session. Returns whether the customer still needs a name.
  Future<bool> verify({required String phone, required String code, String? name}) async {
    final (session, _) = await _repo.verify(phone: phone, code: code, name: name);
    await _ref.read(customerSessionProvider.notifier).save(session);
    return session.customer.name == null;
  }

  /// Signs out on the server, then drops the token here whatever the server said.
  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } on ApiException {
      // Offline: the token is dropped here anyway and expires on the server by itself.
    }
    await _ref.read(customerSessionProvider.notifier).clear();
  }
}
