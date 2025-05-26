/// Interface for CRDT payloads that can be embedded in Merkle nodes
abstract class CRDTPayload<T> {
  /// Merges this payload with another payload of the same type.
  /// The result is a new payload instance representing the merged state.
  T merge(T other);
  
  /// Returns a canonical string representation of this payload.
  /// This method is crucial for consistent CID generation.
  /// Implementations should ensure that equivalent payloads always produce
  /// the exact same string output (e.g., by sorting elements in collections).
  String toCanonicalString();

  /// Returns a string representation of this payload, primarily for debugging.
  /// This should NOT be used for serialization that affects CID generation.
  @override
  String toString();
}
