part of 'one_to_many.dart';

/// Represents a callback for building a sequence flow whenever a root value is
/// associated with a list of streams.
///
/// [roots] contains all the current root events from a many-to-many relationship.
/// The generated flow should listen to [generatedStreams] and provide their
/// values to [childrenConsumer]. To access the root value associated with
/// [generatedStreams], you can access the [buildIndex] position at [roots].
typedef _ManyToManyFlowBuilder<T, R> = SequenceFlow<R> Function(
  List<T> roots,
  int buildIndex,
  List<Stream<R>> generatedStreams,
  ValueConsumer<List<AsyncSnapshot<R>>> childrenConsumer,
);

/// Handles the events from [ManyToManyFlow].
///
/// The caller that uses this callback should follow this workflow:
///
/// 1. The root stream starts to be listened.
/// 2. The root stream emits a list *L*, containing *N* root events.
/// 3. The caller triggers the [onRoots] function once, passing *L* as its
///    `roots` parameter.
/// 4. For each root event *E* in *L*, a list of nested streams *NSL* is
///    associated with *E*. Then, the caller triggers the [onRoot] function in
///    each iteration, passing *L* as its `roots` parameter, the index of `E` in
///    `L` as its `index` parameter (that goes from 0, inclusive, to *N*,
///    exclusive), and the length of *NSL* as its `length` parameter. The *NSL*
///    association process can be done with [ManyToManyFlow.mapping], for example.
/// 5. All the generated nested streams start to be listened.
/// 6. A nested stream *NS* emits a single event. *NS* is contained inside a
///    *NSL*, which is associated with a root event *E*.
/// 7. The caller triggers the [onChildren] function, passing *L* as its `roots`
///    parameter, the index of *E* in *L* as its `index` parameter and a list of
///    asynchronous snapshots *ASL* as its `children` parameter. In *ASL*, if a
///    snapshot at position *i* has the state "waiting", the nested stream
///    at position *i* in *NSL* have not emitted any events; if has the state
///    "data", the nested stream at position *i* in *NSL* has emitted the event
///    stored in [AsyncSnapshot.data].
/// 8. The workflow now enters a idle state. If the step 6 happens again, repeat
///    steps 6-7. If the step 2 happens again, repeat steps 3-7.
class _ManyToManyFlowCallback<T, R> {
  /// Called when a list of root events is emitted by the root stream.
  ///
  /// Its `roots` parameter provides the emitted list.
  final FutureOr<void> Function(List<T> roots) onRoots;

  /// Called when a nested stream's event is emitted.
  ///
  /// Its `roots` parameter provides the current list of root events and its
  /// `index` parameter provides the index of the emitted event's parent on
  /// `roots`. Its `children` parameter provides the emitted event.
  final FutureOr<void> Function(List<T> roots, int index, List<R> children)
      onChildren;

  const _ManyToManyFlowCallback({
    required this.onRoots,
    required this.onChildren,
  });
}

typedef ManyToManyValue<T, R> = List<OneToOneValue<T, R>>;

/// Combines multiple streams based on a many-to-many relationship between them.
///
/// The relationship is provided by [mapping]. When [stream] emits a list of M
/// events, call [mapping] on it, which will create a list of N sub-streams for
/// each event. When all sub-streams emit at least one value (generating M*N
/// values), supply a [ManyToManyValue] with M [OneToManyValue] values, with their
/// [OneToManyValue.parent] values as each event and their respective
/// [OneToManyValue.children] as their respective sub-streams, in the same order
/// as its originating streams.
///
/// --------------------------
///
/// If [stream] emits a new event while not all sub-streams from the previous
/// event have emitted at least one value, the values emitted from these
/// previous sub-streams will be dismissed.
class ManyToManyFlow<T, R> extends Flow {
  factory ManyToManyFlow.lazy(
    Stream<List<T>> stream, {
    required Stream<List<R>> Function(T) mapping,
    required ValueConsumer<ManyToManyValue<T, List<R>>> consumer,
  }) {
    return ManyToManyFlow.eager(
      stream,
      mapping: mapping,
      consumer: ValueConsumer.lambda((value) {
        if (value.any((nestedValue) => nestedValue.child
            .choose(onWaiting: () => true, onActive: (_) => false))) {
          return;
        }
        consumer.apply(value
            .map((nestedValue) => OneToOneValue(
                  root: nestedValue.root,
                  child: nestedValue.child.choose(
                    onWaiting: () => throw -1,
                    onActive: (data) => data,
                  ),
                ))
            .toList());
      }),
    );
  }

  /// Supplies values as soon as possible.
  ///
  /// If a value is not available yet, it'll be supplied as a [AsyncSnapshot.waiting].
  /// Otherwise, it'll be supplied as a [AsyncSnapshot.data] containing the
  /// emitted value.
  factory ManyToManyFlow.eager(
    Stream<List<T>> stream, {
    required Stream<List<R>> Function(T) mapping,
    required ValueConsumer<ManyToManyValue<T, AsyncSnapshot<List<R>>>> consumer,
  }) {
    ManyToManyValue<T, AsyncSnapshot<List<R>>>? _value;
    return ManyToManyFlow._(
      stream: stream,
      mapping: mapping,
      flowBuilder: (roots, i, streams, flowConsumer) {
        return SequenceFlow<R>.eager(
          streams,
          consumer: ValueConsumer.lambda((children) {
            flowConsumer.apply(children);
          }),
        );
      },
      callback: _ManyToManyFlowCallback(
        onRoots: (roots) {
          final ManyToManyValue<T, AsyncSnapshot<List<R>>> value = roots
              .map((root) => OneToOneValue<T, AsyncSnapshot<List<R>>>(
                  root: root, child: const AsyncSnapshot.waiting()))
              .toList();
          _value = value;
          consumer.apply(value);
        },
        onChildren: (roots, i, children) {
          final ManyToManyValue<T, AsyncSnapshot<List<R>>>? value = _value;
          if (value == null) return;
          value[i] = OneToOneValue<T, AsyncSnapshot<List<R>>>(
            root: roots[i],
            child: AsyncSnapshot.data(children),
          );
          consumer.apply(value);
        },
      ),
    );
  }

  final Stream<List<T>> stream;
  final Stream<List<R>> Function(T) mapping;

  final _ManyToManyFlowBuilder<T, R> flowBuilder;
  final _ManyToManyFlowCallback<T, R>? callback;

  const ManyToManyFlow._({
    required this.stream,
    required this.mapping,
    required this.flowBuilder,
    required this.callback,
  });

  @override
  FlowState start() => _ManyToManyState(
        stream: stream,
        mapping: mapping,
        callback: callback,
      );
}

class _ManyToManyState<T, R> extends FlowState {
  late final StreamSubscription<void> _subscription;
  List<StreamSubscription<void>>? _nestedSubscriptions;
  List<bool>? _flags;

  final DoneCompleter _completer = DoneCompleter();

  _ManyToManyState({
    required Stream<List<T>> stream,
    required Stream<List<R>> Function(T) mapping,
    _ManyToManyFlowCallback<T, R>? callback,
  }) {
    _subscription = stream.listen((events) async {
      // A new group of root events is being emitted
      callback?.onRoots(events);

      // Stop listening to the previous group
      await Future.wait(
        _nestedSubscriptions?.map((subscription) => subscription.cancel()) ??
            [],
      );

      // Start listening to the current group
      _flags = events.map((_) => false).toList();
      _nestedSubscriptions = List.generate(events.length, (i) {
        final T event = events[i];
        final Stream<List<R>> nestedStream = mapping(event);
        return nestedStream.listen(
          (snapshots) {
            callback?.onChildren(events, i, snapshots);
          },
          onDone: () {
            final List<bool> flags = _flags as List<bool>;
            flags[i] = true;
            if (flags.every((flag) => flag)) _completer.childDone();
          },
        );
      });
    }, onDone: () => _completer.rootDone());
  }

  @override
  Future<void> wait() => _completer.future;

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await Future.wait((_nestedSubscriptions ?? [])
        .map((subscription) => subscription.cancel()));
  }
}
