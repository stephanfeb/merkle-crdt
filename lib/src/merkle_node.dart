import 'cid.dart';

/// A node in the Merkle-DAG
class MerkleNode<T> {
  /// The content identifier of this node
  final CID cid;
  
  /// The payload carried by this node
  final T payload;
  
  /// The set of children CIDs
  final Set<CID> children;

  MerkleNode({
    required this.cid,
    required this.payload,
    required this.children,
  });

  /// Creates a MerkleNode with the given payload and children
  factory MerkleNode.create(T payload, Set<CID> children) {
    // Create a string representation of the node content
    final contentString = _createContentString(payload, children);
    final cid = CID.fromContent(contentString);
    
    return MerkleNode(
      cid: cid,
      payload: payload,
      children: Set.from(children),
    );
  }

  /// Creates a string representation of the node content for hashing
  static String _createContentString(dynamic payload, Set<CID> children) {
    final childrenStr = children.map((c) => c.value).join(',');
    return '$payload|$childrenStr';
  }

  @override
  String toString() => 'MerkleNode(cid: $cid, payload: $payload, children: $children)';
}