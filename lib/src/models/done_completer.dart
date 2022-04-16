import 'dart:async';

import '../utils.dart';

class DoneCompleter {
  final Completer<void> _completer = Completer();

  bool _isRootDone = false;

  void emit(P2CEventType type) {
    switch (type) {
      case P2CEventType.root:
        {
          _isRootDone = true;
          break;
        }
      case P2CEventType.child:
        {
          if (!_isRootDone) return;
          try {
            _completer.complete();
          } on StateError catch (_) {}
        }
    }
  }

  Future<void> get future => _completer.future;
}
