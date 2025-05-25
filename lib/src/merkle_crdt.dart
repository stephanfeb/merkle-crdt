import 'cid.dart';
import 'merkle_node.dart';
import 'dag_syncer.dart';
import 'broadcaster.dart';
import 'crdt_payload.dart';

/// Implementation of a Merkle-CRDT
class MerkleCRDT<T extends CRDTPayload<T>> {
  /// The DAG-Syncer component
  final DAGSyncer<T> dagSyncer;

  /// The Broadcaster component
  final Broadcaster broadcaster;

  /// The current root CIDs of the Merkle-CRDT
  Set<MerkleDagCID> _roots = {};

  /// A cache of nodes by CID
  final Map<String, MerkleNode<T>> _nodeCache = {};

  MerkleCRDT({
    required this.dagSyncer,
    required this.broadcaster,
  }) {
    // Subscribe to broadcasts
    broadcaster.subscribe().listen(_handleBroadcast);
  }

  /// Returns the current root CIDs
  Set<MerkleDagCID> get roots => Set.from(_roots);

  /// Adds a new payload to the Merkle-CRDT
  Future<MerkleDagCID> add(T payload) async {
    // If we have an existing state, merge the new payload with it
    if (_roots.isNotEmpty) {
      final currentState = await getState();
      if (currentState != null) {
        payload = currentState.merge(payload);
      }
    }

    // Create a new node with the payload and current roots as children
    final node = MerkleNode.create(payload, _roots);

    // Add the node to the cache
    _nodeCache[node.cid.value] = node;

    // Make the node available to other replicas
    await dagSyncer.put(node);

    // Update the roots
    _roots = {node.cid};

    // Broadcast the new root CID
    await broadcaster.broadcast(node.cid.value);

    return node.cid;
  }

  /// Handles a broadcast from another replica
  Future<void> _handleBroadcast(dynamic data) async {
    if (data is String) {
      final cid = MerkleDagCID(data);
      await _merge(cid);
    }
  }

  /// Merges a remote Merkle-CRDT with this one
  Future<void> _merge(MerkleDagCID remoteCid) async {
    // Get the remote node
    final remoteNode = await dagSyncer.get(remoteCid);
    if (remoteNode == null) return;

    // Add the remote node to the cache
    _nodeCache[remoteNode.cid.value] = remoteNode;

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
  bool _isIncluded(MerkleDagCID cid) {
    // If the CID is one of our roots, it's included
    if (_roots.contains(cid)) return true;

    // Check if any of our roots include the CID
    for (final root in _roots) {
      if (_isDescendant(cid, root)) return true;
    }

    return false;
  }

  /// Checks if our DAG is included in the remote DAG
  Future<bool> _isIncludedIn(MerkleDagCID remoteCid) async {
    // Check if all our roots are descendants of the remote CID
    for (final root in _roots) {
      if (!await _isDescendantOf(root, remoteCid)) return false;
    }

    return true;
  }

  /// Checks if a CID is a descendant of another CID
  bool _isDescendant(MerkleDagCID descendant, MerkleDagCID ancestor) {
    // If they're the same, it's not a descendant
    if (descendant == ancestor) return false;

    // Get the ancestor node from the cache
    final ancestorNode = _nodeCache[ancestor.value];
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
  Future<bool> _isDescendantOf(MerkleDagCID descendant, MerkleDagCID ancestor) async {
    // If they're the same, it's not a descendant
    if (descendant == ancestor) return false;

    // Get the ancestor node, fetching it if needed
    MerkleNode<T>? ancestorNode = _nodeCache[ancestor.value];
    if (ancestorNode == null) {
      ancestorNode = await dagSyncer.get(ancestor);
      if (ancestorNode == null) return false;
      _nodeCache[ancestor.value] = ancestorNode;
    }

    // Check if the descendant is a direct child of the ancestor
    if (ancestorNode.children.contains(descendant)) return true;

    // Check if the descendant is a descendant of any of the ancestor's children
    for (final child in ancestorNode.children) {
      if (await _isDescendantOf(descendant, child)) return true;
    }

    return false;
  }

  /// Gets the current state by merging all payloads in the DAG
  Future<T?> getState() async {
    if (_roots.isEmpty) return null;

    // Start with the first root
    final firstRoot = _roots.first;
    MerkleNode<T>? firstNode = _nodeCache[firstRoot.value];
    if (firstNode == null) {
      // This will throw if the DAGSyncer.get operation fails
      firstNode = await dagSyncer.get(firstRoot);
      if (firstNode == null) return null;
      _nodeCache[firstRoot.value] = firstNode;
    }

    T state = firstNode.payload;

    // Merge with the other roots
    for (final root in _roots.skip(1)) {
      MerkleNode<T>? node = _nodeCache[root.value];
      if (node == null) {
        // This will throw if the DAGSyncer.get operation fails
        node = await dagSyncer.get(root);
        if (node == null) continue;
        _nodeCache[root.value] = node;
      }

      state = state.merge(node.payload);
    }

    return state;
  }
}
