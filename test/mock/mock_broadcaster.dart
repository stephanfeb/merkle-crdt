import 'dart:async';

import 'package:merkledag/merkledag.dart';

/// A mock implementation of the Broadcaster interface
class MockBroadcaster implements Broadcaster {
  final List<StreamController<String>> _controllers = [];

  @override
  Future<void> broadcast(String cidString) async {
    for (final controller in _controllers) {
      controller.add(cidString);
    }
  }

  @override
  Stream<String> subscribe() {
    final controller = StreamController<String>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }
}
