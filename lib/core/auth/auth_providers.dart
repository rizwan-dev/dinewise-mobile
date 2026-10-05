import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'session.dart';
import 'token_store.dart';

const customerSessionKey = 'dinewise.customer_session';
const staffSessionKey = 'dinewise.staff_session';

/// Sessions as read from secure storage at launch (see `bootstrap`). Overridden in `main`.
final initialCustomerSessionProvider = Provider<CustomerSession?>((ref) => null);
final initialStaffSessionProvider = Provider<StaffSession?>((ref) => null);

final tokenStoreProvider = Provider<TokenStore>((ref) => MemoryTokenStore());

/// Reads both sessions before the first frame, dropping any that have expired.
Future<(CustomerSession?, StaffSession?)> loadSessions(TokenStore store, DateTime now) async {
  var customer = CustomerSession.decode(await store.read(customerSessionKey));
  var staff = StaffSession.decode(await store.read(staffSessionKey));
  if (customer != null && customer.isExpired(now)) {
    customer = null;
    await store.delete(customerSessionKey);
  }
  if (staff != null && staff.isExpired(now)) {
    staff = null;
    await store.delete(staffSessionKey);
  }
  return (customer, staff);
}

/// The signed-in customer, or null. Kept apart from the staff session: one phone can be signed
/// in as both, and signing out of one leaves the other.
final customerSessionProvider = NotifierProvider<CustomerSessionNotifier, CustomerSession?>(
  CustomerSessionNotifier.new,
);

class CustomerSessionNotifier extends Notifier<CustomerSession?> {
  @override
  CustomerSession? build() => ref.read(initialCustomerSessionProvider);

  Future<void> save(CustomerSession session) async {
    state = session;
    await ref.read(tokenStoreProvider).write(customerSessionKey, session.encode());
  }

  /// Signed out, or the server said the token is dead (`401`).
  Future<void> clear() async {
    if (state == null) return;
    state = null;
    await ref.read(tokenStoreProvider).delete(customerSessionKey);
  }

  /// Expiry is checked lazily: a token past `expiresAt` is dropped before use.
  String? get liveToken {
    final session = state;
    if (session == null) return null;
    if (session.isExpired(ref.read(clockProvider)())) {
      clear();
      return null;
    }
    return session.token;
  }
}

final staffSessionProvider = NotifierProvider<StaffSessionNotifier, StaffSession?>(StaffSessionNotifier.new);

class StaffSessionNotifier extends Notifier<StaffSession?> {
  @override
  StaffSession? build() => ref.read(initialStaffSessionProvider);

  Future<void> save(StaffSession session) async {
    state = session;
    await ref.read(tokenStoreProvider).write(staffSessionKey, session.encode());
  }

  Future<void> clear() async {
    if (state == null) return;
    state = null;
    await ref.read(tokenStoreProvider).delete(staffSessionKey);
  }

  String? get liveToken {
    final session = state;
    if (session == null) return null;
    if (session.isExpired(ref.read(clockProvider)())) {
      clear();
      return null;
    }
    return session.token;
  }
}
