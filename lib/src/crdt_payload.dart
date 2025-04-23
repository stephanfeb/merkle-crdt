/// Interface for CRDT payloads that can be embedded in Merkle nodes
abstract class CRDTPayload<T> {
  /// Merges this payload with another payload
  T merge(T other);
  
  /// Returns a string representation of this payload
  @override
  String toString();
}