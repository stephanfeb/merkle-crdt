import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';

void main() {
  group('MerkleClock Tests', () {
    late MockDAGSyncer<String> dagSyncer;
    late MerkleClock<String> clock;

    setUp(() {
      dagSyncer = MockDAGSyncer<String>();
      clock = MerkleClock<String>(dagSyncer: dagSyncer);
    });

    test('Initial state has empty roots', () {
      expect(clock.roots, isEmpty);
    });

    test('Adding a node updates roots', () async {
      final cid = await clock.addNode('event1');
      
      expect(clock.roots.length, equals(1));
      expect(clock.roots.first, equals(cid));
    });

    test('Adding multiple nodes creates a chain', () async {
      final cid1 = await clock.addNode('event1');
      final cid2 = await clock.addNode('event2');
      
      // The second node should replace the first in roots
      expect(clock.roots.length, equals(1));
      expect(clock.roots.first, equals(cid2));
      
      // The second node should have the first as a child
      final node2 = await dagSyncer.get(cid2);
      expect(node2, isNotNull);
      expect(node2!.children, contains(cid1));
    });

    test('Merging with a node already in the DAG does nothing', () async {
      final cid1 = await clock.addNode('event1');
      final cid2 = await clock.addNode('event2');
      
      // Merge with the first node (which is already in the DAG)
      await clock.merge(cid1);
      
      // Roots should still be just the second node
      expect(clock.roots.length, equals(1));
      expect(clock.roots.first, equals(cid2));
    });

    test('Merging with a node that includes our DAG updates roots', () async {
      // Create first clock and add events
      final cid1 = await clock.addNode('event1');
      
      // Create second clock with the same DAGSyncer
      final clock2 = MerkleClock<String>(dagSyncer: dagSyncer);
      
      // Add the first node to the second clock and then add another node
      await clock2.merge(cid1);
      final cid2 = await clock2.addNode('event2');
      
      // Merge the second clock's latest node into the first clock
      await clock.merge(cid2);
      
      // The first clock should now have the second node as its root
      expect(clock.roots.length, equals(1));
      expect(clock.roots.first, equals(cid2));
    });

    test('Merging with a disjoint DAG keeps both roots', () async {
      // Create first clock and add an event
      final cid1 = await clock.addNode('event1');
      
      // Create second clock with the same DAGSyncer
      final clock2 = MerkleClock<String>(dagSyncer: dagSyncer);
      
      // Add a different event to the second clock
      final cid2 = await clock2.addNode('event2');
      
      // Merge the second clock's node into the first clock
      await clock.merge(cid2);
      
      // The first clock should now have both nodes as roots
      expect(clock.roots.length, equals(2));
      expect(clock.roots, containsAll([cid1, cid2]));
    });

    test('Adding a node after merging disjoint DAGs creates a new root with both as children', () async {
      // Create first clock and add an event
      final cid1 = await clock.addNode('event1');
      
      // Create second clock with the same DAGSyncer
      final clock2 = MerkleClock<String>(dagSyncer: dagSyncer);
      
      // Add a different event to the second clock
      final cid2 = await clock2.addNode('event2');
      
      // Merge the second clock's node into the first clock
      await clock.merge(cid2);
      
      // Add a new event to the first clock
      final cid3 = await clock.addNode('event3');
      
      // The first clock should now have only the new node as root
      expect(clock.roots.length, equals(1));
      expect(clock.roots.first, equals(cid3));
      
      // The new node should have both previous nodes as children
      final node3 = await dagSyncer.get(cid3);
      expect(node3, isNotNull);
      expect(node3!.children, containsAll([cid1, cid2]));
    });

    test('Merging with a null node does nothing', () async {
      final cid1 = await clock.addNode('event1');
      
      // Create a CID that doesn't exist in the DAGSyncer
      final nonExistentCid = MerkleDagCID('non-existent');
      
      // Merge with the non-existent CID
      await clock.merge(nonExistentCid);
      
      // Roots should remain unchanged
      expect(clock.roots.length, equals(1));
      expect(clock.roots.first, equals(cid1));
    });
  });
}