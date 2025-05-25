import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';

void main() {
  group('CID Extended Tests', () {
    test('CID with empty string', () {
      final cid = MerkleDagCID('');
      expect(cid.value, equals(''));
      expect(cid.toString(), equals('CID()'));
    });

    test('CID.fromContent with empty string', () {
      final cid = MerkleDagCID.fromContent('');
      expect(cid.value, isNotEmpty); // Should still generate a hash
    });

    test('CID.fromContent with special characters', () {
      final cid1 = MerkleDagCID.fromContent('test\nwith\nnewlines');
      final cid2 = MerkleDagCID.fromContent('test\nwith\nnewlines');
      final cid3 = MerkleDagCID.fromContent('test with spaces');
      
      expect(cid1, equals(cid2));
      expect(cid1, isNot(equals(cid3)));
    });

    test('CID.fromContent with Unicode characters', () {
      final cid1 = MerkleDagCID.fromContent('Unicode: 😀🌍🚀');
      final cid2 = MerkleDagCID.fromContent('Unicode: 😀🌍🚀');
      final cid3 = MerkleDagCID.fromContent('Different: 🎉🎊');
      
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
      final children = <MerkleDagCID>{};
      for (var i = 0; i < 100; i++) {
        children.add(MerkleDagCID('child$i'));
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
      final children1 = {MerkleDagCID('child1')};
      final children2 = {MerkleDagCID('child2')};
      
      final node1 = MerkleNode.create('same payload', children1);
      final node2 = MerkleNode.create('same payload', children2);
      
      expect(node1.cid, isNot(equals(node2.cid)));
    });

    test('MerkleNode.toString() contains payload and children info', () {
      final children = {MerkleDagCID('child1'), MerkleDagCID('child2')};
      final node = MerkleNode.create('test', children);
      
      final nodeString = node.toString();
      expect(nodeString, contains('test'));
      expect(nodeString, contains('child1'));
      expect(nodeString, contains('child2'));
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
}
