import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/api_exception.dart';

/// One Server-Sent Events message: `event:` name (default `message`) and its `data:`.
class SseEvent {
  const SseEvent(this.event, this.data, {this.id});

  final String event;
  final String data;
  final String? id;

  /// [data] decoded as a JSON object, or null when it is not one.
  Json? get json {
    try {
      final value = jsonDecode(data);
      return value is Json ? value : null;
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SseEvent && other.event == event && other.data == data && other.id == id;

  @override
  int get hashCode => Object.hash(event, data, id);

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// A line-by-line `text/event-stream` parser, following the WHATWG rules the API relies on:
///
/// - `field: value` lines (one optional space after the colon is dropped),
/// - several `data:` lines join with `\n`,
/// - a blank line dispatches the message (nothing is dispatched without data),
/// - lines starting with `:` are comments (the server's keep-alive),
/// - `retry:` sets the reconnection delay in milliseconds.
class SseParser {
  String _event = '';
  final _data = StringBuffer();
  bool _hasData = false;
  String? _id;

  /// The latest `retry:` value, if the server sent one.
  Duration? retry;

  /// Feeds one line (without its line ending). Returns the message it completes, if any.
  SseEvent? addLine(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;

    final colon = line.indexOf(':');
    final String field;
    var value = '';
    if (colon == -1) {
      field = line;
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null && ms >= 0) retry = Duration(milliseconds: ms);
    }
    return null;
  }

  SseEvent? _dispatch() {
    if (!_hasData) {
      _event = '';
      return null;
    }
    final event = SseEvent(_event.isEmpty ? 'message' : _event, _data.toString(), id: _id);
    _event = '';
    _data.clear();
    _hasData = false;
    return event;
  }

  /// Parses a stream of bytes into messages. Line endings may be `\n`, `\r\n` or `\r`.
  Stream<SseEvent> bind(Stream<List<int>> bytes) => bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map(addLine)
      .where((e) => e != null)
      .cast<SseEvent>();
}

/// What a [LiveStream] reports: connection changes as well as the server's messages.
sealed class LiveUpdate {
  const LiveUpdate();
}

/// The stream is open (first time, or again after a drop). Changes made while it was down are
/// not replayed, so fetch the order or board again.
class LiveConnected extends LiveUpdate {
  const LiveConnected();
}

/// The stream dropped; it reconnects by itself after [retryIn].
class LiveDisconnected extends LiveUpdate {
  const LiveDisconnected(this.retryIn);
  final Duration retryIn;
}

/// A server message (`order`, `resync`…).
class LiveMessage extends LiveUpdate {
  const LiveMessage(this.event);
  final SseEvent event;
}

/// Follows one SSE endpoint for as long as it is listened to.
///
/// The server ends every stream after about 4½ minutes and networks drop, so the stream
/// reconnects on its own: after the server's `retry` (3 s), doubling on repeated failures up to
/// [maxBackoff], back to the base delay after a successful connect. `401` and `404` end it with
/// an [ApiException] error, since retrying cannot fix them. Cancelling the subscription closes
/// the connection.
class LiveStream {
  LiveStream(
    this.api,
    this.path,
    this.auth, {
    this.baseDelay = const Duration(seconds: 3),
    this.maxBackoff = const Duration(seconds: 30),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final ApiClient api;
  final String path;
  final AuthKind auth;
  final Duration baseDelay;
  final Duration maxBackoff;
  final Future<void> Function(Duration) _sleep;

  /// The delay before reconnect attempt number [failures] (1-based), given the base delay.
  static Duration backoff(Duration base, int failures, Duration max) {
    final factor = 1 << (failures - 1).clamp(0, 10);
    final ms = base.inMilliseconds * factor;
    return ms > max.inMilliseconds ? max : Duration(milliseconds: ms);
  }

  /// Starts following the endpoint when listened to. Built on a [StreamController] rather than
  /// `async*` so that cancelling closes the connection at once, even while waiting for data.
  Stream<LiveUpdate> updates() {
    var cancelled = false;
    http.Client? client;
    StreamSubscription<SseEvent>? subscription;
    Completer<void>? streamEnded;
    late final StreamController<LiveUpdate> controller;

    void emit(LiveUpdate update) {
      if (!cancelled) controller.add(update);
    }

    Future<void> run() async {
      var base = baseDelay;
      var failures = 0;
      while (!cancelled) {
        var connected = false;
        try {
          final (c, response) = await api.openStream(path, auth);
          client = c;
          if (cancelled) return;
          connected = true;
          failures = 0;
          emit(const LiveConnected());
          final parser = SseParser();
          final ended = streamEnded = Completer<void>();
          subscription = parser
              .bind(response.stream)
              .listen(
                (event) {
                  if (parser.retry != null) base = parser.retry!;
                  emit(LiveMessage(event));
                },
                onError: (Object _) => ended.isCompleted ? null : ended.complete(),
                onDone: () => ended.isCompleted ? null : ended.complete(),
                cancelOnError: true,
              );
          await ended.future;
        } on ApiException catch (e) {
          if (e.isUnauthenticated || e.isNotFound || e.status == 403) {
            if (!cancelled) {
              controller.addError(e);
              await controller.close();
            }
            return;
          }
        } catch (_) {
          // A dropped connection: reconnect below.
        } finally {
          // Already done (or cancelled) by now; cancelling only releases it.
          unawaited(subscription?.cancel());
          subscription = null;
          client?.close();
          client = null;
        }
        if (cancelled) return;
        if (!connected) failures++;
        final wait = failures == 0 ? base : backoff(base, failures, maxBackoff);
        emit(LiveDisconnected(wait));
        await _sleep(wait);
      }
    }

    controller = StreamController<LiveUpdate>(
      onListen: run,
      onCancel: () async {
        cancelled = true;
        final ended = streamEnded;
        if (ended != null && !ended.isCompleted) ended.complete();
        // Stop listening first, then drop the connection: closing the client while the response
        // is still being listened to would surface "Connection closed" as an uncaught error.
        final sub = subscription;
        final open = client;
        subscription = null;
        client = null;
        await sub?.cancel();
        open?.close();
      },
    );
    return controller.stream;
  }
}
