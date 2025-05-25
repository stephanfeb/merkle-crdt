import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Content Identifier for Merkle-DAG nodes
class MerkleDagCID {
  final String value;

  MerkleDagCID(this.value);

  /// Creates a CID by hashing the given content
  factory MerkleDagCID.fromContent(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return MerkleDagCID(digest.toString());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerkleDagCID && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CID($value)';
}