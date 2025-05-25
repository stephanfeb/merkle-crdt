import '../cid.dart';
import '../merkle_node.dart';
import '../dag_syncer.dart';

/// A mock implementation of the DAG-Syncer interface
class MockDAGSyncer<T> implements DAGSyncer<T> {
  final Map<String, MerkleNode<T>> _nodes = {};

  @override
  Future<MerkleNode<T>?> get(MerkleDagCID cid) async {
    return _nodes[cid.value];
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    _nodes[node.cid.value] = node;
  }
}