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
    // Sort elements by their string representation for deterministic ordering
    final sortedElements = _elements.map((e) => e.toString()).toList();
    sortedElements.sort();

    final builder = BytesBuilder(copy: false);
    
    // Write element count as varint
    builder.add(_encodeVarint(sortedElements.length));
    
    // Write each element with length prefix
    for (final element in sortedElements) {
      final elementBytes = utf8.encode(element);
      builder.add(_encodeVarint(elementBytes.length));
      builder.add(elementBytes);
    }
    
    return builder.toBytes();
  }

  /// Creates a GSet from canonical bytes produced by toCanonicalBytes()
  factory GSet.fromCanonicalBytes(Uint8List bytes) {
    int offset = 0;
    
    // Read element count
    final countEntry = _decodeVarint(bytes, offset);
    final elementCount = countEntry.key;
    offset += countEntry.value;
    
    final gset = GSet<T>();
    
    // Read each element
    for (int i = 0; i < elementCount; i++) {
      // Read element length
      final lengthEntry = _decodeVarint(bytes, offset);
      final elementLength = lengthEntry.key;
      offset += lengthEntry.value;
      
      // Read element bytes
      if (offset + elementLength > bytes.length) {
        throw FormatException('Incomplete element data at index $i');
      }
      
      final elementBytes = bytes.sublist(offset, offset + elementLength);
      offset += elementLength;
      
      final elementString = utf8.decode(elementBytes);
      
      // For generic type T, we need to convert the string back to T
      // This assumes T can be constructed from its string representation
      // For String type, this works directly. For other types, this may need customization.
      if (T == String) {
        gset.add(elementString as T);
      } else {
        // For non-String types, we'd need a way to parse from string
        // This is a limitation of the current design - ideally we'd have a parser function
        throw UnsupportedError('fromCanonicalBytes currently only supports String elements. Got type $T');
      }
    }
    
    return gset;
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
