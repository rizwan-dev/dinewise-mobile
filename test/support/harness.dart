import 'package:dinewise/app.dart';
import 'package:dinewise/core/auth/auth_providers.dart';
import 'package:dinewise/core/auth/session.dart';
import 'package:dinewise/core/auth/token_store.dart';
import 'package:dinewise/core/providers.dart';
import 'package:dinewise/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

final testNow = DateTime.utc(2026, 10, 5, 6, 53);

final signedInCustomer = CustomerSession(
  token: FakeApi.customerToken,
  expiresAt: DateTime.utc(2099),
  customer: const Customer(id: 25, phone: '+919822022314', name: 'Asha Kulkarni'),
);

final signedInKitchen = StaffSession(
  token: FakeApi.staffToken,
  expiresAt: DateTime.utc(2099),
  staff: const StaffMember(
    id: 2,
    name: 'Kitchen',
    email: 'kitchen@tadkalane.example',
    role: StaffRole.kitchen,
  ),
);

/// Starts the whole app against [api], optionally signed in and at [location].
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  FakeApi api, {
  CustomerSession? customer,
  StaffSession? staff,
  String? location,
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        apiBaseUrlProvider.overrideWithValue('http://fake.test/api/v1'),
        httpClientFactoryProvider.overrideWithValue(api.client),
        clockProvider.overrideWithValue(() => testNow),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        initialCustomerSessionProvider.overrideWithValue(customer),
        initialStaffSessionProvider.overrideWithValue(staff),
      ],
      child: const DinewiseApp(),
    ),
  );
  final container = ProviderScope.containerOf(tester.element(find.byType(DinewiseApp)));
  if (location != null) container.read(routerProvider).go(location);
  await settle(tester);
  return container;
}

/// Lets requests, debounces and animations finish. `pumpAndSettle` would never return while a
/// live stream's indicator pulses, so this pumps a fixed number of frames instead.
Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the app (closing live streams) and lets their reconnect timers run out.
Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 31));
}
