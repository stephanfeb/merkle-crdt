import 'dart:collection'; // For LinkedHashMap
import 'package:dart_cid/dart_cid.dart';
import 'package:synchronized/synchronized.dart'; // Using this for Lock

import 'merkle_node.dart';
import 'dag_syncer.dart';

/// Abstract base class for Merkle DAG structures like MerkleCRDT and MerkleClock.
///
/// Encapsulates common DAG management logic including root tracking, node caching,
/// and DAG traversal/comparison methods.
abstract class AbstractMerkleDAG<T> {
  /// Lock to ensure atomic updates to DAG state (roots, cache).
  final Lock lock = Lock(); // Made non-private for subclass access

  /// The DAG-Syncer component for fetching and putting nodes.
  final DAGSyncer<T> dagSyncer;

  /// The current root CIDs of the Merkle DAG.
  /// Intended for internal use by subclasses.
  Set<CID> instanceRoots = {};

  /// A cache of nodes by their CID string representation, with LRU behavior.
  /// Intended for internal use by subclasses.
  final LinkedHashMap<String, MerkleNode<T>> instanceNodeCache = LinkedHashMap<String, MerkleNode<T>>();
  
  /// Maximum number of nodes to keep in the cache.
  final int maxCacheSize;

  /// Constructor for AbstractMerkleDAG.
  ///
  /// Requires a [dagSyncer] for node storage and retrieval.
  /// Optionally, a [maxCacheSize] can be provided (defaults to 1000).
  AbstractMerkleDAG({required this.dagSyncer, this.maxCacheSize = 1000});

  /// Returns an unmodifiable copy of the current root CIDs.
  Set<CID> get roots => Set.from(instanceRoots);

  /// Protected method to set roots, typically used by subclasses.
  void setRootsForTesting(Set<CID> newRoots) {
    // This method is primarily for testing or specific subclass needs.
    // In general, root modification should be handled by specific DAG operations.
    instanceRoots = Set.from(newRoots);
  }
  
  /// Fetches a node from the cache or DAGSyncer.
  /// Adds the node to the cache if fetched from DAGSyncer.
  /// Implements LRU eviction if cache exceeds maxCacheSize.
  Future<MerkleNode<T>?> getNode(CID cid) async {
    final cidStr = cid.toString();
    MerkleNode<T>? node;

    if (instanceNodeCache.containsKey(cidStr)) {
      // Move to end (most recently used)
      node = instanceNodeCache.remove(cidStr)!;
      instanceNodeCache[cidStr] = node;
    } else {
      node = await dagSyncer.get(cid);
      if (node != null) {
        instanceNodeCache[cidStr] = node;
        // Evict if cache is over size
        if (maxCacheSize > 0) { // Allow disabling cache limit with 0 or negative
          while (instanceNodeCache.length > maxCacheSize) {
            instanceNodeCache.remove(instanceNodeCache.keys.first); // Remove oldest
          }
        }
      }
    }
    return node;
  }

  /// Checks if a [cid] is included in the current DAG (i.e., is a root or a descendant of a root).
  /// This is an asynchronous check that may fetch nodes from the DAGSyncer.
  Future<bool> isIncluded(CID cid) async {
    if (instanceRoots.contains(cid)) return true;
    for (final root in instanceRoots) {
      // Use the async version that fetches nodes if necessary
      if (await isDescendantOf(cid, root)) return true;
    }
    return false;
  }

  /// Checks if our current DAG (all its roots) is included in the DAG rooted at [remoteCid].
  /// This means all our current roots must be descendants of [remoteCid].
  Future<bool> isCurrentDAGIncludedIn(CID remoteCid) async {
    for (final root in instanceRoots) {
      if (!await isDescendantOf(root, remoteCid)) return false;
    }
    return true;
  }

  /// Checks if [descendantCid] is a descendant of [ancestorCid] using only cached nodes.
  /// This is a synchronous, cache-only check.
  bool isDescendant(CID descendantCid, CID ancestorCid) {
    if (descendantCid == ancestorCid) return false;

    final ancestorNode = instanceNodeCache[ancestorCid.toString()];
    if (ancestorNode == null) {
      // If ancestor is not in cache, we cannot determine using this synchronous method.
      // For a full check, isDescendantOf (async) should be used.
      return false; 
    }

    if (ancestorNode.children.contains(descendantCid)) return true;

    for (final childCid in ancestorNode.children) {
      if (isDescendant(descendantCid, childCid)) return true;
    }
    return false;
  }

  /// Checks if [descendantCid] is a descendant of [ancestorCid], fetching nodes as needed.
  /// This is an asynchronous check that may use the [dagSyncer].
  Future<bool> isDescendantOf(CID descendantCid, CID ancestorCid) async {
    if (descendantCid == ancestorCid) return false;

    final ancestorNode = await getNode(ancestorCid);
    if (ancestorNode == null) return false;

    if (ancestorNode.children.contains(descendantCid)) return true;

    for (final childCid in ancestorNode.children) {
      // Recursive call
      if (await isDescendantOf(descendantCid, childCid)) return true;
    }
    return false;
  }

  /// Common merge logic for integrating a remote DAG root.
  /// Subclasses will call this and then potentially perform their own specific root updates.
  /// Returns true if the local roots were changed by this basic merge logic.
  Future<bool> commonMergeLogic(CID remoteCid) async {
    final remoteNode = await getNode(remoteCid);
    if (remoteNode == null) {
      // Cannot find the remote node, so no merge can happen.
      return false; 
    }

    // If remoteCid is already part of our DAG, no change.
    if (await isIncluded(remoteCid)) { // Await the async isIncluded
      return false;
    }

    // If our current DAG is entirely included in the remote DAG (i.e., all our roots are descendants of remoteCid),
    // then the remoteCid becomes our new sole root.
    if (await isCurrentDAGIncludedIn(remoteCid)) {
      instanceRoots = {remoteCid};
      return true;
    }

    // Otherwise (concurrent change), add remoteCid to our set of roots.
    // This is a simplified merge; CRDTs might have more complex logic.
    // MerkleClock typically does this. MerkleCRDT might do this and then resolve.
    instanceRoots.add(remoteCid);
    return true;
  }
}
