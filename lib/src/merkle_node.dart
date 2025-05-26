import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dart_cid/dart_cid.dart';
// Assuming dart_cid uses standard multihash format and provides codec constants.

// Standard IPLD codecs (from https://github.com/multiformats/multicodec/blob/master/table.csv)
const int codecDagPb = 0x70;
const int codecRaw = 0x55;

// Standard Multihash codes (from https://github.com/multiformats/multicodec/blob/master/table.csv)
const int mhSha2_256 = 0x12; // sha2-256

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
    final dataBytes = utf8.encode(contentString);
    
    // 1. Create the hash digest
    final digestBytes = crypto.sha256.convert(dataBytes).bytes;
    
    // 2. Create the multihash: code + length + digest
    // <multihash-algorithm-code><digest-length><digest-value>
    var multihashBuilder = BytesBuilder();
    multihashBuilder.addByte(mhSha2_256); // sha2-256 multihash code
    multihashBuilder.addByte(digestBytes.length); // length of the digest
    multihashBuilder.add(digestBytes);
    final multihash = Uint8List.fromList(multihashBuilder.toBytes());

    // 3. Create CID (version 1)
    // CIDv1: <cid-version><multicodec-content-type><multihash>
    // Assuming the CID class constructor takes these parts or there's a factory
    // CID(version, codec, multihashBytes)
    final newCid = CID(1, codecDagPb, multihash); // Using CID constructor
    
    return MerkleNode(
      cid: newCid,
      payload: payload,
      children: Set.from(children),
    );
  }

  /// Creates a string representation of the node content for hashing
  static String _createContentString(dynamic payload, Set<CID> children) { 
    final childrenStr = children.map((c) => c.toString()).join(',');
    return '$payload|$childrenStr';
  }

  @override
  String toString() => 'MerkleNode(cid: $cid, payload: $payload, children: $children)';
}
