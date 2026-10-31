import 'dart:async';

/// A broadcast-style stream that replays its buffered history to late
/// listeners.
///
/// FFmpeg usually starts writing before Dart has finished attaching listeners
/// (a `-version` run prints and exits in a few milliseconds), and a plain
/// broadcast controller would silently drop those lines. This class keeps a
/// bounded history so the UI — or a test that subscribes late — still sees the
/// beginning of the log.
class ReplayStream<T> {
  ReplayStream({this.capacity = 2000}) : assert(capacity > 0);

  /// Maximum number of retained events.
  final int capacity;

  final List<T> _history = <T>[];
  final Set<StreamController<T>> _listeners = <StreamController<T>>{};
  bool _closed = false;

  bool get isClosed => _closed;

  /// Number of buffered events (history + not yet delivered).
  int get length => _history.length;

  Stream<T> get stream {
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        for (final event in List<T>.of(_history)) {
          controller.add(event);
        }
        if (_closed) {
          unawaited(controller.close());
        } else {
          _listeners.add(controller);
        }
      },
      onCancel: () {
        _listeners.remove(controller);
      },
    );
    return controller.stream;
  }

  void add(T event) {
    if (_closed) return;
    _history.add(event);
    if (_history.length > capacity) {
      _history.removeRange(0, _history.length - capacity);
    }
    for (final listener in List<StreamController<T>>.of(_listeners)) {
      listener.add(event);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final listeners = List<StreamController<T>>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      await listener.close();
    }
  }
}
