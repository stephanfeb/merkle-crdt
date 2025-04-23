import 'package:merkledag/merkledag.dart';
import 'dart:convert';

/// A Grow-only Set CRDT implementation
class GSet<T> implements CRDTPayload<GSet<T>> {
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
  Iterable<T> get elements => _elements;

  /// Converts the set to a list
  List<T> toList() => _elements.toList();

  /// Converts the set to a JSON string
  String toJson() => jsonEncode(_elements.toList());

  @override
  GSet<T> merge(GSet<T> other) {
    final result = GSet<T>();
    result._elements.addAll(_elements);
    result._elements.addAll(other._elements);
    return result;
  }

  @override
  String toString() => _elements.toString();

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