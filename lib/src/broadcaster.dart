/// Interface for a component that broadcasts data to other replicas
abstract class Broadcaster {
  /// Broadcasts data to other replicas
  Future<void> broadcast(dynamic data);
  
  /// Subscribes to broadcasts
  Stream<dynamic> subscribe();
}