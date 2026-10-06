import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/format/time.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../cart/data/cart.dart';
import '../data/board.dart';
import '../data/kitchen_repository.dart';

/// A kitchen ticket: what to cook, when it is due, the cash to collect, and the one big button.
class TicketCard extends ConsumerStatefulWidget {
  const TicketCard({super.key, required this.ticket, required this.now, required this.rejectReasons});

  final Ticket ticket;
  final DateTime now;
  final List<String> rejectReasons;

  @override
  ConsumerState<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends ConsumerState<TicketCard> {
  bool _busy = false;

  Future<void> _move(String to, {String? reason}) async {
    setState(() => _busy = true);
    unawaited(HapticFeedback.mediumImpact());
    try {
      await ref.read(boardProvider.notifier).move(widget.ticket.code, to, reason: reason);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (_) => _RejectSheet(code: widget.ticket.code, reasons: widget.rejectReasons),
    );
    if (reason != null) await _move('REJECTED', reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final palette = context.palette;
    final late = t.isLate(widget.now);
    final delivery = t.fulfilment == Fulfilment.delivery;

    return Semantics(
      container: true,
      label: 'Order ${t.code}${late ? ', late' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: late ? palette.danger : palette.hairline, width: late ? 2 : 1),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.code, style: context.text.titleLarge),
                      const SizedBox(width: 8),
                      Icon(
                        delivery ? Icons.delivery_dining_outlined : Icons.storefront_outlined,
                        size: 20,
                        color: palette.subtle,
                        semanticLabel: delivery ? 'Delivery' : 'Pickup',
                      ),
                    ],
                  ),
                  _DueBadge(due: t.dueAt, now: widget.now, late: late, later: t.later),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  t.customerName ?? 'Guest',
                  delivery ? 'Delivery${t.pincode == null ? '' : ' · ${t.pincode}'}' : 'Pickup',
                  'placed ${formatTime(t.placedAt)}',
                ].join(' · '),
                style: context.text.bodySmall,
              ),
              const Divider(height: 22),
              for (final item in t.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${item.quantity}×',
                          style: context.text.titleMedium!.copyWith(color: palette.accent),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: context.text.titleMedium),
                            if (item.details.isNotEmpty) Text(item.details, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (t.notes case final notes?) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sticky_note_2_outlined, size: 18, color: palette.accentOnSoft),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          notes,
                          style: context.text.bodyMedium!.copyWith(
                            color: palette.accentOnSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    t.cashToCollectPaise == null ? Icons.verified_outlined : Icons.payments_outlined,
                    size: 18,
                    color: palette.success,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t.cashToCollectPaise == null
                          ? 'Paid online'
                          : 'Collect ${formatPaise(t.cashToCollectPaise!)} cash',
                      style: context.text.labelLarge!.copyWith(color: palette.success),
                    ),
                  ),
                ],
              ),
              if (t.kitchenNext != null || t.canReject) const SizedBox(height: 12),
              if (t.kitchenNext != null)
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _busy ? null : () => _move(t.kitchenNext!),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(t.kitchenNextLabel ?? 'Next', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              if (t.canReject)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: palette.danger),
                  onPressed: _busy ? null : _reject,
                  child: const Text('Reject'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueBadge extends StatelessWidget {
  const _DueBadge({required this.due, required this.now, required this.late, required this.later});

  final DateTime due;
  final DateTime now;
  final bool late;
  final bool later;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = later
        ? formatDayAndTime(due, now: now)
        : 'Due ${formatTime(due)} · ${formatDueIn(due, now: now)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: late ? palette.danger : palette.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: context.text.labelMedium!.copyWith(
          color: late ? Colors.white : palette.accentOnSoft,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.code, required this.reasons});

  final String code;
  final List<String> reasons;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Reject ${widget.code}?', style: context.text.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'The customer sees the reason.',
          style: context.text.bodyMedium!.copyWith(color: context.palette.muted),
        ),
        const SizedBox(height: 16),
        for (final r in widget.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(onPressed: () => Navigator.pop(context, r), child: Text(r)),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _other,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Another reason'),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder(
          valueListenable: _other,
          builder: (context, value, _) => FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
            onPressed: value.text.trim().isEmpty ? null : () => Navigator.pop(context, value.text.trim()),
            child: const Text('Reject with this reason'),
          ),
        ),
      ],
    ),
  );
}
