import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import 'app_router.dart';

/// Leaves a customer-only screen when the customer session ends while it is open (signed out
/// elsewhere, or a `401` from the server), for sign-in and then back to [location].
///
/// The router's redirect covers navigating *to* such a screen; screens that were pushed are not
/// re-checked by the router when a session changes, so they watch for it themselves.
class CustomerGuard extends ConsumerWidget {
  const CustomerGuard({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(customerSessionProvider.select((s) => s != null), (was, now) {
      if (was == true && !now && context.mounted) context.go(Routes.signInThen(location));
    });
    return child;
  }
}

/// The same for kitchen screens and the staff session: back to staff sign-in.
class StaffGuard extends ConsumerWidget {
  const StaffGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(staffSessionProvider.select((s) => s != null), (was, now) {
      if (was == true && !now && context.mounted) context.go(Routes.kitchenSignIn);
    });
    return child;
  }
}
