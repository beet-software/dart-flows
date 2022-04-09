import 'dart:async';

class DoneCompleter {
  final Completer<void> _completer = Completer();

  bool _isRootDone = false;

  void rootDone() => _isRootDone = true;

  void childDone() {
    if (!_isRootDone) return;
    try {
      _completer.complete();
    } on StateError catch (_) {}
  }

  Future<void> get future => _completer.future;
}
