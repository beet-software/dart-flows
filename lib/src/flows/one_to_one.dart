import 'dart:async';

import '../models/async_snapshot.dart';
import '../models/done_completer.dart';
import '../models/value_consumer.dart';
import 'flow.dart';

/// Stores a value [root] with its dependent [child].
class OneToOneValue<T, R> {
  final T root;
  final R child;

  const OneToOneValue({
    required this.root,
    required this.child,
  });

  @override
  String toString() => "OneToOneValue([$root]{$child})";
}

class _OneToOneCombinerCallback<T, R> {
  final FutureOr<void> Function(T root) onRootEvent;
  final FutureOr<void> Function(T root, R child) onChildEvent;

  const _OneToOneCombinerCallback({
    required this.onRootEvent,
    required this.onChildEvent,
  });
}

/// Combines two streams based on a one-to-one relationship between them.
///
/// The relationship is provided by [mapping]. For every value `v` emitted by
/// [stream], call [mapping] on it, which will create a nested stream. For each
/// value `nv` in this nested stream, supply a [OneToOneValue], with
/// `v` as [OneToOneValue.root] and `nv` as [OneToOneValue.child].
///
/// This is equivalent to [Stream.asyncExpand]. However, the latter evaluates
/// the stream lazily (e.g. only when it reaches a terminal operation, such as
/// [Stream.toList] or [Stream.last]), while the former evaluates the stream as
/// soon as possible.
class OneToOneFlow<T, R> extends Flow {
  /// Supplies values only when both root and child are available.
  factory OneToOneFlow.lazy(
    Stream<T> stream, {
    required Stream<R> Function(T) mapping,
    required ValueConsumer<OneToOneValue<T, R>> consumer,
  }) {
    return OneToOneFlow._(
      stream: stream,
      mapping: mapping,
      callback: _OneToOneCombinerCallback(
        onRootEvent: (root) {},
        onChildEvent: (root, child) =>
            consumer.apply(OneToOneValue(root: root, child: child)),
      ),
    );
  }

  /// Supplies values as soon as possible.
  ///
  /// If a value is not available yet, it'll be supplied as a [AsyncSnapshot.waiting].
  ///
  /// When a root event is emitted, a [OneToOneValue] is supplied with its child
  /// being a [AsyncSnapshot.waiting]. When a child event is emitted, a
  /// [OneToOneValue] is supplied with its child being [AsyncSnapshot.data]
  /// containing the emitted event.
  factory OneToOneFlow.eager(
    Stream<T> stream, {
    required Stream<R> Function(T) mapping,
    required ValueConsumer<OneToOneValue<T, AsyncSnapshot<R>>> consumer,
  }) {
    return OneToOneFlow._(
      stream: stream,
      mapping: mapping,
      callback: _OneToOneCombinerCallback(
        onRootEvent: (root) => consumer.apply(
            OneToOneValue(root: root, child: const AsyncSnapshot.waiting())),
        onChildEvent: (root, child) => consumer
            .apply(OneToOneValue(root: root, child: AsyncSnapshot.data(child))),
      ),
    );
  }

  final Stream<T> stream;
  final Stream<R> Function(T) mapping;
  final _OneToOneCombinerCallback<T, R>? callback;

  /// Creates an [OneToOneFlow].
  ///
  /// [stream] must supply the root events.
  ///
  /// [mapping] is a function applied for each root event, creating the
  /// sub-stream associated to it.
  const OneToOneFlow._({
    required this.stream,
    required this.mapping,
    this.callback,
  });

  @override
  FlowState start() =>
      _State<T, R>(stream: stream, mapping: mapping, callback: callback);
}

class _State<T, R> implements FlowState {
  late final StreamSubscription<void> _subscription;
  StreamSubscription<void>? _nestedSubscription;

  final DoneCompleter _done = DoneCompleter();

  _State({
    required Stream<T> stream,
    required Stream<R> Function(T) mapping,
    _OneToOneCombinerCallback<T, R>? callback,
  }) {
    _subscription = stream.listen(
      (event) async {
        await callback?.onRootEvent(event);
        final Stream<R> nestedStream = mapping(event);
        await _nestedSubscription?.cancel();
        _nestedSubscription = nestedStream.listen(
          (nestedEvent) async {
            await callback?.onChildEvent(event, nestedEvent);
          },
          onDone: () => _done.childDone(),
        );
      },
      onDone: () => _done.rootDone(),
    );
  }

  @override
  Future<void> wait() => _done.future;

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _nestedSubscription?.cancel();
  }
}
