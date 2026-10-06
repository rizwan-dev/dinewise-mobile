import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/states.dart';
import '../../restaurant/data/restaurant_repository.dart';
import '../data/kitchen_repository.dart';

/// Staff sign-in: email and password, or (on the demo) one tap as the kitchen or the manager.
class StaffSignInScreen extends ConsumerStatefulWidget {
  const StaffSignInScreen({super.key});

  @override
  ConsumerState<StaffSignInScreen> createState() => _StaffSignInScreenState();
}

class _StaffSignInScreenState extends ConsumerState<StaffSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      // Replace this screen with the board (the router only redirects screens it navigated to).
      if (context.canPop()) {
        context.pushReplacement(Routes.kitchen);
      } else {
        context.go(Routes.kitchen);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(isDemoProvider);
    final auth = ref.read(staffAuthProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: Brand.stone900, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.soup_kitchen_rounded, color: Brand.saffron200, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Semantics(header: true, child: Text('Kitchen mode', style: context.text.displaySmall)),
                  const SizedBox(height: 8),
                  Text(
                    'For Tadka Lane staff: take new orders, cook them and send them out.',
                    style: context.text.bodyLarge!.copyWith(color: context.palette.muted),
                  ),
                  const SizedBox(height: 28),
                  if (demo) ...[
                    const Notice(
                      icon: Icons.science_outlined,
                      text: 'This is the demo. Step into the kitchen with one tap.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _run(() => auth.demoSignIn(StaffRole.kitchen)),
                            icon: const Icon(Icons.restaurant_rounded),
                            label: const Text('Try as kitchen'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _run(() => auth.demoSignIn(StaffRole.manager)),
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text('Try as manager'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or sign in', style: context.text.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _run(() => auth.signIn(_email.text, _password.text)),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      errorText: _error,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  BusyButton(
                    label: 'Sign in',
                    busy: _busy,
                    onPressed: () => _run(() => auth.signIn(_email.text, _password.text)),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go(Routes.home),
                      child: const Text('Back to ordering'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
