import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';

// A simple CRDT payload for testing serialization/deserialization
class TestPayload implements CRDTPayload<String> {
  final String _value;

  TestPayload(this._value);

  @override
  String get value => _value;

  @override
  TestPayload merge(CRDTPayload<String> other) {
    return TestPayload('${_value},${other.value}');
  }

  @override
  Uint8List toCanonicalBytes() {
    return Uint8List.fromList(utf8.encode(_value));
  }

  // Factory method to create a TestPayload from bytes
  static TestPayload fromBytes(Uint8List bytes) {
    return TestPayload(utf8.decode(bytes));
  }

  @override
  String toString() => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestPayload &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

void main() {
  // Helper to create a CID from a string content for testing
  CID cidFromContent(String content) => MerkleNode.create(content, <CID>{}).cid;

  group('CID Extended Tests', () {
    test('CID from empty string content', () {
      // CID.fromString('') would throw. Test CID generation from empty content.
      final cid = cidFromContent('');
      expect(cid, isA<CID>());
      expect(cid.toString(), isNotEmpty); 
    });

    // This test is essentially the same as above with the helper
    test('CID.fromContent with empty string (using helper)', () {
      final cid = cidFromContent('');
      expect(cid.toString(), isNotEmpty); // Should still generate a hash
    });

    test('CID.fromContent with special characters', () {
      final cid1 = cidFromContent('test\nwith\nnewlines');
      final cid2 = cidFromContent('test\nwith\nnewlines');
      final cid3 = cidFromContent('test with spaces');

      expect(cid1, equals(cid2));
      expect(cid1, isNot(equals(cid3)));
    });

    test('CID.fromContent with Unicode characters', () {
      final cid1 = cidFromContent('Unicode: 😀🌍🚀');
      final cid2 = cidFromContent('Unicode: 😀🌍🚀');
      final cid3 = cidFromContent('Different: 🎉🎊');

      expect(cid1, equals(cid2));
      expect(cid1, isNot(equals(cid3)));
    });
  });

  group('MerkleNode Extended Tests', () {
    test('MerkleNode with empty payload', () {
      final node = MerkleNode.create('', {});
      expect(node.payload, equals(''));
      expect(node.children, isEmpty);
      expect(node.cid, isNotNull);
    });

    test('MerkleNode with null-like payload', () {
      // Using a nullable type for the test
      final node = MerkleNode<String?>.create(null, {});
      expect(node.payload, isNull);
      expect(node.children, isEmpty);
      expect(node.cid, isNotNull);
    });

    test('MerkleNode with large number of children', () {
      // Create 100 children
      final children = <CID>{};
      for (var i = 0; i < 100; i++) {
        children.add(cidFromContent('child$i'));
      }

      final node = MerkleNode.create('parent', children);
      expect(node.children.length, equals(100));
    });

    test('MerkleNode with complex payload', () {
      // Create a complex payload (a map in this case)
      final payload = {
        'name': 'test',
        'value': 42,
        'nested': {'a': 1, 'b': 2}
      };

      final node = MerkleNode.create(payload, {});
      expect(node.payload, equals(payload));
    });

    test('Two MerkleNodes with same payload but different children have different CIDs', () {
      final children1 = {cidFromContent('child1')};
      final children2 = {cidFromContent('child2')};

      final node1 = MerkleNode.create('same payload', children1);
      final node2 = MerkleNode.create('same payload', children2);

      expect(node1.cid, isNot(equals(node2.cid)));
    });

    test('MerkleNode.toString() contains payload and children info', () {
      final childCid1 = cidFromContent('child1');
      final childCid2 = cidFromContent('child2');
      final children = {childCid1, childCid2};
      final node = MerkleNode.create('test', children);

      final nodeString = node.toString();
      expect(nodeString, contains('test'));
      expect(nodeString, contains(childCid1.toString()));
      expect(nodeString, contains(childCid2.toString()));
    });
  });

  group('GSet Extended Tests', () {
    test('GSet with empty initial set', () {
      final set = GSet<String>();
      expect(set.elements, isEmpty);
    });

    test('GSet with initial elements', () {
      final initialElements = {'a', 'b', 'c'};
      final set = GSet<String>.fromList(initialElements.toList());
      expect(set.elements, equals(initialElements));
    });

    test('GSet elements are unmodifiable', () {
      final set = GSet<String>();
      set.add('a');

      // This should throw because elements returns an unmodifiable set
      expect(() => (set.elements as Set<String>).add('b'), throwsUnsupportedError);
    });

    test('GSet merge with empty set', () {
      final set1 = GSet<String>();
      set1.add('a');

      final set2 = GSet<String>();

      final merged1 = set1.merge(set2);
      final merged2 = set2.merge(set1);

      expect(merged1.elements, equals({'a'}));
      expect(merged2.elements, equals({'a'}));
    });

    test('GSet merge is commutative', () {
      final set1 = GSet<String>();
      set1.add('a');
      set1.add('b');

      final set2 = GSet<String>();
      set2.add('c');
      set2.add('d');

      final merged1 = set1.merge(set2);
      final merged2 = set2.merge(set1);

      expect(merged1.elements, equals(merged2.elements));
    });

    test('GSet merge is associative', () {
      final set1 = GSet<String>();
      set1.add('a');

      final set2 = GSet<String>();
      set2.add('b');

      final set3 = GSet<String>();
      set3.add('c');

      // (set1 ∪ set2) ∪ set3
      final merged1 = set1.merge(set2).merge(set3);

      // set1 ∪ (set2 ∪ set3)
      final merged2 = set1.merge(set2.merge(set3));

      expect(merged1.elements, equals(merged2.elements));
    });

    test('GSet with different types', () {
      final intSet = GSet<int>();
      intSet.add(1);
      intSet.add(2);

      final doubleSet = GSet<double>();
      doubleSet.add(3.14);
      doubleSet.add(2.71);

      expect(intSet.elements, equals({1, 2}));
      expect(doubleSet.elements, equals({3.14, 2.71}));
    });

    test('GSet with large number of elements', () {
      final set = GSet<int>();
      for (var i = 0; i < 1000; i++) {
        set.add(i);
      }

      expect(set.elements.length, equals(1000));
    });

    test('GSet toString() returns string representation of elements', () {
      final set = GSet<String>();
      set.add('a');
      set.add('b');

      expect(set.toString(), equals('{a, b}'));
    });
  });

  group('MerkleNode Serialization Tests', () {
    test('MerkleNode with TestPayload can be serialized and deserialized', () {
      // Create a TestPayload
      final payload = TestPayload('test-payload');

      // Create some children CIDs
      final child1 = cidFromContent('child1');
      final child2 = cidFromContent('child2');
      final children = {child1, child2};

      // Create a MerkleNode with the payload and children
      final originalNode = MerkleNode.create(payload, children);

      // Serialize the node to bytes
      final bytes = originalNode.toBytes();
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);

      // Deserialize the bytes back to a MerkleNode
      final deserializedNode = MerkleNode.fromBytes<TestPayload, String>(
        bytes, 
        TestPayload.fromBytes
      );

      // Verify that the deserialized node is equivalent to the original node
      expect(deserializedNode.cid, equals(originalNode.cid));
      expect(deserializedNode.payload, equals(originalNode.payload));
      expect(deserializedNode.children, equals(originalNode.children));
    });

    test('MerkleNode with complex structure can be serialized and deserialized', () {
      // Create a more complex structure with nested children
      final payload1 = TestPayload('parent');
      final payload2 = TestPayload('child1');
      final payload3 = TestPayload('child2');

      // Create child nodes
      final childNode1 = MerkleNode.create(payload2, {});
      final childNode2 = MerkleNode.create(payload3, {});

      // Create parent node with children
      final parentNode = MerkleNode.create(payload1, {childNode1.cid, childNode2.cid});

      // Serialize the parent node
      final bytes = parentNode.toBytes();

      // Deserialize the bytes back to a MerkleNode
      final deserializedNode = MerkleNode.fromBytes<TestPayload, String>(
        bytes, 
        TestPayload.fromBytes
      );

      // Verify that the deserialized node is equivalent to the original node
      expect(deserializedNode.cid, equals(parentNode.cid));
      expect(deserializedNode.payload, equals(parentNode.payload));
      expect(deserializedNode.children, equals(parentNode.children));
    });

    test('MerkleNode with empty children can be serialized and deserialized', () {
      // Create a TestPayload
      final payload = TestPayload('no-children');

      // Create a MerkleNode with no children
      final originalNode = MerkleNode.create(payload, {});

      // Serialize the node to bytes
      final bytes = originalNode.toBytes();

      // Deserialize the bytes back to a MerkleNode
      final deserializedNode = MerkleNode.fromBytes<TestPayload, String>(
        bytes, 
        TestPayload.fromBytes
      );

      // Verify that the deserialized node is equivalent to the original node
      expect(deserializedNode.cid, equals(originalNode.cid));
      expect(deserializedNode.payload, equals(originalNode.payload));
      expect(deserializedNode.children, isEmpty);
    });

    test('MerkleNode with many children can be serialized and deserialized', () {
      // Create a TestPayload
      final payload = TestPayload('many-children');

      // Create many children CIDs
      final children = <CID>{};
      for (var i = 0; i < 100; i++) {
        children.add(cidFromContent('child$i'));
      }

      // Create a MerkleNode with many children
      final originalNode = MerkleNode.create(payload, children);

      // Serialize the node to bytes
      final bytes = originalNode.toBytes();

      // Deserialize the bytes back to a MerkleNode
      final deserializedNode = MerkleNode.fromBytes<TestPayload, String>(
        bytes, 
        TestPayload.fromBytes
      );

      // Verify that the deserialized node is equivalent to the original node
      expect(deserializedNode.cid, equals(originalNode.cid));
      expect(deserializedNode.payload, equals(originalNode.payload));
      expect(deserializedNode.children, equals(originalNode.children));
      expect(deserializedNode.children.length, equals(100));
    });
  });
}
