# flows

A library that provides a new scope for infinite streams.

## Motivation

Let's suppose we have the following streams:

```dart
/// Iterates from 1 (inclusive) to [n] (inclusive), yielding the iteration value every 2 seconds.
Stream<int> outer(int n) async* {
  for (int i = 1; i <= n; i++) {
    await Future.delayed(const Duration(seconds: 2));
    yield i;
  }
}

/// Iterates from 1 (inclusive) to [m] (exclusive), unless [m] is equal to 3. Then, it'll iterate 
/// from 0 (inclusive) to infinity. For both cases, it'll yield the iteration value every 1 second.
Stream<String> inner(int m) async* {
  final double max = m == 3 ? double.infinity : m.toDouble();
  yield "outer: $m";
  for (int i = 1; i < max; i++) {
    await Future.delayed(const Duration(seconds: 1));
    yield "  inner: ${i + 1}";
  }
}
```

We want to print, for every value `v` of `outer`, `v` followed by the values returned by `inner(v)`.
Note that, if `inner` receives 3 as an argument, it'll return an infinite stream.

---

Using the Streams API, we can use `Stream.asyncExpand`:

```dart
void usingAsyncExpand() async {
  print("start");
  final Stream<String> stream = outer(2).asyncExpand(inner);
  await for (String value in stream) {
    print("value: $value");
  }
  print("end");
}
```

This will display the following output:
 
```none
start
value: outer: 1
value:   inner: 1
value: outer: 2
value:   inner: 1
value:   inner: 2
end
```

However, what if we pass 4 instead of 2 to `outer`? The output now will be:

```
start
value: outer: 1
value:   inner: 1
value: outer: 2
value:   inner: 1
value:   inner: 2
value: outer: 3
value:   inner: 1
value:   inner: 2
value:   inner: 3
value:   inner: 4
value:   inner: 5
value:   inner: 6
// [goes on to infinity]
```

Note that `outer: 4` was not displayed after 2 seconds. Instead, the `asyncExpand` is consuming all
the events from `inner`, ignoring any incoming events from `outer` until `inner` completes.

---

We could try a workaround using a `StreamController.addStream`:

```dart
void usingAddStream() async {
  print("start");
  final StreamController<String> controller = StreamController();
  final StreamSubscription<String> subscription =
      controller.stream.listen((event) => print("value: $event"));

  final Stream<int> stream = outer(4);
  await for (int value in stream) {
    controller.addStream(inner(value));
  }

  await controller.close();
  await subscription.cancel();
  print("end");
}
```

However, while this will work for the first two events from `outer`, it'll raise a `StateError` on 
the third one:

```none
Unhandled exception:
Bad state: Cannot add event while adding a stream
```

Now, the problem is that we can't add events to `StreamController` until the insertion operation is
complete (and it'll be never completed, since `inner(3)` returns an infinite stream).

---

Using this library, we can use an `OneToOneFlow<int, String>`:

```dart
void usingFlows() async {
  print("start");
  final OneToOneFlow<int, String> flow = OneToOneFlow.lazy(
    outer(4),
    mapping: (v) => inner(v),
    consumer: ValueConsumer.lambda((v) => print("value: $v")),
  );

  final FlowState<String> state = flow.start();
  await state.wait();

  await state.dispose();
  print("end");
}
```

The output now will be:

```none
start
value: OneToOneValue([1]{outer: 1})
value: OneToOneValue([1]{  inner: 1})
value: OneToOneValue([2]{outer: 2})
value: OneToOneValue([2]{  inner: 1})
value: OneToOneValue([3]{outer: 3})
value: OneToOneValue([3]{  inner: 1})
value: OneToOneValue([4]{outer: 4})
value: OneToOneValue([4]{  inner: 1})
value: OneToOneValue([4]{  inner: 2})
value: OneToOneValue([4]{  inner: 3})
value: OneToOneValue([4]{  inner: 4})
end
```

Note that now the `outer: 4` value is emitted after 2 seconds and it does not block while `inner` is 
still active. 

This is what a flow is for: handling dependent infinite streams without blocking its parent's stream.

---

A very useful scenario is database listening. We have a School table and a Student table and we want
to listen whenever both tables changes. Since a change listener emits an infinite stream, we can use
a `OneToManyFlow<School, Student>`:

```dart
class School {
  final String id;
  final String name;

  const School({required this.id, required this.name});

  @override
  String toString() => 'School{id: $id, name: $name}';
}

class Student {
  final String id;
  final String schoolId;
  final String name;

  const Student({required this.id, required this.schoolId, required this.name});

  @override
  String toString() => 'Student{id: $id, schoolId: $schoolId, name: $name}';
}

Stream<School> listenSchool(String id) async* {
  yield School(id: id, name: "School");
  await Future.delayed(const Duration(seconds: 3));
  yield School(id: id, name: "High School");
}

List<Stream<Student>> listenStudents(String schoolId) {
  return [
    () async* {
      yield Student(id: "E001", schoolId: schoolId, name: "John");
      await Future.delayed(const Duration(seconds: 1));
      yield Student(id: "E001", schoolId: schoolId, name: "John Lennon");
    }(),
    () async* {
      yield Student(id: "E002", schoolId: schoolId, name: "Paul");
      await Future.delayed(const Duration(seconds: 5));
      yield Student(id: "E002", schoolId: schoolId, name: "Paul McCartney");
    }(),
    () async* {
      yield Student(id: "E003", schoolId: schoolId, name: "George Harrison");
    }(),
  ];
}

void usingDatabaseFlow() async {
  print("start");
  final OneToManyFlow<School, Student> flow = OneToManyFlow.lazy(
    listenSchool("#001"),
    mapping: (school) => listenStudents(school.id),
    consumer: ValueConsumer.lambda((v) => print("value: $v")),
  );

  final FlowState<Student> state = flow.start();
  await state.wait();
  await state.dispose();

  print("end");
}
```

The output displayed is:

```none
start
[1] value: OneToManyValue([School{id: #001, name: School}]{Student{id: E001, schoolId: #001, name: John}, Student{id: E002, schoolId: #001, name: Paul}, Student{id: E003, schoolId: #001, name: George Harrison}})
[2] value: OneToManyValue([School{id: #001, name: School}]{Student{id: E001, schoolId: #001, name: John Lennon}, Student{id: E002, schoolId: #001, name: Paul}, Student{id: E003, schoolId: #001, name: George Harrison}})
[3] value: OneToManyValue([School{id: #001, name: High School}]{Student{id: E001, schoolId: #001, name: John}, Student{id: E002, schoolId: #001, name: Paul}, Student{id: E003, schoolId: #001, name: George Harrison}})
[4] value: OneToManyValue([School{id: #001, name: High School}]{Student{id: E001, schoolId: #001, name: John Lennon}, Student{id: E002, schoolId: #001, name: Paul}, Student{id: E003, schoolId: #001, name: George Harrison}})
[5] value: OneToManyValue([School{id: #001, name: High School}]{Student{id: E001, schoolId: #001, name: John Lennon}, Student{id: E002, schoolId: #001, name: Paul McCartney}, Student{id: E003, schoolId: #001, name: George Harrison}})
end
```

Note that:
 
- the first line displays the first event containing the school and its three students
- after 1 second, the next line displays the "John" to "John Lennon" student name change;
- after 3 seconds, the next line displays the "School" to "High School" school name change. 
    This triggers `listenStudents` again since it's being called on `mapping` parameter;
- after 1 second, the next line displays again the "John" to "John Lennon" student name change;
- after 5 seconds, the next line displays the "Paul" to "Paul McCartney" student name change.

If we used any of the two methods above (`Stream#asyncExpand` and `Stream#addStream`), we would not
be able to detect the "School" to "High School" change if `listenStudents` were an infinite stream.

## Usage

### Definitions

- An **event** is an element of type `T` that a `Stream<T>` can provide.
- An **emitted event** is an **event** that a `Stream<T>` has already provided.
- A **flow** is a specific scope based on one or more streams.
- A **value** is an element that a **flow** can provide.
- A **supplied value** is an **value** that a **Flow** has already provided.
- A **lazy flow** is a flow that supplies its values only when all values in this scope are ready.
- An **eager flow** is a flow that supplies its values as soon as possible, even if not all of them are ready.

Let's suppose a flow depends on a list of 3 streams (S1, S2 and S3), supplying a list of 3 values 
(V1, V2 and V3), where the value at position *i* contains the current event emitted by the stream at
 position *i*. 
 
If S1 emits an event, a lazy version of this flow will not supply any values, while its eager 
version will supply three `AsyncSnapshot` values, respectively: `AsyncSnapshot.data(E1)`, 
`AsyncSnapshot.waiting()` and `AsyncSnapshot.waiting()`.

If S3 emits an event, a lazy version of this flow will still not supply any values, while its eager
version will supply another three `AsyncSnapshot` values, respectively: `AsyncSnapshot.data(E1)`, 
`AsyncSnapshot.waiting()` and `AsyncSnapshot.data(E3)`.

If S2 emits an event, a lazy version of this flow will supply three values, respectively: `E1`, `E2`
and `E3`. In the other hand, an eager version of this flow will supply more three `AsyncSnapshot` 
values, respectively: `AsyncSnapshot.data(E1)`,  `AsyncSnapshot.data(E2)` and `AsyncSnapshot.data(E3)`.


### Producing

There are three flows provided by this library:

- `SequenceFlow<T>`, which keeps track of the current emitted events from a sequence of streams;
- `OneToOneFlow<T, R>`, which listens to two streams (a parent and its child);
- `OneToManyFlow<T, R>`, which listens to two or more streams (a parent and its children);

When a flow is created, you can start it using the `Flow#start` method. This will execute the flow
and return a `FlowState`. This state has two main methods: 

- `FlowState#wait`, that waits for this flow to complete (beware that if this flow
    is backed by an infinite stream, the future returned by this method may never complete);
- `FlowState#dispose`, that cancels the subscription(s) in the backed stream(s) and stops it.

To create a custom flow, extend the `Flow` class and return its respective `FlowState` on the 
`Flow#start` method. Note that instantiating a `Flow` is cheap, while instantiating a `FlowState` is not.
Ideally, a `Flow` subclass should be immutable and a `FlowState` mutable. Think of a 
[`Widget`-`Element` relationship](https://docs.flutter.dev/resources/inside-flutter#sublinear-widget-building).

### Consuming

To consume values from a flow, you can use a `ValueConsumer<R>`:
 
```dart
class MyConsumer implements ValueConsumer<OneToOneValue<int, String>> {
  const MyConsumer();

  @override
  void apply(OneToOneValue<int, String> value) {
    print(value.root);
    print(value.child);
  }
}

void consumerFromClass() {
  final OneToOneFlow<int, String> flow = OneToOneFlow<int, String>.lazy(
    Stream.fromIterable([1, 2, 3]),
    mapping: (v) => Stream.fromIterable([v, v + 1, v + 2]).map((v) => "a$v"),
    consumer: const MyConsumer(),
  );
}
```

To simulate an anonymous object, use the `ValueConsumer#lambda` factory method:

```dart
void consumerFromLambda() {
  final OneToOneFlow<int, String> flow = OneToOneFlow<int, String>.lazy(
    Stream.fromIterable([1, 2, 3]),
    mapping: (v) => Stream.fromIterable([v, v + 1, v + 2]).map((v) => "a$v"),
    consumer: ValueConsumer.lambda((value) {
      print(value.root);
      print(value.child);
    }),
  );
}
```
 
To consume using a `Stream<R>` instead, use the `Flow#stream` static method:

```dart
void flowAsStream() async {
  final Stream<OneToOneValue<int, String>> stream = Flow.stream((consumer) {
    return OneToOneFlow<int, String>.lazy(
      Stream.fromIterable([1, 2, 3]),
      mapping: (v) => Stream.fromIterable([v, v + 1, v + 2]).map((v) => "a$v"),
      consumer: consumer,
    );
  });
}
```
