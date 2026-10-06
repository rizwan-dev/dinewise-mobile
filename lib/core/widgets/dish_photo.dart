import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/brand_colors.dart';

/// A dish photo, cached by URL (photos never change at a URL), with a warm placeholder while
/// it loads and when a dish has no photo.
class DishPhoto extends StatelessWidget {
  const DishPhoto({
    super.key,
    required this.url,
    this.veg,
    this.borderRadius = BorderRadius.zero,
    this.greyedOut = false,
    this.memCacheWidth,
  });

  final String? url;
  final bool? veg;
  final BorderRadius borderRadius;

  /// Sold out: shown in greyscale.
  final bool greyedOut;

  /// Decode at roughly the displayed size to keep memory low in long lists.
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    Widget child = url == null
        ? const _Placeholder()
        : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            memCacheWidth: memCacheWidth,
            fadeInDuration: const Duration(milliseconds: 220),
            placeholder: (_, _) => const _Placeholder(loading: true),
            errorWidget: (_, _, _) => const _Placeholder(),
          );
    if (greyedOut) {
      child = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 0.7, 0,
        ]),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: ExcludeSemantics(child: SizedBox.expand(child: child)),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? const [Brand.stone800, Brand.stone900] : const [Brand.saffron100, Brand.saffron50],
        ),
      ),
      child: Center(
        child: AnimatedOpacity(
          opacity: loading ? 0.35 : 0.6,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.ramen_dining_rounded, size: 36, color: dark ? Brand.stone600 : Brand.saffron400),
        ),
      ),
    );
  }
}
