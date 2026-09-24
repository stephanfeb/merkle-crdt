import 'package:dcid/dcid.dart';

import 'merkle_node.dart';
import 'dag_syncer.dart';
import 'abstract_merkle_dag.dart'; // Import the base class

/// A Merkle-Clock is a Merkle-DAG where each node represents an event
class MerkleClock<T> extends AbstractMerkleDAG<T> {
  // dagSyncer, instanceRoots, instanceNodeCache, and roots getter are inherited

  MerkleClock({
    required DAGSyncer<T> dagSyncer,
    int maxCacheSize = 1000, // Default matches base class
  }) : super(dagSyncer: dagSyncer, maxCacheSize: maxCacheSize);

  // roots getter is inherited

  /// Adds a new node to the Merkle-Clock
  Future<CID> addNode(T payload) async {
    return lock.synchronized(() async {
      // Create a new node with the payload and current roots as children
      final node = MerkleNode.create(payload, super.instanceRoots); // Use inherited instanceRoots
      
      // Add the node to the cache (inherited instanceNodeCache)
      super.instanceNodeCache[node.cid.toString()] = node;
      
      // Make the node available to other replicas (inherited dagSyncer)
      await super.dagSyncer.put(node);
      
      // Update the roots (inherited instanceRoots)
      super.instanceRoots = {node.cid};
      
      return node.cid;
    });
  }

  /// Merges another Merkle-Clock with this one
  Future<void> merge(CID remoteCid) async {
    return lock.synchronized(() async {
      // Ensure the remote node is fetched and cached if it exists.
      final remoteNode = await getNode(remoteCid); // Uses inherited getNode
      if (remoteNode == null) return;

      // Use commonMergeLogic from the base class to handle root updates.
      // MerkleClock's merge logic aligns directly with commonMergeLogic.
      await commonMergeLogic(remoteCid);
    });
  }

  // _isIncluded, _isDescendant, _isDescendantOf are inherited and made public in base.
  // (e.g. isIncluded, isDescendant, isDescendantOf)
}
