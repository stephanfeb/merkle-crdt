import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';

void main() {
  group('CID Tests', () {
    // Helper to create a CID from a string content for testing
    CID cidFromContent(String content) => MerkleNode.create(content, <CID>{}).cid;

    test('CID equality', () {
      final cid1 = cidFromContent('abc');
      final cid2 = cidFromContent('abc');
      final cid3 = cidFromContent('def');

      expect(cid1 == cid2, isTrue);
      expect(cid1 == cid3, isFalse);
      expect(cid1.hashCode == cid2.hashCode, isTrue);
      expect(cid1.hashCode == cid3.hashCode, isFalse);
    });

    test('CID from content', () {
      final cid1 = cidFromContent('test content');
      final cid2 = cidFromContent('test content');
      final cid3 = cidFromContent('different content');

      expect(cid1 == cid2, isTrue);
      expect(cid1 == cid3, isFalse);
    });
  });

  group('MerkleNode Tests', () {
    // Helper to create a CID from a string content for testing (can reuse the one above or redefine for clarity)
    CID cidForNodeTest(String content) => MerkleNode.create(content, <CID>{}).cid;

    test('MerkleNode creation', () {
      final child1 = cidForNodeTest('child1');
      final child2 = cidForNodeTest('child2');
      final children = {child1, child2};

      final node = MerkleNode.create('test payload', children);

      expect(node.payload, equals('test payload'));
      expect(node.children, equals(children));
      expect(node.cid, isNotNull);
    });

    test('MerkleNode equality based on content', () {
      final children1 = {cidForNodeTest('child1'), cidForNodeTest('child2')};
      final children2 = {cidForNodeTest('child1'), cidForNodeTest('child2')};

      final node1 = MerkleNode.create('test payload', children1);
      final node2 = MerkleNode.create('test payload', children2);

      expect(node1.cid == node2.cid, isTrue);
    });

    test('MerkleNode different with different content', () {
      final children1 = {cidForNodeTest('child1'), cidForNodeTest('child2')};
      final children2 = {cidForNodeTest('child1'), cidForNodeTest('child3')};

      final node1 = MerkleNode.create('test payload', children1);
      final node2 = MerkleNode.create('test payload', children2);

      expect(node1.cid == node2.cid, isFalse);
    });
  });

  group('GSet Tests', () {
    test('GSet add and merge', () {
      final set1 = GSet<String>();
      set1.add('apple');
      set1.add('banana');

      final set2 = GSet<String>();
      set2.add('cherry');
      set2.add('date');

      final merged = set1.merge(set2);

      expect(merged.elements, containsAll(['apple', 'banana', 'cherry', 'date']));
      expect(merged.elements.length, equals(4));
    });

    test('GSet idempotent merge', () {
      final set1 = GSet<String>();
      set1.add('apple');
      set1.add('banana');

      final merged = set1.merge(set1);

      expect(merged.elements, equals(set1.elements));
      expect(merged.elements.length, equals(2));
    });
  });

  group('MerkleCRDT with Mock Components', () {
    late MockDAGSyncer<GSet<String>> dagSyncer;
    late MockBroadcaster broadcaster;
    late MerkleCRDT<GSet<String>> crdt;

    setUp(() {
      dagSyncer = MockDAGSyncer<GSet<String>>();
      broadcaster = MockBroadcaster();
      crdt = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('Add payload to MerkleCRDT', () async {
      final set = GSet<String>();
      set.add('apple');

      final cid = await crdt.add(set);

      expect(cid, isNotNull);
      expect(crdt.roots.length, equals(1));
      expect(crdt.roots.first, equals(cid));

      final state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, contains('apple'));
    });

    test('Merge two MerkleCRDTs', () async {
      // Create first CRDT and add a payload
      final set1 = GSet<String>();
      set1.add('apple');
      final cid1 = await crdt.add(set1);

      // Create second CRDT with the same components
      final crdt2 = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );

      // Add a different payload to the second CRDT
      final set2 = GSet<String>();
      set2.add('banana');
      final cid2 = await crdt2.add(set2);

      // Simulate broadcasting from crdt2 to crdt1
      await broadcaster.broadcast(cid2.toString());

      // Wait for the broadcast to be processed
      await Future.delayed(Duration(milliseconds: 100));

      // Get the state of the first CRDT
      final state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, containsAll(['apple', 'banana']));
    });
  });
}
