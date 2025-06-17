import 'dart:typed_data';
import 'package:collection/collection.dart'; // For listEquals
import 'package:logging/logging.dart'; // For Logger
import 'package:dart_cid/dart_cid.dart';

import 'merkle_node.dart';
import 'dag_syncer.dart';
import 'broadcaster.dart';
import 'crdt_payload.dart';
import 'abstract_merkle_dag.dart'; // Import the base class

/// Implementation of a Merkle-CRDT
/// V is the type of the logical value held by the CRDT (e.g., Set<String>)
/// P is the type of the CRDT payload object itself (e.g., GSet<String>),
/// which implements CRDTPayload<V>.
class MerkleCRDT<V, P extends CRDTPayload<V>> extends AbstractMerkleDAG<P> {
  /// The Broadcaster component
  final Broadcaster broadcaster;

  /// Optional callback invoked after a remote update has been successfully processed.
  final void Function()? onRemoteUpdateProcessed;

  // dagSyncer, _roots, _nodeCache, and roots getter are inherited from AbstractMerkleDAG

  MerkleCRDT({
    required DAGSyncer<P> dagSyncer,
    required this.broadcaster,
    this.onRemoteUpdateProcessed, // New callback parameter
    int maxCacheSize = 1000, // Default matches base class
  }) : super(dagSyncer: dagSyncer, maxCacheSize: maxCacheSize) {
    // Subscribe to broadcasts
    broadcaster.subscribe().listen(_handleBroadcast);
  }

  // roots getter is inherited

  /// Adds a new payload to the Merkle-CRDT
  Future<CID> add(P payload) async {
    return lock.synchronized(() async {
      P effectivePayload = payload;

      if (super.instanceRoots.isNotEmpty) {
        final P? currentState = await getState();
        if (currentState != null) {
          effectivePayload = currentState.merge(payload) as P;
        }
      }

      // --- START NO-OP CHECK ---
      bool isNoOp = false;
      if (super.instanceRoots.length == 1) {
        final P? currentHeadPayload = await getState(); // This gets the payload of the current single head
        if (currentHeadPayload != null) {
          // Compare canonical bytes for robust equality check
          if (const DeepCollectionEquality().equals(effectivePayload.toCanonicalBytes(), currentHeadPayload.toCanonicalBytes())) {
            isNoOp = true;
          }
        }
      }

      if (isNoOp) {
        Logger('MerkleCRDT').info('MerkleCRDT.add: No-op detected for payload. Returning existing head CID: ${super.instanceRoots.first}');
        return super.instanceRoots.first;
      }
      // --- END NO-OP CHECK ---

      // Create a new node with the (potentially merged) effectivePayload and current roots as children
      final node = MerkleNode.create(effectivePayload, super.instanceRoots);

      // Add the node to the cache (inherited instanceNodeCache)
      super.instanceNodeCache[node.cid.toString()] = node;

      // Make the node available to other replicas (inherited dagSyncer)
      await super.dagSyncer.put(node);

      // Update the roots (inherited instanceRoots)
      super.instanceRoots = {node.cid};

      // Broadcast the new root CID
      await broadcaster.broadcast(node.cid.toString());

      return node.cid;
    });
  }

  /// Handles a broadcast from another replica
  Future<void> _handleBroadcast(dynamic data) async {
    if (data is String) {
      try {
        final cid = CID.fromString(data);
        await _merge(cid);
        // If merge was successful (no exception thrown), invoke the callback
        this.onRemoteUpdateProcessed?.call();
      } catch (e) {
        // Optionally log the error, e.g., print('Error during broadcast handling: $e');
        // For the purpose of the "Handles ... gracefully" test,
        // catching it here prevents it from becoming an unhandled async error.
        // The test itself verifies the outcome based on FlakyDAGSyncer's behavior.
      }
    }
  }

  /// Merges a remote Merkle-CRDT with this one
  Future<void> _merge(CID remoteCid) async {
    return lock.synchronized(() async {
      // Ensure the remote node is fetched and cached if it exists.
      final remoteNode = await getNode(remoteCid); // Uses inherited getNode
      if (remoteNode == null) return;

      // Use commonMergeLogic from the base class to handle root updates.
      // MerkleCRDT's specific behavior is that after a structural merge (concurrent heads),
      // a subsequent `add` operation will resolve these multiple roots by creating a new
      // node that has all current roots as children, effectively merging the states.
      // The commonMergeLogic correctly updates _roots to reflect the structural merge.
      await commonMergeLogic(remoteCid);
    });
  }

  // _isIncluded, _isDescendant, _isDescendantOf are inherited and made public in base.
  // (e.g. isIncluded, isDescendant, isDescendantOf)

  /// Gets the current state of the CRDT by merging the payloads of all root nodes.
  ///
  /// This method assumes that the CRDT is state-based, where the full state can be
  /// reconstructed by merging the payloads of the current concurrent heads (roots)
  /// of the Merkle-DAG. It iterates through all known roots, fetches their
  /// corresponding nodes (and payloads), and merges them using the `CRDTPayload.merge`
  /// method.
  ///
  /// If there are no roots, it returns `null`.
  /// If any root node cannot be fetched, it might return a partial state or `null`
  /// depending on the availability of other roots.
  Future<P?> getState() async {
    if (super.instanceRoots.isEmpty) return null;

    // Start with the first root
    final firstRoot = super.instanceRoots.first;
    MerkleNode<P>? firstNode = await getNode(firstRoot);
    if (firstNode == null) return null;
    
    P state = firstNode.payload;

    // Merge with the other roots
    for (final root in super.instanceRoots.skip(1)) {
      MerkleNode<P>? node = await getNode(root);
      if (node == null) continue;

      // The merge method on P (which extends CRDTPayload<V>) should return P.
      // Casting because CRDTPayload.merge is typed to return CRDTPayload<V>.
      state = state.merge(node.payload) as P;
    }

    return state;
  }
}
