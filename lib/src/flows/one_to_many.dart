import 'dart:async';

import '../models/async_snapshot.dart';
import '../models/done_completer.dart';
import '../models/value_consumer.dart';
import 'flow.dart';
import 'one_to_one.dart';
import 'sequence.dart';

part 'many_to_many.dart';

/// Stores a [parent] with its [children].
typedef SyncOneToManyValue<T, R> = OneToOneValue<T, List<R>>;

typedef AsyncOneToManyValue<T, R> = OneToOneValue<T, AsyncSnapshot<List<R>>>;

/// A callback used to manage the events supplied by [OneToManyFlow].
class _OneToManyFlowCallback<T, R> {
  /// Called when a root event is emitted.
  ///
  /// Its `root` parameter provides the emitted event and its `length` parameter
  /// provides the length of the nested streams generated by [OneToManyFlow.mapping].
  final FutureOr<void> Function(T root) onRoot;

  /// Called when a children event is emitted.
  ///
  /// Its `root` parameter provides their respective root event and its `children`
  /// parameter provides the emitted event.
  final FutureOr<void> Function(T root, List<R> children) onChildren;

  const _OneToManyFlowCallback({
    required this.onRoot,
    required this.onChildren,
  });
}

typedef _FlowBuilder<T, R> = SequenceFlow<R> Function(
    T, List<Stream<R>>, ValueConsumer<List<AsyncSnapshot<R>>>);

/// Combines multiple streams based on a one-to-many relationship between them.
///
/// The relationship is provided by [mapping]. When [stream] emits an event,
/// call [mapping] on it, which will create a list of N sub-streams. When all
/// sub-streams emit at least one value (generating N values), supply a
/// [SyncOneToManyValue], with `v` as [SyncOneToManyValue.parent] and all N emitted values
/// as [SyncOneToManyValue.children], in the same order as its originating streams.
///
/// --------------------------
///
/// In below representations,
///
/// - a `-` represents a waiting state;
/// - a `=` represents an active state;
/// - a `|` represents a change in the stream;
/// - a `[XX]` represents an emitted event;
/// - a `[  ]` represents the absence of an event;
/// - a line starting with `A` represents [stream];
/// - a line starting with `S#` represents a list of streams returned by [mapping];
/// - a line starting with `R` represents the values emitted by this flow.
///
/// If [stream] emits a new event while not all sub-streams from the previous
/// event have emitted at least one value, the values emitted from these
/// previous sub-streams will be dismissed:
///
/// ```dart
/// A  ====[E1]===[  ]===[  ]===[E2]===[  ]===[  ]===[  ]
/// S1 -------|===[V1]===[  ]======|===[V3]===[  ]===[  ]
/// S2 -------|===[  ]===[  ]======|===[  ]===[V4]===[  ]
/// S3 -------|===[  ]===[V2]======|===[  ]===[  ]===[V5]
/// R  ----------------------------------------------[R1]
/// ```
///
/// where `R1` is an `OneToManyValue(E2, [V3, V4, V5])`. Note that `V1` and `V2`
/// were dismissed.
///
/// If 1) [stream] emits an event E1; 2) [mapping] returns S1, S2 and S3 after
/// being called for E1; 3) S1, S2 and S3 emit V1, V2 and V3, respectively; 4)
/// this flow supplies an [SyncOneToManyValue] containing E1 and V1, V2 and V3;
/// and 5) S2 emits a value V4, this flow will supply another [SyncOneToManyValue]
/// containing E1 and V1, V4 and V3.
///
/// ```dart
/// A  ===[E1]===[  ]===[  ]===[  ]===[  ]===[  ]
/// S1 ------|===[V1]===[  ]===[  ]===[  ]===[V5]
/// S2 ------|===[  ]===[V2]===[  ]===[V4]===[  ]
/// S3 ------|===[  ]===[  ]===[V3]===[  ]===[  ]
/// R  ------------------------[R1]===[R2]===[R3]
/// ```
///
/// where `R1` is an `OneToManyValue(E1, [V1, V2, V3])`, `R2` is an
/// `OneToManyValue(E1, [V1, V3, V4])` and `R3` is an
/// `OneToManyValue(E1, [V5, V3, V4])`.
class OneToManyFlow<T, R> extends Flow {
  /// Supplies values only when all sub-streams emit at least one event.
  factory OneToManyFlow.lazy(
    Stream<T> stream, {
    required Stream<List<R>> Function(T) mapping,
    required ValueConsumer<OneToOneValue<T, List<R>>> consumer,
  }) {
    return OneToManyFlow.eager(
      stream,
      mapping: mapping,
      consumer: ValueConsumer.lambda((value) {
        value.child.choose(
          onWaiting: () {},
          onActive: (children) {
            consumer.apply(OneToOneValue(root: value.root, child: children));
          },
        );
      }),
    );
  }

  /// Supplies values as soon as possible.
  ///
  /// If a value is not available yet, it'll be supplied as a [AsyncSnapshot.waiting].
  /// Otherwise, it'll be supplied as a [AsyncSnapshot.data] containing the
  /// emitted value.
  factory OneToManyFlow.eager(
    Stream<T> stream, {
    required Stream<List<R>> Function(T) mapping,
    required ValueConsumer<OneToOneValue<T, AsyncSnapshot<List<R>>>> consumer,
  }) {
    return OneToManyFlow._(
      stream: stream,
      mapping: mapping,
      flowBuilder: (root, streams, flowConsumer) {
        return SequenceFlow.eager(streams, consumer: flowConsumer);
      },
      callback: _OneToManyFlowCallback(
        onRoot: (root) {
          consumer.apply(
            OneToOneValue(root: root, child: const AsyncSnapshot.waiting()),
          );
        },
        onChildren: (root, children) {
          consumer.apply(
            OneToOneValue(root: root, child: AsyncSnapshot.data(children)),
          );
        },
      ),
    );
  }

  /// Stream that supplies the root events.
  ///
  /// A root event is the left-side of the relationship 1:N.
  final Stream<T> stream;

  /// Function applied for each root event, creating the sub-streams associated to it.
  ///
  /// A sub-stream is the right-side of the relationship 1:N.
  final Stream<List<R>> Function(T) mapping;

  /// Function applied when creating a flow to listen to the sub-streams created.
  ///
  /// Its first parameter provides the root event; its second parameter provides
  /// the sub-streams associated with this event; and its third parameter provides
  /// the consumer to be used whenever the built flow emits events.
  final _FlowBuilder<T, R> flowBuilder;

  /// Callback used to handle the events this flow will create.
  final _OneToManyFlowCallback<T, R>? callback;

  const OneToManyFlow._({
    required this.stream,
    required this.mapping,
    required this.flowBuilder,
    this.callback,
  });

  @override
  FlowState start() => _State(
        stream: stream,
        mapping: mapping,
        flowBuilder: flowBuilder,
        callback: callback,
      );
}

class _State<T, R> extends FlowState {
  late final StreamSubscription<void> _subscription;
  StreamSubscription<void>? _nestedSubscription;

  final DoneCompleter _done = DoneCompleter();

  _State({
    required Stream<T> stream,
    required Stream<List<R>> Function(T) mapping,
    required _FlowBuilder<T, R> flowBuilder,
    _OneToManyFlowCallback<T, R>? callback,
  }) {
    _subscription = stream.listen(
      (event) async {
        callback?.onRoot(event);
        await _nestedSubscription?.cancel();

        final Stream<List<R>> nestedStream = mapping(event);
        _nestedSubscription = nestedStream.listen((children) {
          callback?.onChildren(event, children);
        }, onDone: () => _done.childDone());
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
