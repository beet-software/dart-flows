import 'dart:async';

import '../models/disposable.dart';
import '../models/value_consumer.dart';

/// Represents a flow.
abstract class Flow {
  static Stream<R> stream<R>(Flow Function(ValueConsumer<R>) builder) {
    final StreamController<R> controller = StreamController();
    final Flow flow = builder(ValueConsumer<R>.lambda(controller.add));
    final FlowState state = flow.start();
    state.wait().then((_) => controller.close());
    return controller.stream;
  }

  const Flow();

  FlowState start();
}

/// Represents the state of a flow.
abstract class FlowState implements Disposable {
  Future<void> wait();
}
