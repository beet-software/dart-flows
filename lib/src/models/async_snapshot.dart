abstract class AsyncSnapshot<R> {
  const factory AsyncSnapshot.waiting() = _WaitingAsyncSnapshot;

  const factory AsyncSnapshot.data(R data, {bool done}) = _ActiveAsyncSnapshot;

  const AsyncSnapshot._();

  T choose<T>({
    required T Function() onWaiting,
    required T Function(R) onActive,
  });
}

class _WaitingAsyncSnapshot<R> extends AsyncSnapshot<R> {
  const _WaitingAsyncSnapshot() : super._();

  @override
  T choose<T>({
    required T Function() onWaiting,
    required T Function(R) onActive,
  }) {
    return onWaiting();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsyncSnapshot &&
          other.choose(onWaiting: () => true, onActive: (_) => false);

  @override
  int get hashCode => 0;

  @override
  String toString() => "AsyncSnapshot<$R>.waiting()";
}

class _ActiveAsyncSnapshot<R> extends AsyncSnapshot<R> {
  final R data;
  final bool done;

  const _ActiveAsyncSnapshot(this.data, {this.done = false}) : super._();

  @override
  T choose<T>({
    required T Function() onWaiting,
    required T Function(R) onActive,
  }) {
    return onActive(data);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsyncSnapshot &&
          other.choose(
              onWaiting: () => false, onActive: (data) => data == this.data);

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => "AsyncSnapshot<$R>.active($data)";
}
