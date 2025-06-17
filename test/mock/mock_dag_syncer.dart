import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart';

/// A mock implementation of the DAG-Syncer interface
class MockDAGSyncer<T> implements DAGSyncer<T> {
  final Map<String, MerkleNode<T>> _nodes = {};

  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    _nodes[node.cid.toString()] = node;
  }
}
