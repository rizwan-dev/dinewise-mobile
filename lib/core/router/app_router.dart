import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/ui/account_screen.dart';
import '../../features/account/ui/sign_in_screen.dart';
import '../../features/cart/ui/cart_screen.dart';
import '../../features/checkout/ui/checkout_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/kitchen/ui/availability_screen.dart';
import '../../features/kitchen/ui/kitchen_board_screen.dart';
import '../../features/kitchen/ui/staff_sign_in_screen.dart';
import '../../features/menu/ui/menu_screen.dart';
import '../../features/orders/ui/order_screen.dart';
import '../../features/orders/ui/orders_screen.dart';
import '../auth/auth_providers.dart';
import 'customer_shell.dart';
import 'session_guard.dart';

abstract final class Routes {
  static const home = '/';
  static const menu = '/menu';
  static const orders = '/orders';
  static const account = '/account';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static const signIn = '/sign-in';
  static const kitchen = '/kitchen';
  static const kitchenSignIn = '/kitchen/sign-in';
  static const kitchenMenu = '/kitchen/menu';

  static String order(String code) => '/orders/$code';
  static String signInThen(String from) => Uri(path: signIn, queryParameters: {'from': from}).toString();
  static String menuAt(String section) => Uri(path: menu, queryParameters: {'section': section}).toString();
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects when either session changes (sign-in, sign-out, a 401).
  final refresh = ValueNotifier(0);
  ref.listen(customerSessionProvider, (_, _) => refresh.value++);
  ref.listen(staffSessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final customer = ref.read(customerSessionProvider);
      final staff = ref.read(staffSessionProvider);

      if (path.startsWith(Routes.kitchen)) {
        final onSignIn = path == Routes.kitchenSignIn;
        if (staff == null && !onSignIn) return Routes.kitchenSignIn;
        if (staff != null && onSignIn) return Routes.kitchen;
        return null;
      }
      final needsCustomer = path == Routes.checkout || path.startsWith('${Routes.orders}/');
      if (needsCustomer && customer == null) return Routes.signInThen(state.uri.toString());
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.menu,
                builder: (_, state) => MenuScreen(initialSection: state.uri.queryParameters['section']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.orders,
                builder: (_, _) => const OrdersScreen(),
                routes: [
                  GoRoute(
                    path: ':code',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, state) => CustomerGuard(
                      location: state.uri.toString(),
                      child: OrderScreen(code: state.pathParameters['code']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.account, builder: (_, _) => const AccountScreen())],
          ),
        ],
      ),
      GoRoute(path: Routes.cart, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const CartScreen()),
      GoRoute(
        path: Routes.checkout,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => CustomerGuard(location: state.uri.toString(), child: const CheckoutScreen()),
      ),
      GoRoute(
        path: Routes.signIn,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: SignInScreen(from: state.uri.queryParameters['from']),
        ),
      ),
      GoRoute(
        path: Routes.kitchenSignIn,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const StaffSignInScreen(),
      ),
      GoRoute(
        path: Routes.kitchen,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const StaffGuard(child: KitchenBoardScreen()),
      ),
      GoRoute(
        path: Routes.kitchenMenu,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const StaffGuard(child: AvailabilityScreen()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
