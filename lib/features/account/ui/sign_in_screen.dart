import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/states.dart';
import '../../restaurant/data/restaurant_repository.dart';
import '../data/account_repository.dart';

enum _Step { phone, code, name }

/// Sign in with a phone number and a one-time code, then (first time) a name.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.from});

  /// Where to go once signed in (e.g. `/checkout`).
  final String? from;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _codeFocus = FocusNode();

  _Step _step = _Step.phone;
  OtpSent? _sent;
  bool _busy = false;
  String? _phoneError;
  String? _codeError;
  String? _nameError;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _phoneError = null;
      _codeError = null;
    });
    try {
      final sent = await ref.read(customerAuthProvider).sendCode(_phone.text);
      if (!mounted) return;
      setState(() {
        _sent = sent;
        _step = _Step.code;
        _code.clear();
      });
      _startResendTimer();
      _codeFocus.requestFocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_step == _Step.code) {
        setState(() => _codeError = e.message);
      } else {
        setState(() => _phoneError = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final sent = _sent;
    if (sent == null) return;
    setState(() {
      _busy = true;
      _codeError = null;
    });
    try {
      final needsName = await ref.read(customerAuthProvider).verify(phone: sent.phone, code: _code.text);
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      if (needsName) {
        setState(() => _step = _Step.name);
      } else {
        _done();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The API has no "update my name" call: the name is kept with the session and sent with the
  /// first order, which saves it on the server.
  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 60) {
      setState(() => _nameError = 'Please enter your name (2 to 60 letters).');
      return;
    }
    final session = ref.read(customerSessionProvider);
    if (session != null) {
      await ref
          .read(customerSessionProvider.notifier)
          .save(session.withCustomer(session.customer.copyWith(name: name)));
    }
    _done();
  }

  void _done() {
    final from = widget.from;
    if (from != null) {
      context.pushReplacement(from);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(isDemoProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: switch (_step) {
                    _Step.phone => _phoneStep(context),
                    _Step.code => _codeStep(context, demo),
                    _Step.name => _nameStep(context),
                  },
                ),
                if (_step == _Step.phone) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.push(Routes.kitchenSignIn),
                      icon: const Icon(Icons.soup_kitchen_outlined),
                      label: const Text('Restaurant staff? Open kitchen mode'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(header: true, child: Text(title, style: context.text.displaySmall)),
      const SizedBox(height: 8),
      Text(subtitle, style: context.text.bodyLarge!.copyWith(color: context.palette.muted)),
      const SizedBox(height: 28),
    ],
  );

  Widget _phoneStep(BuildContext context) => Column(
    key: const ValueKey('phone'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(context, 'Sign in', 'We will text a six-digit code to your mobile number.'),
      TextField(
        controller: _phone,
        autofocus: true,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
          LengthLimitingTextInputFormatter(16),
        ],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _sendCode(),
        decoration: InputDecoration(
          labelText: 'Mobile number',
          prefixIcon: const Icon(Icons.phone_iphone_rounded),
          prefixText: '+91 ',
          hintText: '98220 22314',
          errorText: _phoneError,
        ),
      ),
      const SizedBox(height: 20),
      BusyButton(label: 'Send code', busy: _busy, onPressed: _sendCode),
    ],
  );

  Widget _codeStep(BuildContext context, bool demo) {
    final sent = _sent!;
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          context,
          'Enter the code',
          'Sent to ${sent.phone}. It works for ${sent.expiresInSeconds ~/ 60} minutes.',
        ),
        if (demo && sent.demoCode != null) ...[
          Notice(
            icon: Icons.sms_outlined,
            text: 'Demo: no SMS is sent. Your code is ${sent.demoCode}.',
            action: TextButton(
              onPressed: () {
                _code.text = sent.demoCode!;
                _verify();
              },
              child: const Text('Fill it in'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _code,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: context.text.headlineMedium!.copyWith(letterSpacing: 12, fontFamily: 'Inter'),
          onChanged: (v) {
            if (v.length == 6) _verify();
          },
          decoration: InputDecoration(labelText: 'Six-digit code', errorText: _codeError, counterText: ''),
        ),
        const SizedBox(height: 20),
        BusyButton(label: 'Verify and sign in', busy: _busy, onPressed: _verify),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy ? null : () => setState(() => _step = _Step.phone),
              child: const Text('Change number'),
            ),
            TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _sendCode,
              child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nameStep(BuildContext context) => Column(
    key: const ValueKey('name'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(context, 'Welcome!', 'What should we call you? The kitchen and the rider will see this name.'),
      TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _saveName(),
        decoration: InputDecoration(
          labelText: 'Your name',
          prefixIcon: const Icon(Icons.person_outline_rounded),
          errorText: _nameError,
        ),
      ),
      const SizedBox(height: 20),
      BusyButton(label: 'Continue', onPressed: _saveName),
    ],
  );
}
