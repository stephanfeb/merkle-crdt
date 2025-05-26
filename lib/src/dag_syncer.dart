import 'package:dart_cid/dart_cid.dart';

import 'merkle_node.dart';

/// Interface for a component that enables fetching and providing Merkle-DAG nodes.
/// Implementations are responsible for the actual storage and retrieval mechanism,
/// which could be local (e.g., in-memory, disk) or remote (e.g., over a network).
abstract class DAGSyncer<T> {
  /// Gets a node by its Content Identifier (CID).
  ///
  /// Returns the [MerkleNode] if found, or `null` if the node does not exist
  /// in the underlying storage and no other error occurred.
  ///
  /// Implementations may throw exceptions for operational failures, such as:
  /// - Network errors (e.g., `SocketException` from `dart:io` if using network).
  /// - Storage errors (e.g., `FileSystemException` from `dart:io` if using disk).
  /// - Permissions issues or other backend-specific errors.
  ///
  /// Callers should be prepared to handle these exceptions.
  Future<MerkleNode<T>?> get(CID cid);
  
  /// Makes a [MerkleNode] available, typically by storing it.
  ///
  /// This operation should ensure that the node can be later retrieved via [get]
  /// using its CID.
  ///
  /// Implementations may throw exceptions for operational failures, similar to [get],
  /// such as network, storage, or permission errors.
  ///
  /// Callers should be prepared to handle these exceptions.
  Future<void> put(MerkleNode<T> node);
}
