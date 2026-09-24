import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dcid/dcid.dart';
import 'crdt_payload.dart'; // Corrected import path for CRDTPayload type

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
    // Create a canonical byte representation of the node content
    final contentBytes = _createContentBytes<T>(payload, children);

    // 1. Create the hash digest
    final digestBytes = crypto.sha256.convert(contentBytes).bytes; // contentBytes is already Uint8List

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

  /// Creates a canonical byte representation of the node content for hashing.
  static Uint8List _createContentBytes<T>(T payload, Set<CID> children) {
    final BytesBuilder builder = BytesBuilder(copy: false);

    // 1. Add payload bytes
    if (payload is CRDTPayload) {
      builder.add(payload.toCanonicalBytes());
    } else {
      // Fallback for non-CRDTPayload types, using their string representation.
      builder.add(utf8.encode(payload.toString()));
    }

    // 2. Add sorted children CIDs bytes
    // A separator between payload and children, and between children might be good for robustness.
    // For now, simple concatenation. The structure of CIDs and typical payload representations
    // might make this safe, but explicit separators are generally safer.
    // Example: builder.addByte(0); // Null byte separator

    if (children.isNotEmpty) {
      final sortedChildrenStrings = children.map((c) => c.toString()).toList();
      sortedChildrenStrings.sort();
      for (final cidStr in sortedChildrenStrings) {
        // Consider adding a prefix/delimiter for each child if ambiguity is a concern
        builder.add(utf8.encode(cidStr));
      }
    }
    return builder.toBytes();
  }

  @override
  String toString() => 'MerkleNode(cid: $cid, payload: $payload, children: $children)';

  /// Serializes the MerkleNode into a Uint8List.
  /// 
  /// This method serializes the entire MerkleNode object, including its CID,
  /// payload, and children CIDs, into a Uint8List for storage.
  Uint8List toBytes() {
    final BytesBuilder builder = BytesBuilder(copy: false);

    // 1. Add CID bytes
    final cidBytes = cid.toBytes();
    builder.add(_encodeVarint(cidBytes.length)); // Add length as varint
    builder.add(cidBytes);

    // 2. Add payload bytes
    Uint8List payloadBytes;
    if (payload is CRDTPayload) {
      payloadBytes = (payload as CRDTPayload).toCanonicalBytes();
    } else {
      // Fallback for non-CRDTPayload types
      payloadBytes = Uint8List.fromList(utf8.encode(payload.toString()));
    }
    builder.add(_encodeVarint(payloadBytes.length)); // Add length as varint
    builder.add(payloadBytes);

    // 3. Add children CIDs
    builder.add(_encodeVarint(children.length)); // Add count as varint

    // Sort children for deterministic serialization
    final sortedChildren = children.toList();
    sortedChildren.sort((a, b) => a.toString().compareTo(b.toString()));

    for (final child in sortedChildren) {
      final childBytes = child.toBytes();
      builder.add(_encodeVarint(childBytes.length)); // Add length as varint
      builder.add(childBytes);
    }

    return builder.toBytes();
  }

  /// Deserializes a Uint8List back into a MerkleNode.
  /// 
  /// This static factory method takes a Uint8List and a payloadFactory function
  /// and reconstructs the MerkleNode.
  /// 
  /// The payloadFactory function is used to convert the serialized payload bytes
  /// back into the original payload type.
  static MerkleNode<P> fromBytes<P extends CRDTPayload<V>, V>(
      Uint8List bytes, 
      P Function(Uint8List) payloadFactory) {
    int offset = 0;

    // 1. Read CID
    final cidLengthEntry = _decodeVarint(bytes, offset);
    final cidLength = cidLengthEntry.key;
    offset += cidLengthEntry.value;

    final cidBytes = bytes.sublist(offset, offset + cidLength);
    offset += cidLength;
    final cid = CID.fromBytes(cidBytes);

    // 2. Read payload
    final payloadLengthEntry = _decodeVarint(bytes, offset);
    final payloadLength = payloadLengthEntry.key;
    offset += payloadLengthEntry.value;

    final payloadBytes = bytes.sublist(offset, offset + payloadLength);
    offset += payloadLength;
    final payload = payloadFactory(payloadBytes);

    // 3. Read children CIDs
    final childrenCountEntry = _decodeVarint(bytes, offset);
    final childrenCount = childrenCountEntry.key;
    offset += childrenCountEntry.value;

    final Set<CID> children = {};
    for (int i = 0; i < childrenCount; i++) {
      final childLengthEntry = _decodeVarint(bytes, offset);
      final childLength = childLengthEntry.key;
      offset += childLengthEntry.value;

      final childBytes = bytes.sublist(offset, offset + childLength);
      offset += childLength;
      children.add(CID.fromBytes(childBytes));
    }

    return MerkleNode<P>(
      cid: cid,
      payload: payload,
      children: children,
    );
  }

  /// Encodes an integer as a varint (variable-length integer).
  static Uint8List _encodeVarint(int value) {
    if (value < 0) {
      throw ArgumentError('Cannot encode negative value as varint: $value');
    }

    final List<int> bytes = [];

    do {
      int byte = value & 0x7F;
      value >>= 7;
      if (value != 0) {
        byte |= 0x80;
      }
      bytes.add(byte);
    } while (value != 0);

    return Uint8List.fromList(bytes);
  }

  /// Decodes a varint (variable-length integer) from bytes.
  /// 
  /// Returns a MapEntry where the key is the decoded integer value
  /// and the value is the number of bytes consumed.
  static MapEntry<int, int> _decodeVarint(Uint8List bytes, int offset) {
    int result = 0;
    int shift = 0;
    int bytesRead = 0;

    while (true) {
      if (offset + bytesRead >= bytes.length) {
        throw FormatException('Incomplete varint');
      }

      final byte = bytes[offset + bytesRead];
      bytesRead++;

      result |= (byte & 0x7F) << shift;
      shift += 7;

      if ((byte & 0x80) == 0) {
        break;
      }

      if (shift > 63) {
        throw FormatException('Varint is too large');
      }
    }

    return MapEntry(result, bytesRead);
  }
}
