import 'dart:async';

import 'package:flows/flows.dart';
import 'package:flows/src/models/done_completer.dart';
import 'package:test/test.dart';

class _ValueStorage<T> {
  T? value;
}

Future<void> pump() => Future.delayed(Duration.zero);

enum FutureCompletion { none, success, error }

class MockDoneCompleter implements DoneCompleter {
  final DoneCompleter _completer = DoneCompleter();

  @override
  Future<void> rootDone() async {
    _completer.rootDone();
  }

  @override
  Future<void> childDone() async {
    _completer.childDone();
  }

  @override
  Future<void> get future => _completer.future;
}

void main() {
  group('1:1 flow (lazy)', () {
    late StreamController<int> outer;
    late StreamController<String> inner;
    late _ValueStorage<OneToOneValue<int, String>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inner = StreamController();

      storage = _ValueStorage();

      flow = OneToOneFlow<int, String>.lazy(
        outer.stream,
        mapping: (_) => inner.stream,
        consumer: ValueConsumer.lambda((v) => storage.value = v),
      ).start();
    });

    tearDown(() async {
      await outer.close();
      await inner.close();
      await flow.dispose();
    });

    test("Do not supply until its dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      inner.add("V1");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, "V1");
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      inner.add("V1");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, "V1");

      await inner.close();
      inner = StreamController();

      outer.add(2);
      await pump();

      expect(storage.value?.root, 1);
      expect(storage.value?.child, "V1");

      inner.add("V2");
      await pump();
      expect(storage.value?.root, 2);
      expect(storage.value?.child, "V2");
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      inner.add("V1");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, "V1");

      inner.add("V2");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, "V2");
    });
  });
  group('1:1 flow (eager)', () {
    late StreamController<int> outer;
    late StreamController<String> inner;
    late _ValueStorage<OneToOneValue<int, AsyncSnapshot<String>>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inner = StreamController();

      storage = _ValueStorage();

      flow = OneToOneFlow<int, String>.eager(
        outer.stream,
        mapping: (_) => inner.stream,
        consumer: ValueConsumer.lambda((v) => storage.value = v),
      ).start();
    });

    tearDown(() async {
      await outer.close();
      await inner.close();
      await flow.dispose();
    });

    test("Supply as soon as root event is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add("V1");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.data("V1"));
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add("V1");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.data("V1"));

      await inner.close();
      inner = StreamController();

      outer.add(2);
      await pump();

      expect(storage.value?.root, 2);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add("V2");
      await pump();
      expect(storage.value?.root, 2);
      expect(storage.value?.child, const AsyncSnapshot.data("V2"));
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add("V1");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.data("V1"));

      inner.add("V2");
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.data("V2"));
    });
  });
  group('1:N flow (lazy)', () {
    late StreamController<int> outer;
    late StreamController<List<String>> inner;
    late _ValueStorage<SyncOneToManyValue<int, String>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inner = StreamController();

      storage = _ValueStorage();

      flow = OneToManyFlow<int, String>.lazy(
        outer.stream,
        mapping: (_) => inner.stream,
        consumer: ValueConsumer.lambda((v) => storage.value = v),
      ).start();
    });

    tearDown(() async {
      await outer.close();
      await inner.close();
      await flow.dispose();
    });

    test("Do not supply until all dependents emit", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      inner.add(["V1", "V2", "V3"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, equals(["V1", "V2", "V3"]));
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      inner.add(["V1", "V2", "V3"]);
      await pump();
      expect(storage.value?.child, equals(["V1", "V2", "V3"]));

      await inner.close();
      inner = StreamController();

      outer.add(2);
      await pump();
      expect(storage.value?.child, equals(["V1", "V2", "V3"]));

      inner.add(["V4", "V5", "V6"]);
      await pump();
      expect(storage.value?.root, 2);
      expect(storage.value?.child, equals(["V4", "V5", "V6"]));
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      inner.add(["V1", "V2", "V3"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, equals(["V1", "V2", "V3"]));

      inner.add(["V4", "V5", "V6"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, equals(["V4", "V5", "V6"]));
    });
  });
  group('1:N flow (eager)', () {
    late StreamController<int> outer;
    late StreamController<List<String>> inner;
    late _ValueStorage<AsyncOneToManyValue<int, String>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inner = StreamController();

      storage = _ValueStorage();

      flow = OneToManyFlow<int, String>.eager(
        outer.stream,
        mapping: (_) => inner.stream,
        consumer: ValueConsumer.lambda((v) => storage.value = v),
      ).start();
    });

    tearDown(() async {
      await outer.close();
      await inner.close();
      await flow.dispose();
    });

    test("Supply as soon as root event is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add(["V1", "V2", "V3"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(
        storage.value?.child
            .choose(onWaiting: () => null, onActive: (data) => data),
        equals(["V1", "V2", "V3"]),
      );
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add(["V1", "V2", "V3"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(
        storage.value?.child
            .choose(onWaiting: () => null, onActive: (data) => data),
        equals(["V1", "V2", "V3"]),
      );

      await inner.close();
      inner = StreamController();

      outer.add(2);
      await pump();
      expect(storage.value?.root, 2);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add(["V3", "V4", "V5"]);
      await pump();
      expect(storage.value?.root, 2);
      expect(
        storage.value?.child
            .choose(onWaiting: () => null, onActive: (data) => data),
        equals(["V3", "V4", "V5"]),
      );
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.root, 1);
      expect(storage.value?.child, const AsyncSnapshot.waiting());

      inner.add(["V1", "V2", "V3"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(
        storage.value?.child
            .choose(onWaiting: () => null, onActive: (data) => data),
        equals(["V1", "V2", "V3"]),
      );

      inner.add(["V3", "V4", "V5"]);
      await pump();
      expect(storage.value?.root, 1);
      expect(
        storage.value?.child
            .choose(onWaiting: () => null, onActive: (data) => data),
        equals(["V3", "V4", "V5"]),
      );
    });
  });
  group('N:N flow (lazy)', () {
    void expectStorage(
      ManyToManyValue<int, List<String>> value,
      Map<int, List<String>> results,
    ) {
      assert(value.length == results.length);
      final int length = value.length;
      for (int i = 0; i < length; i++) {
        final OneToOneValue<int, List<String>> actual = value[i];
        final List<String?> expected = results[actual.root]!;
        for (int j = 0; j < actual.child.length; j++) {
          final String nestedActual = actual.child[j];
          final String? nestedExpected = expected[j];
          expect(nestedActual, nestedExpected);
        }
      }
    }

    late StreamController<List<int>> outer;
    late Map<int, StreamController<List<String>>> inners;
    late _ValueStorage<ManyToManyValue<int, List<String>>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inners = {};
      storage = _ValueStorage();
      flow = ManyToManyFlow<int, String>.lazy(
        outer.stream,
        mapping: (event) {
          final StreamController<List<String>>? controller = inners[event];
          if (controller == null) {
            throw StateError(
                "inners does not contain the respective child for $event");
          }
          return controller.stream;
        },
        consumer: ValueConsumer.lambda((value) => storage.value = value),
      ).start();
    });
    tearDown(() async {
      await outer.close();
      await Future.wait(inners.values.map((controller) => controller.close()));
      storage.value = null;
      await flow.dispose();
    });

    test("Supply as soon as root events are emitted", () async {
      expect(storage.value, isNull);

      outer.add([1, 2, 3]);
      inners = {
        for (int value in [1, 2, 3]) value: StreamController()
      };
      await pump();
      expect(storage.value, isNull);

      inners[1]!.add(["a", "b"]);
      await pump();
      expect(storage.value, isNull);

      inners[2]!.add(["c", "d"]);
      await pump();
      expect(storage.value, isNull);

      inners[3]!.add(["e", "f"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: ["c", "d"],
        3: ["e", "f"]
      });
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add([1, 2, 3]);
      inners = {
        for (int value in [1, 2, 3]) value: StreamController()
      };
      await pump();
      expect(storage.value, isNull);

      inners[1]!.add(["a", "b"]);
      await pump();
      expect(storage.value, isNull);

      inners[3]!.add(["e", "f"]);
      await pump();
      expect(storage.value, isNull);

      await Future.wait(inners.values.map((controller) => controller.close()));
      inners = {
        for (int value in [4, 5, 6]) value: StreamController()
      };
      outer.add([4, 5, 6]);
      await pump();
      expect(storage.value, isNull);

      inners[5]!.add(["c", "d"]);
      await pump();
      expect(storage.value, isNull);
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add([1, 2, 3]);
      inners = {
        for (int value in [1, 2, 3]) value: StreamController()
      };
      await pump();
      expect(storage.value, isNull);

      inners[1]!.add(["a", "b"]);
      await pump();
      expect(storage.value, isNull);

      inners[2]!.add(["c", "d"]);
      await pump();
      expect(storage.value, isNull);

      inners[3]!.add(["e", "f"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: ["c", "d"],
        3: ["e", "f"]
      });

      inners[2]!.add(["g", "h"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: ["g", "h"],
        3: ["e", "f"]
      });
    });
  });
  group('N:N flow (eager)', () {
    void expectStorage(
      ManyToManyValue<int, AsyncSnapshot<List<String>>> value,
      Map<int, List<String>?> results,
    ) {
      assert(value.length == results.length);
      final int length = value.length;
      for (int i = 0; i < length; i++) {
        final OneToOneValue<int, AsyncSnapshot<List<String>>> actual = value[i];
        final List<String>? expected = results[actual.root];
        actual.child.choose(
          onWaiting: () {},
          onActive: (child) {
            for (int j = 0; j < child.length; j++) {
              final String nestedActual = child[j];
              final String? nestedExpected = expected?[j];
              expect(nestedActual, nestedExpected);
            }
          },
        );
      }
    }

    late StreamController<List<int>> outer;
    late Map<int, StreamController<List<String>>> inners;
    late _ValueStorage<ManyToManyValue<int, AsyncSnapshot<List<String>>>>
        storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inners = {};
      storage = _ValueStorage();
      flow = ManyToManyFlow<int, String>.eager(
        outer.stream,
        mapping: (event) {
          final StreamController<List<String>>? controller = inners[event];
          if (controller == null) {
            throw StateError("inners does not contain the respective "
                "child for $event");
          }
          return controller.stream;
        },
        consumer: ValueConsumer.lambda((value) => storage.value = value),
      ).start();
    });
    tearDown(() async {
      await outer.close();
      await Future.wait(inners.values.map((controller) => controller.close()));
      storage.value = null;
      await flow.dispose();
    });

    test("Supply as soon as root events are emitted", () async {
      expect(storage.value, isNull);

      outer.add([1, 2, 3]);
      inners = {
        for (int value in [1, 2, 3]) value: StreamController()
      };
      await pump();
      expectStorage(storage.value!, {1: null, 2: null, 3: null});

      inners[1]!.add(["a", "b"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: null,
        3: null
      });

      inners[3]!.add(["e", "f"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: null,
        3: ["e", "f"]
      });

      inners[2]!.add(["c", "d"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: ["c", "d"],
        3: ["e", "f"]
      });
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add([1, 2, 3]);
      inners = {
        for (int value in [1, 2, 3]) value: StreamController()
      };
      await pump();
      expectStorage(storage.value!, {1: null, 2: null, 3: null});

      inners[1]!.add(["a", "b"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: null,
        3: null
      });

      inners[3]!.add(["e", "f"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: null,
        3: ["e", "f"]
      });

      await Future.wait(inners.values.map((controller) => controller.close()));
      inners = {
        for (int value in [4, 5, 6]) value: StreamController()
      };
      outer.add([4, 5, 6]);
      await pump();
      expectStorage(storage.value!, {4: null, 5: null, 6: null});
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add([1, 2, 3]);
      inners = {
        for (int value in [1, 2, 3]) value: StreamController()
      };
      await pump();
      expectStorage(storage.value!, {1: null, 2: null, 3: null});

      inners[1]!.add(["a", "b"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: null,
        3: null
      });

      inners[3]!.add(["e", "f"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: null,
        3: ["e", "f"]
      });

      inners[2]!.add(["c", "d"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["a", "b"],
        2: ["c", "d"],
        3: ["e", "f"]
      });

      inners[1]!.add(["g", "h"]);
      await pump();
      expectStorage(storage.value!, {
        1: ["g", "h"],
        2: ["c", "d"],
        3: ["e", "f"]
      });
    });
  });
  group('DoneCompleter', () {
    late MockDoneCompleter completer;
    late FutureCompletion status;
    setUp(() {
      completer = MockDoneCompleter();

      status = FutureCompletion.none;
      completer.future
          .then((_) => status = FutureCompletion.success)
          .catchError((_) => status = FutureCompletion.error);
    });

    test('calling rootDone before childDone should complete', () async {
      expect(status, FutureCompletion.none);
      await completer.rootDone();
      expect(status, FutureCompletion.none);
      await completer.childDone();
      expect(status, FutureCompletion.success);
    });
    test('calling rootDone multiple times should not raise errors', () async {
      expect(status, FutureCompletion.none);
      await completer.rootDone();
      expect(status, FutureCompletion.none);
      await completer.rootDone();
      expect(status, FutureCompletion.none);
      await completer.childDone();
      expect(status, FutureCompletion.success);
    });
    test('calling childDone multiple times should not raise errors', () async {
      expect(status, FutureCompletion.none);
      await completer.childDone();
      expect(status, FutureCompletion.none);
      await completer.rootDone();
      expect(status, FutureCompletion.none);
      await completer.childDone();
      expect(status, FutureCompletion.success);
    });
    test('calling childDone after complete should not raise errors', () async {
      expect(status, FutureCompletion.none);
      await completer.rootDone();
      expect(status, FutureCompletion.none);
      await completer.childDone();
      expect(status, FutureCompletion.success);
      await completer.childDone();
      expect(status, FutureCompletion.success);
    });
  });
}
