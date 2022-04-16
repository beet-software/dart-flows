abstract class ValueConsumer<T> {
  const factory ValueConsumer.lambda(
    void Function(T) callback,
  ) = _LambdaValueConsumer;

  void apply(T value);
}

class _LambdaValueConsumer<T> implements ValueConsumer<T> {
  final void Function(T) applier;

  const _LambdaValueConsumer(this.applier);

  @override
  void apply(T value) => applier(value);
}

abstract class ErrorConsumer<T> {
  const factory ErrorConsumer.lambda(
    void Function(T, Object, [StackTrace?]) callback,
  ) = _LambdaErrorConsumer;

  void emit(T value, Object error, [StackTrace? stackTrace]);
}

class _LambdaErrorConsumer<T> implements ErrorConsumer<T> {
  final void Function(T, Object, [StackTrace?]) handler;

  const _LambdaErrorConsumer(this.handler);

  @override
  void emit(T value, Object error, [StackTrace? stackTrace]) =>
      handler(value, error, stackTrace);
}
