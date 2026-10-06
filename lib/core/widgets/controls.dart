import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../live/live_status.dart';
import '../theme/app_theme.dart';

/// − 2 + with 48dp targets.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.min = 0,
    this.max = 20,
    this.itemName,
    this.compact = false,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String? itemName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final what = itemName == null ? '' : ' $itemName';
    final size = compact ? 40.0 : 48.0;
    Widget button(IconData icon, String label, int? to) => Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(minimumSize: Size.square(size)),
          onPressed: to == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onChanged(to);
                },
          icon: Icon(icon, size: 20, color: to == null ? palette.subtle : palette.action),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            quantity - 1 <= 0 && min == 0 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            quantity - 1 <= 0 && min == 0 ? 'Remove$what' : 'One less$what',
            quantity > min ? quantity - 1 : null,
          ),
          Semantics(
            liveRegion: true,
            label: 'Quantity $quantity',
            excludeSemantics: true,
            child: SizedBox(
              width: 28,
              child: Text('$quantity', textAlign: TextAlign.center, style: context.text.titleMedium),
            ),
          ),
          button(Icons.add_rounded, 'One more$what', quantity < max ? quantity + 1 : null),
        ],
      ),
    );
  }
}

/// A heading for a page section, with an optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing, this.padding});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(16, 28, 8, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: context.text.headlineSmall)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: context.text.bodyMedium!.copyWith(color: context.palette.muted)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A pulsing dot and "Live" / "Reconnecting…".
class LiveIndicator extends StatefulWidget {
  const LiveIndicator({super.key, required this.status, this.onDark = false});

  final LiveStatus status;
  final bool onDark;

  @override
  State<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<LiveIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (label, color) = switch (widget.status) {
      LiveStatus.live => ('Live', palette.success),
      LiveStatus.connecting => ('Connecting…', palette.subtle),
      LiveStatus.reconnecting => ('Reconnecting…', palette.accent),
      LiveStatus.off => ('Paused', palette.subtle),
    };
    return Semantics(
      label: 'Updates: $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: widget.status == LiveStatus.live
                ? Tween(begin: 0.35, end: 1.0).animate(_pulse)
                : const AlwaysStoppedAnimation(1),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.text.labelMedium!.copyWith(
              color: widget.onDark ? Colors.white : palette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width primary button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: busy
            ? const SizedBox(
                key: ValueKey('busy'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisAlignment: trailing == null
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  if (trailing != null) Text(trailing!),
                ],
              ),
      ),
    ),
  );
}
