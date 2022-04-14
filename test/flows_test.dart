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
    late List<StreamController<String>> inners;
    late _ValueStorage<OneToManyValue<int, String>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inners = List.generate(3, (i) => StreamController());

      storage = _ValueStorage();

      flow = OneToManyFlow<int, String>.lazy(
        outer.stream,
        mapping: (_) => inners.map((inner) => inner.stream).toList(),
        consumer: ValueConsumer.lambda((v) => storage.value = v),
      ).start();
    });

    tearDown(() async {
      await outer.close();
      await Future.wait(inners.map((inner) => inner.close()));
      await flow.dispose();
    });

    test("Do not supply until all dependents emit", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      for (int i = 0; i < 3; i++) {
        inners[i].add("V${i + 1}");
        await pump();
        expect(storage.value, i < 2 ? isNull : isNotNull);
      }
      expect(storage.value?.parent, 1);
      expect(storage.value?.children, equals(["V1", "V2", "V3"]));
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      for (int i = 0; i < 2; i++) {
        inners[i].add("V${i + 1}");
        await pump();
        expect(storage.value, isNull);
      }

      await Future.wait(inners.map((inner) => inner.close()));
      inners = List.generate(3, (_) => StreamController());

      outer.add(2);
      await pump();
      expect(storage.value, isNull);

      for (int i = 0; i < 3; i++) {
        inners[i].add("V${i + 4}");
        await pump();
        expect(storage.value, i < 2 ? isNull : isNotNull);
      }
      expect(storage.value?.parent, 2);
      expect(storage.value?.children, equals(["V4", "V5", "V6"]));
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value, isNull);

      for (int i = 0; i < 3; i++) {
        inners[i].add("V${i + 1}");
        await pump();
        expect(storage.value, i < 2 ? isNull : isNotNull);
      }
      expect(storage.value?.parent, 1);
      expect(storage.value?.children, equals(["V1", "V2", "V3"]));

      inners[1].add("V4");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children, equals(["V1", "V4", "V3"]));
    });
  });
  group('1:N flow (eager)', () {
    late StreamController<int> outer;
    late List<StreamController<String>> inners;
    late _ValueStorage<OneToManyValue<int, AsyncSnapshot<String>>> storage;
    late FlowState flow;

    setUp(() {
      outer = StreamController();
      inners = List.generate(3, (i) => StreamController());

      storage = _ValueStorage();

      flow = OneToManyFlow<int, String>.eager(
        outer.stream,
        mapping: (_) => inners.map((inner) => inner.stream).toList(),
        consumer: ValueConsumer.lambda((v) => storage.value = v),
      ).start();
    });

    tearDown(() async {
      await outer.close();
      await Future.wait(inners.map((inner) => inner.close()));
      await flow.dispose();
    });

    test("Supply as soon as root event is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.parent, 1);
      expect(
        storage.value?.children,
        everyElement(equals(const AsyncSnapshot.waiting())),
      );

      inners[0].add("V1");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.waiting());
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[1].add("V2");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V2"));
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[2].add("V3");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V2"));
      expect(storage.value?.children[2], const AsyncSnapshot.data("V3"));
    });
    test("Dismiss dependents if a new root is emitted", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.parent, 1);
      expect(
        storage.value?.children,
        everyElement(equals(const AsyncSnapshot.waiting())),
      );

      inners[0].add("V1");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.waiting());
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[1].add("V2");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V2"));
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      await Future.wait(inners.map((inner) => inner.close()));
      inners = List.generate(3, (i) => StreamController());

      outer.add(2);
      await pump();
      expect(storage.value?.parent, 2);
      expect(
        storage.value?.children,
        everyElement(equals(const AsyncSnapshot.waiting())),
      );

      inners[0].add("V3");
      await pump();
      expect(storage.value?.parent, 2);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V3"));
      expect(storage.value?.children[1], const AsyncSnapshot.waiting());
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[1].add("V4");
      await pump();
      expect(storage.value?.parent, 2);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V3"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V4"));
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[2].add("V5");
      await pump();
      expect(storage.value?.parent, 2);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V3"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V4"));
      expect(storage.value?.children[2], const AsyncSnapshot.data("V5"));
    });
    test("Supply with same root if a dependent emits", () async {
      expect(storage.value, isNull);

      outer.add(1);
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children,
          everyElement(equals(const AsyncSnapshot.waiting())));

      inners[0].add("V1");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.waiting());
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[1].add("V2");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V2"));
      expect(storage.value?.children[2], const AsyncSnapshot.waiting());

      inners[2].add("V3");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V2"));
      expect(storage.value?.children[2], const AsyncSnapshot.data("V3"));

      inners[1].add("V4");
      await pump();
      expect(storage.value?.parent, 1);
      expect(storage.value?.children[0], const AsyncSnapshot.data("V1"));
      expect(storage.value?.children[1], const AsyncSnapshot.data("V4"));
      expect(storage.value?.children[2], const AsyncSnapshot.data("V3"));
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
