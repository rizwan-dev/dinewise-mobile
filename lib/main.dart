import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_providers.dart';
import 'core/auth/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecureTokenStore();
  final (customer, staff) = await loadSessions(store, DateTime.now());

  runApp(
    ProviderScope(
      // Errors are shown with a Retry button; nothing retries behind the user's back.
      retry: (_, _) => null,
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        initialCustomerSessionProvider.overrideWithValue(customer),
        initialStaffSessionProvider.overrideWithValue(staff),
      ],
      child: const DinewiseApp(),
    ),
  );
}
