import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/format/time.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/states.dart';
import '../../cart/data/cart.dart';
import '../../cart/ui/bill.dart';
import '../../restaurant/data/restaurant_repository.dart';
import '../data/order.dart';
import '../data/orders_repository.dart';
import 'status_chip.dart';

/// One order, following the kitchen live.
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(code));
    final live = ref.watch(orderLiveProvider(code));

    // Tell the customer when the kitchen moves their order on.
    ref.listen(orderProvider(code).select((o) => o.value?.status), (previous, next) {
      if (previous != null && next != null && previous != next) {
        HapticFeedback.mediumImpact();
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Order update: ${ref.read(orderProvider(code)).value?.statusLabel ?? ''}',
          Directionality.of(context),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.orders)),
        title: Text('Order $code'),
        actions: [
          if (order.value case final o? when !o.isFinal)
            Padding(padding: const EdgeInsets.only(right: 16), child: LiveIndicator(status: live)),
        ],
      ),
      body: switch (order) {
        AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => ref.read(orderProvider(code).notifier).refreshQuietly(),
          child: _OrderBody(order: value),
        ),
        AsyncValue(:final error?) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(orderProvider(code)),
        ),
        _ => const _OrderSkeleton(),
      },
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final restaurant = ref.watch(restaurantProvider).value;
    final now = ref.watch(clockProvider)();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _StatusHeader(order: order, now: now),
        if (order.steps.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: _Steps(steps: order.steps),
            ),
          ),
        ],
        if (order.cashDuePaise case final due?) ...[
          const SizedBox(height: 16),
          Notice(
            icon: Icons.payments_outlined,
            tone: NoticeTone.success,
            text: 'Please keep ${formatPaise(due)} ready in cash.',
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.fulfilment == Fulfilment.delivery ? 'Delivering to' : 'Pick up from', style: context.text.titleLarge),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      order.fulfilment == Fulfilment.delivery ? Icons.home_outlined : Icons.storefront_outlined,
                      size: 20,
                      color: palette.subtle,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        order.address?.oneLine ?? '${restaurant?.name ?? 'Tadka Lane'}, ${restaurant?.address ?? 'Baner, Pune'}',
                        style: context.text.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (order.notes case final notes?) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sticky_note_2_outlined, size: 20, color: palette.subtle),
                      const SizedBox(width: 10),
                      Expanded(child: Text('"$notes"', style: context.text.bodyMedium!.copyWith(fontStyle: FontStyle.italic))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your order', style: context.text.titleLarge),
                const SizedBox(height: 8),
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 32, child: Text('${item.quantity}×', style: context.text.titleSmall)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: context.text.bodyLarge),
                              if (item.optionsLabel.isNotEmpty) Text(item.optionsLabel, style: context.text.bodySmall),
                            ],
                          ),
                        ),
                        Text(formatPaise(item.lineTotalPaise), style: context.text.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        BillCard(totals: order.totals, couponCode: order.couponCode, title: 'Bill'),
        const SizedBox(height: 16),
        _History(order: order),
        if (order.canCancel) ...[
          const SizedBox(height: 24),
          _CancelButton(code: order.code),
        ],
      ],
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final problem = order.status.isProblem;
    final done = order.isFinal && !problem;
    final String subtitle;
    if (order.status == OrderStatus.rejected) {
      subtitle = 'The restaurant could not accept this order${order.rejectReason == null ? '.' : ': ${order.rejectReason}.'}';
    } else if (order.status == OrderStatus.cancelled) {
      subtitle = 'You cancelled this order. Nothing to pay.';
    } else if (done) {
      subtitle = 'Thank you for ordering from Tadka Lane. Enjoy your meal!';
    } else if (order.readyBy != null) {
      final when = formatDayAndTime(order.readyBy!, now: now).replaceFirst('Today, ', '');
      subtitle = order.fulfilment == Fulfilment.delivery
          ? 'Expected at your door around $when'
          : 'Ready for pickup around $when';
    } else {
      subtitle = '';
    }
    final (Color bg, Color fg) = problem
        ? (Brand.chilli, Colors.white)
        : done
        ? (Brand.leaf700, Colors.white)
        : (Brand.saffron700, Colors.white);

    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bg, Color.lerp(bg, Colors.black, 0.25)!],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      order.statusLabel,
                      key: ValueKey(order.status),
                      style: context.text.headlineMedium!.copyWith(color: fg),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(subtitle, style: context.text.bodyMedium!.copyWith(color: fg.withValues(alpha: 0.9))),
                  ],
                  if (order.scheduled && !order.isFinal) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Scheduled', style: context.text.labelMedium!.copyWith(color: fg)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(statusIcon(order.status), key: ValueKey(order.status), size: 52, color: fg.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<OrderStep> steps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        for (final (i, step) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: step.done
                            ? palette.action
                            : step.current
                            ? palette.accent
                            : palette.card,
                        border: Border.all(
                          color: step.done ? palette.action : (step.current ? palette.accent : palette.hairline),
                          width: 2,
                        ),
                      ),
                      child: step.done
                          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                          : step.current
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                            )
                          : null,
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          color: step.done ? palette.action : palette.hairline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 22),
                    child: Semantics(
                      label: '${step.label}, ${step.done ? 'done' : (step.current ? 'now' : 'to come')}',
                      excludeSemantics: true,
                      child: Text(
                        step.label,
                        style: context.text.titleMedium!.copyWith(
                          color: step.done || step.current ? null : palette.subtle,
                          fontWeight: step.current ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          title: Text('History', style: context.text.titleLarge),
          subtitle: Text('Placed ${formatShortDate(order.createdAt)}, ${formatTime(order.createdAt)}', style: context.text.bodySmall),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final entry in order.timeline.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(statusIcon(entry.status), size: 20),
                title: Text(entry.label),
                subtitle: entry.note == null ? null : Text(entry.note!),
                trailing: Text(formatTime(entry.at), style: context.text.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _CancelButton extends ConsumerStatefulWidget {
  const _CancelButton({required this.code});

  final String code;

  @override
  ConsumerState<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends ConsumerState<_CancelButton> {
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text('The kitchen has not started on it yet, so nothing is charged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref.read(orderProvider(widget.code).notifier).cancel();
      ref.invalidate(myOrdersProvider);
      if (mounted) showMessage(context, 'Order cancelled');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
      await ref.read(orderProvider(widget.code).notifier).refreshQuietly();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: context.palette.danger,
      side: BorderSide(color: context.palette.danger.withValues(alpha: 0.5)),
    ),
    onPressed: _busy ? null : _cancel,
    icon: _busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.close_rounded),
    label: const Text('Cancel order'),
  );
}

class _OrderSkeleton extends StatelessWidget {
  const _OrderSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Skeleton(
      child: Column(
        children: [
          Bone(height: 120, radius: 24),
          SizedBox(height: 16),
          Bone(height: 220, radius: 20),
          SizedBox(height: 16),
          Bone(height: 160, radius: 20),
        ],
      ),
    ),
  );
}
