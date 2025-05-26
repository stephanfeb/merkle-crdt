import 'dart:typed_data';

/// Interface for CRDT payloads that can be embedded in Merkle nodes.
/// Implementations must ensure that [toCanonicalBytes] provides a deterministic
/// byte representation for consistent CID generation.
abstract class CRDTPayload<T> {
  /// The logical value of the payload.
  T get value;

  /// Merges this payload with another payload of the same type.
  /// The result is a new payload instance representing the merged state.
  CRDTPayload<T> merge(CRDTPayload<T> other);

  /// Returns a canonical byte representation of this payload.
  /// This method is crucial for consistent CID generation.
  /// Implementations should ensure that equivalent payloads always produce
  /// the exact same byte output (e.g., by sorting elements in collections,
  /// using canonical string encodings like UTF-8 for text, etc.).
  Uint8List toCanonicalBytes();

  /// Returns a string representation of this payload, primarily for debugging.
  /// This should NOT be used for serialization that affects CID generation.
  @override
  String toString();
}
