import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'auth/auth_providers.dart';
import 'config/env.dart';

/// "Now", injectable so tests can pin the clock.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The HTTP client factory; tests swap in `MockClient`.
final httpClientFactoryProvider = Provider<http.Client Function()>((ref) => http.Client.new);

final apiBaseUrlProvider = Provider<String>((ref) => Env.apiBaseUrl);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    clientFactory: ref.watch(httpClientFactoryProvider),
    tokenFor: (kind) => switch (kind) {
      AuthKind.customer => ref.read(customerSessionProvider.notifier).liveToken,
      AuthKind.staff => ref.read(staffSessionProvider.notifier).liveToken,
      AuthKind.none => null,
    },
    onUnauthenticated: (kind) {
      switch (kind) {
        case AuthKind.customer:
          ref.read(customerSessionProvider.notifier).clear();
        case AuthKind.staff:
          ref.read(staffSessionProvider.notifier).clear();
        case AuthKind.none:
          break;
      }
    },
  );
  ref.onDispose(client.close);
  return client;
});

/// Whether the app is in the foreground. Live streams close in the background and reconnect,
/// with a fresh fetch, when the app comes back (as the website does when its tab is hidden).
final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void update(AppLifecycleState lifecycle) {
    final foreground = lifecycle == AppLifecycleState.resumed;
    // `inactive` (a call banner, the app switcher) is brief: keep streams open through it.
    if (lifecycle == AppLifecycleState.inactive) return;
    if (state != foreground) state = foreground;
  }
}
