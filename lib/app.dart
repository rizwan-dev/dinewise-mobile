import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/orders/data/orders_repository.dart';

class DinewiseApp extends ConsumerStatefulWidget {
  const DinewiseApp({super.key});

  @override
  ConsumerState<DinewiseApp> createState() => _DinewiseAppState();
}

class _DinewiseAppState extends ConsumerState<DinewiseApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => ref.read(appForegroundProvider.notifier).update(state),
      // Orders move on while the app is in the background.
      onResume: () => ref.invalidate(myOrdersProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Dinewise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        // Respect the user's text size, but cap it where layouts would break.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.6)),
          child: child!,
        );
      },
    );
  }
}
