import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../providers.dart';
import 'sse.dart';

/// How a live stream is doing, for the small "Live" indicator.
enum LiveStatus { off, connecting, live, reconnecting }

/// Follows [path] while the app is in the foreground and calls [onChange] whenever the data
/// may have changed: on every (re)connect, `order` and `resync` message. Returns the status.
///
/// Call from a provider's `build`; the stream closes when the provider is disposed or rebuilt
/// (for example when the app goes to the background), and coming back reconnects, which
/// fetches again.
LiveStatus followLive(
  Ref ref,
  void Function(LiveStatus status) setStatus, {
  required String path,
  required AuthKind auth,
  required void Function(LiveMessage? message) onChange,
  void Function(Object error)? onFatal,
}) {
  if (!ref.watch(appForegroundProvider)) return LiveStatus.off;
  final stream = LiveStream(ref.read(apiClientProvider), path, auth).updates();
  late final StreamSubscription<LiveUpdate> sub;
  sub = stream.listen(
    (update) {
      switch (update) {
        case LiveConnected():
          setStatus(LiveStatus.live);
          onChange(null);
        case LiveDisconnected():
          setStatus(LiveStatus.reconnecting);
        case LiveMessage(:final event):
          if (event.event == 'order' || event.event == 'resync') onChange(update);
      }
    },
    onError: (Object error) {
      setStatus(LiveStatus.off);
      onFatal?.call(error);
    },
    cancelOnError: true,
  );
  ref.onDispose(sub.cancel);
  return LiveStatus.connecting;
}
