import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/session.dart';
import '../../../core/live/live_status.dart';
import '../../../core/providers.dart';
import '../../menu/data/menu_repository.dart';
import 'board.dart';

class KitchenRepository {
  const KitchenRepository(this._api);

  final ApiClient _api;

  Future<StaffSession> signIn(String email, String password) async => StaffSession.fromSignIn(
    (await _api.post('/staff/sign-in', body: {'email': email.trim(), 'password': password}))!,
  );

  /// Demo only: one-tap sign-in as the demo kitchen or manager.
  Future<StaffSession> demoSignIn(StaffRole role) async =>
      StaffSession.fromSignIn((await _api.post('/staff/demo-sign-in', body: {'role': role.wire}))!);

  Future<void> signOut() async {
    try {
      await _api.post('/staff/sign-out', auth: AuthKind.staff);
    } on ApiException catch (e) {
      if (!e.isUnauthenticated) rethrow;
    }
  }

  Future<Board> board() async => Board.fromJson(await _api.get('/kitchen/board', auth: AuthKind.staff));

  /// Moves an order on: normally to its `kitchenNext`, or to `REJECTED` with a reason.
  Future<void> move(String code, String to, {String? reason}) async {
    await _api.post('/kitchen/orders/$code/move', body: {'to': to, 'reason': ?reason}, auth: AuthKind.staff);
  }

  Future<void> setAvailability(int itemId, {required bool available}) async {
    await _api.post(
      '/kitchen/menu/$itemId/availability',
      body: {'available': available},
      auth: AuthKind.staff,
    );
  }
}

final kitchenRepositoryProvider = Provider((ref) => KitchenRepository(ref.watch(apiClientProvider)));

/// Staff sign-in and sign-out, keeping the staff session apart from the customer's.
final staffAuthProvider = Provider(StaffAuth.new);

class StaffAuth {
  StaffAuth(this._ref);

  final Ref _ref;

  KitchenRepository get _repo => _ref.read(kitchenRepositoryProvider);

  Future<void> signIn(String email, String password) async =>
      _ref.read(staffSessionProvider.notifier).save(await _repo.signIn(email, password));

  Future<void> demoSignIn(StaffRole role) async =>
      _ref.read(staffSessionProvider.notifier).save(await _repo.demoSignIn(role));

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } on ApiException {
      // Offline: dropped here anyway; it expires on the server at the end of the shift.
    }
    await _ref.read(staffSessionProvider.notifier).clear();
  }
}

final boardProvider = AsyncNotifierProvider.autoDispose<BoardNotifier, Board>(BoardNotifier.new);

class BoardNotifier extends AsyncNotifier<Board> {
  KitchenRepository get _repo => ref.read(kitchenRepositoryProvider);

  @override
  Future<Board> build() {
    ref.watch(staffSessionProvider.select((s) => s?.staff.id));
    return _repo.board();
  }

  /// Fetches again without a loading state, and signals any order that just arrived.
  Future<void> refreshQuietly() async {
    final before = state.value?.codes;
    final result = await AsyncValue.guard(_repo.board);
    if (!ref.mounted) return;
    if (result.hasValue || !state.hasValue) state = result;
    final after = result.value;
    if (before != null && after != null) {
      final arrived =
          after.current.where((t) => !before.contains(t.code)).length +
          after.later.where((t) => !before.contains(t.code)).length;
      if (arrived > 0) ref.read(newOrderSignalProvider.notifier).bump();
    }
  }

  /// Moves an order on, then refreshes. A `409` (someone else moved it) refreshes too and is
  /// rethrown so the screen can say so.
  Future<void> move(String code, String to, {String? reason}) async {
    try {
      await _repo.move(code, to, reason: reason);
    } finally {
      await refreshQuietly();
    }
  }
}

/// Counts orders arriving on the board, for the new-order chime and haptic.
final newOrderSignalProvider = NotifierProvider<NewOrderSignal, int>(NewOrderSignal.new);

class NewOrderSignal extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Whether the new-order chime is on (kitchen tablets usually want it; it can be muted).
final kitchenSoundProvider = NotifierProvider<KitchenSound, bool>(KitchenSound.new);

class KitchenSound extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

/// The kitchen's live stream: every order change refreshes the board.
final kitchenLiveProvider = NotifierProvider.autoDispose<KitchenLive, LiveStatus>(KitchenLive.new);

class KitchenLive extends Notifier<LiveStatus> {
  @override
  LiveStatus build() {
    final staffId = ref.watch(staffSessionProvider.select((s) => s?.staff.id));
    if (staffId == null) return LiveStatus.off;
    return followLive(
      ref,
      (status) => state = status,
      path: '/kitchen/events',
      auth: AuthKind.staff,
      onChange: (_) => ref.read(boardProvider.notifier).refreshQuietly(),
    );
  }
}

/// Dish availability changes for the sold-out screen.
final availabilityProvider = Provider(AvailabilityController.new);

class AvailabilityController {
  AvailabilityController(this._ref);

  final Ref _ref;

  Future<void> set(int itemId, {required bool available}) async {
    await _ref.read(kitchenRepositoryProvider).setAvailability(itemId, available: available);
    // The menu is shared with customer mode: both see the change at once.
    _ref.invalidate(menuProvider);
  }
}

/// Ticks every 20 seconds so "late" and "due in" labels stay true between fetches.
final kitchenClockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final now = ref.read(clockProvider);
  yield now();
  yield* Stream.periodic(const Duration(seconds: 20), (_) => now());
});
