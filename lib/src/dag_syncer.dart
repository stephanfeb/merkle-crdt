import 'cid.dart';
import 'merkle_node.dart';

/// Interface for a component that enables fetching and providing Merkle-DAG nodes
abstract class DAGSyncer<T> {
  /// Gets a node by its CID
  Future<MerkleNode<T>?> get(MerkleDagCID cid);
  
  /// Makes a node available to other replicas
  Future<void> put(MerkleNode<T> node);
}