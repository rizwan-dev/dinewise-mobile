import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme/app_theme.dart';

/// The text to show for any error: the server's message when there is one.
String errorText(Object? error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Shows a short message at the bottom of the screen.
void showMessage(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: error ? 4 : 2),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Theme.of(context).colorScheme.onInverseSurface,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

/// Runs a pull-to-refresh and says so when it fails; the screen keeps what it had.
Future<void> refreshOrSay(BuildContext context, Future<Object?> Function() refresh) async {
  try {
    await refresh();
  } on Object catch (e) {
    if (context.mounted) showMessage(context, errorText(e), error: true);
  }
}

/// A friendly full-area message with an optional action: empty lists, errors, signed out.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 16 : 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 64 : 88,
                height: compact ? 64 : 88,
                decoration: BoxDecoration(color: palette.accentSoft, shape: BoxShape.circle),
                child: Icon(icon, size: compact ? 30 : 40, color: palette.accent),
              ),
              const SizedBox(height: 20),
              Text(title, style: context.text.headlineSmall, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: context.text.bodyMedium!.copyWith(color: palette.muted),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// An error with a Retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry, this.compact = false});

  final Object? error;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error! as ApiException).isNetwork;
    return MessageView(
      icon: offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
      title: offline ? 'You seem to be offline' : 'That did not load',
      message: errorText(error),
      compact: compact,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}

/// A rounded tinted box for an inline notice (a quote problem, a demo hint).
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone = NoticeTone.info,
    this.action,
  });

  final String text;
  final IconData icon;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (bg, fg) = switch (tone) {
      NoticeTone.info => (palette.accentSoft, palette.accentOnSoft),
      NoticeTone.success => (palette.successSoft, palette.success),
      NoticeTone.danger => (palette.dangerSoft, palette.danger),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: context.text.bodyMedium!.copyWith(color: fg, fontWeight: FontWeight.w500),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
      ),
    );
  }
}

enum NoticeTone { info, success, danger }
