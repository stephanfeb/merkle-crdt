import 'dart:async';
import '../broadcaster.dart';

/// A mock implementation of the Broadcaster interface
class MockBroadcaster implements Broadcaster {
  final List<StreamController<dynamic>> _controllers = [];

  @override
  Future<void> broadcast(data) async {
    for (final controller in _controllers) {
      controller.add(data);
    }
  }

  @override
  Stream<dynamic> subscribe() {
    final controller = StreamController<dynamic>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }
}