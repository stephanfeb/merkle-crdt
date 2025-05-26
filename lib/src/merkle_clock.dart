import 'package:dart_cid/dart_cid.dart';

import 'merkle_node.dart';
import 'dag_syncer.dart';

/// A Merkle-Clock is a Merkle-DAG where each node represents an event
class MerkleClock<T> {
  /// The DAG-Syncer component
  final DAGSyncer<T> dagSyncer;
  
  /// The current root CIDs of the Merkle-Clock
  Set<CID> _roots = {};
  
  /// A cache of nodes by CID
  final Map<String, MerkleNode<T>> _nodeCache = {};

  MerkleClock({
    required this.dagSyncer,
  });

  /// Returns the current root CIDs
  Set<CID> get roots => Set.from(_roots);

  /// Adds a new node to the Merkle-Clock
  Future<CID> addNode(T payload) async {
    // Create a new node with the payload and current roots as children
    final node = MerkleNode.create(payload, _roots);
    
    // Add the node to the cache
    _nodeCache[node.cid.toString()] = node;
    
    // Make the node available to other replicas
    await dagSyncer.put(node);
    
    // Update the roots
    _roots = {node.cid};
    
    return node.cid;
  }

  /// Merges another Merkle-Clock with this one
  Future<void> merge(CID remoteCid) async {
    // Get the remote node
    final remoteNode = await dagSyncer.get(remoteCid);
    if (remoteNode == null) return;
    
    // Add the remote node to the cache
    _nodeCache[remoteNode.cid.toString()] = remoteNode;
    
    // Check if the remote node is already included in our DAG
    if (_isIncluded(remoteNode.cid)) return;
    
    // Check if our DAG is included in the remote DAG
    if (await _isIncludedIn(remoteNode.cid)) {
      // If our DAG is included in the remote DAG, update our roots
      _roots = {remoteNode.cid};
      return;
    }
    
    // If neither DAG includes the other, merge them
    _roots = {..._roots, remoteNode.cid};
  }

  /// Checks if a CID is included in our DAG
  bool _isIncluded(CID cid) {
    // If the CID is one of our roots, it's included
    if (_roots.contains(cid)) return true;
    
    // Check if any of our roots include the CID
    for (final root in _roots) {
      if (_isDescendant(cid, root)) return true;
    }
    
    return false;
  }

  /// Checks if our DAG is included in the remote DAG
  Future<bool> _isIncludedIn(CID remoteCid) async {
    // Check if all our roots are descendants of the remote CID
    for (final root in _roots) {
      if (!await _isDescendantOf(root, remoteCid)) return false;
    }
    
    return true;
  }

  /// Checks if a CID is a descendant of another CID
  bool _isDescendant(CID descendant, CID ancestor) {
    // If they're the same, it's not a descendant
    if (descendant == ancestor) return false;
    
    // Get the ancestor node from the cache
    final ancestorNode = _nodeCache[ancestor.toString()];
    if (ancestorNode == null) return false;
    
    // Check if the descendant is a direct child of the ancestor
    if (ancestorNode.children.contains(descendant)) return true;
    
    // Check if the descendant is a descendant of any of the ancestor's children
    for (final child in ancestorNode.children) {
      if (_isDescendant(descendant, child)) return true;
    }
    
    return false;
  }

  /// Checks if a CID is a descendant of another CID, fetching nodes as needed
  Future<bool> _isDescendantOf(CID descendant, CID ancestor) async {
    // If they're the same, it's not a descendant
    if (descendant == ancestor) return false;
    
    // Get the ancestor node, fetching it if needed
    MerkleNode<T>? ancestorNode = _nodeCache[ancestor.toString()];
    if (ancestorNode == null) {
      ancestorNode = await dagSyncer.get(ancestor);
      if (ancestorNode == null) return false;
      _nodeCache[ancestor.toString()] = ancestorNode;
    }
    
    // Check if the descendant is a direct child of the ancestor
    if (ancestorNode.children.contains(descendant)) return true;
    
    // Check if the descendant is a descendant of any of the ancestor's children
    for (final child in ancestorNode.children) {
      if (await _isDescendantOf(descendant, child)) return true;
    }
    
    return false;
  }
}