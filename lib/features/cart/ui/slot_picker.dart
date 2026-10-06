import 'package:flutter/material.dart';

import '../../../core/format/time.dart';
import '../../../core/theme/app_theme.dart';
import '../../restaurant/data/restaurant.dart';
import '../data/cart.dart';

/// "As soon as possible (by 1:15 pm)" or "Tomorrow, 12:30 pm".
String describeSlot(String slot, SlotOptions options, {required DateTime now}) {
  if (slot == Cart.asap) {
    return options.asap == null
        ? 'As soon as possible'
        : 'As soon as possible · by ${formatTime(options.asap!)}';
  }
  return formatDayAndTime(parseInstant(slot), now: now);
}

/// Picks ASAP or a 15-minute slot, grouped by day. Full slots are shown disabled.
Future<String?> showSlotPicker(
  BuildContext context, {
  required SlotOptions options,
  required String current,
  required DateTime now,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  useSafeArea: true,
  builder: (_) => _SlotPicker(options: options, current: current, now: now),
);

class _SlotPicker extends StatefulWidget {
  const _SlotPicker({required this.options, required this.current, required this.now});

  final SlotOptions options;
  final String current;
  final DateTime now;

  @override
  State<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<_SlotPicker> {
  late final Map<String, List<Slot>> _days = widget.options.byDate;
  late String? _day = _initialDay();

  String? _initialDay() {
    if (widget.current != Cart.asap) {
      for (final entry in _days.entries) {
        if (entry.value.any((s) => s.value == widget.current)) return entry.key;
      }
    }
    return _days.keys.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final slots = _day == null ? const <Slot>[] : _days[_day]!;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('When should it be ready?', style: context.text.headlineSmall),
            const SizedBox(height: 16),
            _AsapTile(
              options: widget.options,
              selected: widget.current == Cart.asap,
              onTap: widget.options.asap == null ? null : () => Navigator.pop(context, Cart.asap),
            ),
            const SizedBox(height: 20),
            Text('Or schedule it', style: context.text.titleMedium),
            const SizedBox(height: 10),
            if (_days.isEmpty)
              Text('No times are open for scheduling right now.', style: TextStyle(color: palette.muted))
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final day in _days.keys)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(formatDayLabel(day, now: widget.now)),
                          selected: _day == day,
                          onSelected: (_) => setState(() => _day = day),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slot in slots)
                        ChoiceChip(
                          label: Text(formatTime(slot.startsAt)),
                          selected: widget.current == slot.value,
                          tooltip: slot.full ? 'Full' : null,
                          onSelected: slot.full ? null : (_) => Navigator.pop(context, slot.value),
                          labelStyle: slot.full
                              ? TextStyle(color: palette.subtle, decoration: TextDecoration.lineThrough)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AsapTile extends StatelessWidget {
  const _AsapTile({required this.options, required this.selected, required this.onTap});

  final SlotOptions options;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? palette.successSoft : palette.card,
            border: Border.all(color: selected ? palette.action : palette.hairline, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, color: onTap == null ? palette.subtle : palette.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('As soon as possible', style: context.text.titleMedium),
                    Text(
                      options.asap == null
                          ? 'The kitchen is full right now. Pick a time below.'
                          : 'Ready by ${formatTime(options.asap!)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: palette.action),
            ],
          ),
        ),
      ),
    );
  }
}
