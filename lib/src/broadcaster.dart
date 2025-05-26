/// Interface for a component that broadcasts data to other replicas and allows
/// subscription to data broadcasted by others.
///
/// Interface for a component that broadcasts data to other replicas and allows
/// subscription to data broadcasted by others.
///
/// The data broadcasted is typically the string representation of a CID for a new root.
abstract class Broadcaster {
  /// Broadcasts a [cidString] to other replicas.
  ///
  /// This is an asynchronous operation that completes when the data has been
  /// successfully dispatched for broadcast. It does not guarantee delivery.
  ///
  /// Implementations may throw exceptions for operational failures, such as:
  /// - Network errors (e.g., `SocketException` if using network).
  /// - Issues with the underlying broadcast mechanism (e.g., message queue errors).
  ///
  /// Callers should be prepared to handle these exceptions.
  Future<void> broadcast(String cidString);
  
  /// Subscribes to broadcasts from other replicas.
  ///
  /// Returns a [Stream] that emits CID strings received from broadcasts.
  ///
  /// The returned stream can also emit errors if the underlying subscription
  /// mechanism encounters an issue or if an error is explicitly broadcasted.
  /// Consumers should handle these errors using `listen(onError: ...)`.
  Stream<String> subscribe();
}
