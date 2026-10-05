import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A soft shimmer over its [Bone] children while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.palette.skeleton;
    final highlight = Color.lerp(base, Theme.of(context).colorScheme.surface, 0.6)!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: reduceMotion
            ? widget.child
            : AnimatedBuilder(
                animation: _controller,
                child: widget.child,
                builder: (context, child) {
                  final t = _controller.value * 2 - 0.5;
                  return ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [base, highlight, base],
                      stops: [(t - 0.3).clamp(0, 1), t.clamp(0, 1), (t + 0.3).clamp(0, 1)],
                    ).createShader(rect),
                    child: child,
                  );
                },
              ),
      ),
    );
  }
}

/// A placeholder block inside a [Skeleton].
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.palette.skeleton,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// The shape of a dish row, for menu and home loading states.
class DishRowSkeleton extends StatelessWidget {
  const DishRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone(width: 60, height: 12),
              SizedBox(height: 10),
              Bone(width: 160, height: 18),
              SizedBox(height: 10),
              Bone(width: 70),
              SizedBox(height: 12),
              Bone(height: 12),
              SizedBox(height: 6),
              Bone(width: 180, height: 12),
            ],
          ),
        ),
        SizedBox(width: 16),
        Bone(width: 116, height: 116, radius: 18),
      ],
    ),
  );
}

/// A list of dish-row skeletons.
class MenuSkeleton extends StatelessWidget {
  const MenuSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(children: [for (var i = 0; i < rows; i++) const DishRowSkeleton()]),
  );
}
