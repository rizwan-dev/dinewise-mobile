import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../restaurant/data/restaurant_repository.dart';
import '../data/account_repository.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(customerSessionProvider);
    final restaurant = ref.watch(restaurantProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text('Account', style: context.text.headlineMedium)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (session == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: context.palette.accentSoft, shape: BoxShape.circle),
                      child: Icon(Icons.person_outline_rounded, color: context.palette.accent, size: 28),
                    ),
                    const SizedBox(height: 14),
                    Text('Sign in to order', style: context.text.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Follow your order live, see past orders and keep your addresses for next time.',
                      style: context.text.bodyMedium!.copyWith(color: context.palette.muted),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => context.push(Routes.signIn),
                      child: const Text('Sign in with your phone'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _ProfileCard(name: session.customer.name, phone: session.customer.displayPhone),
            const SizedBox(height: 16),
            const _Addresses(),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('My orders'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.orders),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(Icons.logout_rounded, color: context.palette.danger),
                    title: Text('Sign out', style: TextStyle(color: context.palette.danger)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Sign out?'),
                          content: const Text('Your cart stays on this phone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
                          ],
                        ),
                      );
                      if (ok ?? false) {
                        await ref.read(customerAuthProvider).signOut();
                        if (context.mounted) showMessage(context, 'Signed out');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.soup_kitchen_outlined),
              title: const Text('Restaurant staff?'),
              subtitle: const Text('Open kitchen mode to run the kitchen board.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.kitchen),
            ),
          ),
          if (restaurant != null) ...[
            const SizedBox(height: 28),
            Center(
              child: Column(
                children: [
                  Text(restaurant.name, style: context.text.titleLarge!.copyWith(color: context.palette.accent)),
                  const SizedBox(height: 4),
                  Text(restaurant.address, textAlign: TextAlign.center, style: context.text.bodySmall),
                  Text(restaurant.phone, style: context.text.bodySmall),
                  if (restaurant.demo) ...[
                    const SizedBox(height: 10),
                    Text(
                      'A demo restaurant. Orders are not cooked, and the demo resets from time to time.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.name, required this.phone});

  final String? name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final initial = (name?.trim().isNotEmpty ?? false) ? name!.trim()[0].toUpperCase() : '?';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Brand.saffron700,
              child: Text(initial, style: context.text.headlineSmall!.copyWith(color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name ?? 'Welcome', style: context.text.headlineSmall),
                  const SizedBox(height: 2),
                  Text(phone, style: context.text.bodyMedium!.copyWith(color: context.palette.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Addresses extends ConsumerWidget {
  const _Addresses();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved addresses', style: context.text.titleLarge),
            const SizedBox(height: 8),
            switch (me) {
              AsyncValue(:final value?) when value.addresses.isEmpty => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'None yet. Tick "Save this address" at checkout to keep one here.',
                  style: context.text.bodyMedium!.copyWith(color: context.palette.muted),
                ),
              ),
              AsyncValue(:final value?) => Column(
                children: [
                  for (final a in value.addresses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.home_outlined),
                      title: Text(a.label),
                      subtitle: Text(a.oneLine),
                    ),
                ],
              ),
              AsyncValue(:final error?) => ErrorView(error: error, compact: true, onRetry: () => ref.invalidate(meProvider)),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Skeleton(
                  child: Column(children: [Bone(), SizedBox(height: 10), Bone(width: 180)]),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}
