import 'dart:async';

import '../models/async_snapshot.dart';
import '../models/value_consumer.dart';
import 'flow.dart';

class _SequenceFlowCallback<T> {
  final FutureOr<void> Function(List<AsyncSnapshot<T>>) onEvent;

  const _SequenceFlowCallback({required this.onEvent});
}

/// Combines a list of streams into a single flow.
class SequenceFlow<T> extends Flow {
  /// Supplies values only when all streams emit at least one event.
  factory SequenceFlow.lazy(
    List<Stream<T>> streams, {
    required ValueConsumer<List<T>> consumer,
  }) {
    return SequenceFlow._(
      streams,
      callback: _SequenceFlowCallback(
        onEvent: (snapshots) {
          if (snapshots.every((snapshot) =>
              snapshot.choose(onWaiting: () => false, onActive: (_) => true))) {
            consumer.apply(snapshots.map((snapshot) {
              return snapshot.choose(
                onWaiting: () => throw -1,
                onActive: (data) => data,
              );
            }).toList());
          }
        },
      ),
    );
  }

  /// Supplies values as soon as possible.
  ///
  /// If a value is not available yet, it'll be supplied as a [AsyncSnapshot.waiting].
  /// Otherwise, it'll be supplied as a [AsyncSnapshot.data] containing the
  /// emitted value.
  factory SequenceFlow.eager(
    List<Stream<T>> streams, {
    required ValueConsumer<List<AsyncSnapshot<T>>> consumer,
  }) {
    return SequenceFlow._(
      streams,
      callback: _SequenceFlowCallback(
        onEvent: (snapshots) => consumer.apply(snapshots),
      ),
    );
  }

  final List<Stream<T>> streams;
  final _SequenceFlowCallback<T>? callback;

  const SequenceFlow._(this.streams, {this.callback});

  @override
  FlowState start() => _State<T>(streams, callback: callback);
}

class _State<T> implements FlowState {
  /// Represents the snapshots of each stream in the stream list.
  ///
  /// The snapshot at position *i* in this list is the current snapshot of the
  /// stream at position *i* in [streams].
  late final List<AsyncSnapshot<T>> _snapshots;

  /// Represents the subscriptions of each stream in the stream list.
  ///
  /// The subscription at position *i* in this list is listening to the stream
  /// at position *i* in [streams].
  late final List<StreamSubscription<void>> _subscriptions;

  final Completer<void> _doneCompleter = Completer();
  late final List<bool> _doneFlags;

  _State(List<Stream<T>> streams, {_SequenceFlowCallback<T>? callback}) {
    _snapshots = streams.map((_) => AsyncSnapshot<T>.waiting()).toList();
    _doneFlags = streams.map((_) => false).toList();
    _subscriptions = List.generate(streams.length, (i) {
      return streams[i].listen(
        (event) {
          _snapshots[i] = AsyncSnapshot.data(event);
          callback?.onEvent(_snapshots);
        },
        onDone: () => _setDone(i),
      );
    });
  }

  void _setDone(int i) {
    _doneFlags[i] = true;
    if (_doneFlags.every((flag) => flag) && !_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  @override
  Future<void> wait() => _doneCompleter.future;

  @override
  Future<void> dispose() async {
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
  }
}
