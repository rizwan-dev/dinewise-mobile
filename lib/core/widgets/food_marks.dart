import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brand_colors.dart';

/// The Indian veg / non-veg mark: a square with a green dot or a red triangle.
class VegMark extends StatelessWidget {
  const VegMark({super.key, required this.veg, this.size = 16});

  final bool veg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = veg ? Brand.vegGreen : Brand.nonVegRed;
    return Semantics(
      label: veg ? 'Vegetarian' : 'Non-vegetarian',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color, width: size / 10 + 0.4),
          borderRadius: BorderRadius.circular(size / 8),
        ),
        alignment: Alignment.center,
        child: veg
            ? Container(
                width: size * 0.48,
                height: size * 0.48,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              )
            : CustomPaint(size: Size.square(size * 0.52), painter: _TrianglePainter(color)),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// 0–3 chillies. Nothing for 0.
class SpiceMeter extends StatelessWidget {
  const SpiceMeter({super.key, required this.spice, this.size = 14});

  final int spice;
  final double size;

  static const _labels = ['Not spicy', 'Mildly spicy', 'Medium spicy', 'Very spicy'];

  @override
  Widget build(BuildContext context) {
    if (spice <= 0) return const SizedBox.shrink();
    final level = spice.clamp(1, 3);
    return Semantics(
      label: _labels[level],
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < level; i++)
            Icon(Icons.local_fire_department_rounded, size: size, color: Brand.chilli),
        ],
      ),
    );
  }
}

/// The small "Bestseller" ribbon.
class BestsellerBadge extends StatelessWidget {
  const BestsellerBadge({super.key, this.onPhoto = false});

  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onPhoto ? Brand.saffron500 : palette.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 13, color: onPhoto ? Colors.white : palette.accentOnSoft),
          const SizedBox(width: 3),
          Text(
            'Bestseller',
            style: context.text.labelSmall!.copyWith(
              color: onPhoto ? Colors.white : palette.accentOnSoft,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
