import 'dart:convert';
import 'dart:typed_data';
import 'package:merkledag/src/crdt_payload.dart'; // Adjusted import

/// A Grow-only Set CRDT implementation
class GSet<T> implements CRDTPayload<Set<T>> {
  /// The internal set of elements
  final Set<T> _elements = {};

  /// Creates an empty GSet
  GSet();

  /// Creates a GSet from a list of elements
  GSet.fromList(List<T> elements) {
    _elements.addAll(elements);
  }

  /// Creates a GSet from a JSON string
  factory GSet.fromJson(String json) {
    final List<dynamic> list = jsonDecode(json);
    return GSet<T>.fromList(list.cast<T>());
  }

  @override
  Set<T> get value => Set.unmodifiable(_elements);

  /// Adds an element to the set
  void add(T element) {
    _elements.add(element);
  }

  /// Checks if the set contains an element
  bool contains(T element) {
    return _elements.contains(element);
  }

  /// Returns the number of elements in the set
  int get length => _elements.length;

  /// Returns true if the set is empty
  bool get isEmpty => _elements.isEmpty;

  /// Returns true if the set is not empty
  bool get isNotEmpty => _elements.isNotEmpty;

  /// Returns an iterator over the elements of the set
  Iterable<T> get elements => Set.unmodifiable(_elements);

  /// Converts the set to a list
  List<T> toList() => _elements.toList();

  /// Converts the set to a JSON string
  String toJson() => jsonEncode(_elements.toList());

  @override
  GSet<T> merge(CRDTPayload<Set<T>> other) {
    if (other is! GSet<T>) {
      throw ArgumentError(
          'Can only merge GSet with another GSet. Got ${other.runtimeType}');
    }
    final newSet = GSet<T>();
    newSet._elements.addAll(this.value);
    newSet._elements.addAll(other.value);
    return newSet;
  }

  @override
  String toString() => _elements.toString(); // For debugging

  @override
  Uint8List toCanonicalBytes() {
    final List<Uint8List> elementBytesList = _elements
        .map((e) => utf8.encode(e.toString())) // Assuming T.toString() is canonical enough
        .toList();

    // Sort the Uint8List representations lexicographically
    elementBytesList.sort((a, b) {
      final lenA = a.length;
      final lenB = b.length;
      final minLen = lenA < lenB ? lenA : lenB;
      for (int i = 0; i < minLen; i++) {
        if (a[i] != b[i]) {
          return a[i].compareTo(b[i]);
        }
      }
      return lenA.compareTo(lenB);
    });

    final builder = BytesBuilder(copy: false);
    for (final bytes in elementBytesList) {
      builder.add(bytes);
    }
    return builder.toBytes();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GSet<T>) return false;
    if (_elements.length != other._elements.length) return false;
    return _elements.containsAll(other._elements);
  }

  @override
  int get hashCode => _elements.hashCode;
}
