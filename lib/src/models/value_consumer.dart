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

