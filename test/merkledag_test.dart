import 'dart:async';
import 'dart:typed_data';
import 'package:collection/collection.dart'; // For listEquals
import 'package:dcid/dcid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:merkledag/src/broadcaster.dart'; // Import for Mocking
import 'package:merkledag/src/dag_syncer.dart'; // Import for Mocking
import 'package:merkledag/src/merkle_node.dart'; // Ensure MerkleNode is available for direct use if needed
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'merkledag_test.mocks.dart'; // Import generated mocks

// Define a simple OpaquePayload for testing
class _TestOpaquePayload implements CRDTPayload<Uint8List> {
  @override
  final Uint8List value;

  _TestOpaquePayload(this.value);

  @override
  CRDTPayload<Uint8List> merge(CRDTPayload<Uint8List> other) {
    // For OpaquePayload, merge is typically last-write-wins,
    // meaning the 'other' payload (the new one) wins.
    return other;
  }

  @override
  Uint8List toCanonicalBytes() {
    return value;
  }

  @override
  String toString() => 'TestOpaquePayload(${value.lengthInBytes} bytes)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TestOpaquePayload &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(value, other.value);

  @override
  int get hashCode => const DeepCollectionEquality().hash(value);
}

@GenerateMocks([DAGSyncer, Broadcaster])
void main() {
  group('CID Tests', () {
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

  group('MerkleCRDT with Mock Components (GSet)', () {
    late MockDAGSyncer<GSet<String>> gsetDagSyncer;
    late MockBroadcaster gsetBroadcaster;
    late MerkleCRDT<Set<String>, GSet<String>> gsetCrdt;
    late StreamController<String> gsetBroadcastController;

    setUp(() {
      gsetDagSyncer = MockDAGSyncer<GSet<String>>();
      gsetBroadcaster = MockBroadcaster();
      gsetBroadcastController = StreamController<String>.broadcast();

      when(gsetDagSyncer.put(any)).thenAnswer((_) async {});
      when(gsetDagSyncer.get(any)).thenAnswer((invocation) async {
        return null;
      });
      when(gsetBroadcaster.broadcast(any)).thenAnswer((invocation) async {
        gsetBroadcastController.add(invocation.positionalArguments[0] as String);
      });
      when(gsetBroadcaster.subscribe()).thenAnswer((_) => gsetBroadcastController.stream);

      gsetCrdt = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: gsetDagSyncer,
        broadcaster: gsetBroadcaster,
      );
    });

    tearDown(() {
      gsetBroadcastController.close();
    });

    test('Add payload to MerkleCRDT (GSet)', () async {
      final set = GSet<String>();
      set.add('apple');
      
      final cid = await gsetCrdt.add(set);

      expect(cid, isNotNull);
      expect(gsetCrdt.roots.length, equals(1));
      expect(gsetCrdt.roots.first, equals(cid));
      
      verify(gsetDagSyncer.put(any)).called(1);
      verify(gsetBroadcaster.broadcast(cid.toString())).called(1);

      final state = await gsetCrdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, contains('apple'));
    });

    test('Merge two MerkleCRDTs (GSet)', () async {
      final set1Payload = GSet<String>()..add('apple');
      final cid1 = await gsetCrdt.add(set1Payload);
      final node1 = MerkleNode.create(set1Payload, <CID>{}); 
      when(gsetDagSyncer.get(cid1)).thenAnswer((_) async => node1);

      final set2Payload = GSet<String>()..add('banana');
      final node2 = MerkleNode.create(set2Payload, <CID>{});
      final cid2 = node2.cid;
      when(gsetDagSyncer.get(cid2)).thenAnswer((_) async => node2);
      
      gsetBroadcastController.add(cid2.toString());
      await Future.delayed(Duration.zero); 

      final state = await gsetCrdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, containsAll(['apple', 'banana']));
    });

    test('onRemoteUpdateProcessed callback is invoked (GSet)', () async {
      bool callbackInvoked = false;
      final StreamController<String> localBroadcasterController = StreamController<String>.broadcast();
      final localBroadcaster = MockBroadcaster(); 
      when(localBroadcaster.subscribe()).thenAnswer((_) => localBroadcasterController.stream);

      final crdtWithCallback = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: gsetDagSyncer, 
        broadcaster: localBroadcaster,
        onRemoteUpdateProcessed: () {
          callbackInvoked = true;
        },
      );

      final remotePayload = GSet<String>()..add('remote_value');
      final remoteNode = MerkleNode.create(remotePayload, <CID>{});
      final remoteCid = remoteNode.cid;

      when(gsetDagSyncer.get(remoteCid)).thenAnswer((_) async => remoteNode);

      localBroadcasterController.add(remoteCid.toString());
      await Future.delayed(Duration.zero); 

      expect(callbackInvoked, isTrue, reason: 'onRemoteUpdateProcessed callback should have been invoked.');

      final state = await crdtWithCallback.getState();
      expect(state, isNotNull);
      expect(state!.elements, contains('remote_value'));
      
      await localBroadcasterController.close();
    });
  });

  group('MerkleCRDT with OpaquePayload (Idempotency Test)', () {
    late MockDAGSyncer<_TestOpaquePayload> opaqueDagSyncer;
    late MockBroadcaster opaqueBroadcaster;
    late MerkleCRDT<Uint8List, _TestOpaquePayload> opaqueCrdt;
    late StreamController<String> opaqueBroadcastController;

    setUp(() {
      opaqueDagSyncer = MockDAGSyncer<_TestOpaquePayload>();
      opaqueBroadcaster = MockBroadcaster();
      opaqueBroadcastController = StreamController<String>.broadcast();

      when(opaqueDagSyncer.put(any)).thenAnswer((_) async {});
      when(opaqueBroadcaster.broadcast(any)).thenAnswer((invocation) async {
         opaqueBroadcastController.add(invocation.positionalArguments[0] as String);
      });
      when(opaqueBroadcaster.subscribe()).thenAnswer((_) => opaqueBroadcastController.stream);

      opaqueCrdt = MerkleCRDT<Uint8List, _TestOpaquePayload>(
        dagSyncer: opaqueDagSyncer,
        broadcaster: opaqueBroadcaster,
      );
    });

    tearDown(() {
      opaqueBroadcastController.close();
    });

    test('add method is idempotent for identical OpaquePayload', () async {
      final payloadData = Uint8List.fromList([1, 2, 3]);
      final testPayload = _TestOpaquePayload(payloadData);

      // --- Perform actions ---
      // First add
      final cid1 = await opaqueCrdt.add(testPayload);
      
      // Second add with identical payload
      final cid2 = await opaqueCrdt.add(testPayload);

      // --- Assertions on CIDs and state ---
      expect(cid1, isNotNull, reason: "CID from first add should not be null.");
      expect(cid2, equals(cid1), reason: 'CID should be the same for identical payload on second add (no-op).');
      
      final state = await opaqueCrdt.getState();
      expect(state, isNotNull, reason: "State should not be null after adds.");
      expect(const DeepCollectionEquality().equals(state!.value, payloadData), isTrue, reason: "State value should match the added payload.");
      expect(opaqueCrdt.roots.length, equals(1), reason: "There should be only one root.");
      expect(opaqueCrdt.roots.first, equals(cid1), reason: "The root should be the CID from the first add.");

      // --- Verifications for mock interactions ---
      // Verify DAGSyncer.put interactions
      // Use a fresh verify for capturing all calls up to this point.
      final capturedPutArgs = verify(opaqueDagSyncer.put(captureAny)).captured;
      expect(capturedPutArgs.length, 1, reason: "DAGSyncer.put should be called exactly once in total (only for the first add).");
      // Ensure the captured argument is what we expect from the first (and only) put call
      final MerkleNode<dynamic> capturedNode = capturedPutArgs.first as MerkleNode<dynamic>;
      expect(capturedNode.cid, cid1, reason: "Captured node's CID should match returned CID from the first add.");
      expect(const DeepCollectionEquality().equals((capturedNode.payload as _TestOpaquePayload).toCanonicalBytes(), testPayload.toCanonicalBytes()), isTrue, reason: "Captured node's payload should match the test payload.");

      // Verify Broadcaster.broadcast interactions
      // Use a fresh verify for capturing all calls up to this point.
      final capturedBroadcastArgs = verify(opaqueBroadcaster.broadcast(captureAny)).captured;
      expect(capturedBroadcastArgs.length, 1, reason: "Broadcaster.broadcast should be called exactly once in total (only for the first add).");
      // Ensure the captured argument is what we expect from the first (and only) broadcast call
      expect(capturedBroadcastArgs.first, equals(cid1.toString()), reason: "Broadcasted argument should be cid1.toString() from the first add.");
      
      // By checking capturedArgs.length == 1 for both put and broadcast,
      // we implicitly verify that no further calls were made during the second 'add' operation.
    });

    test('add method creates new head for different OpaquePayload', () async {
      final payloadData1 = Uint8List.fromList([1, 2, 3]);
      final opaquePayload1 = _TestOpaquePayload(payloadData1);

      final payloadData2 = Uint8List.fromList([4, 5, 6]);
      final opaquePayload2 = _TestOpaquePayload(payloadData2);

      // --- Perform actions ---
      // First add
      final cid1 = await opaqueCrdt.add(opaquePayload1);
      
      // Second add with different payload
      final cid2 = await opaqueCrdt.add(opaquePayload2);

      // --- Assertions on CIDs and state ---
      expect(cid1, isNotNull, reason: "CID from first add should not be null.");
      expect(cid2, isNotNull, reason: "CID from second add should not be null.");
      expect(cid2, isNot(equals(cid1)), reason: 'CID should be different for a new payload.');
      
      final stateAfterAdds = await opaqueCrdt.getState();
      expect(stateAfterAdds, isNotNull, reason: "State should not be null after adds.");
      // After two different OpaquePayloads, the LWW merge means the second one is the current state.
      expect(const DeepCollectionEquality().equals(stateAfterAdds!.value, payloadData2), isTrue, reason: 'State should reflect the second payload.');
      expect(opaqueCrdt.roots.length, equals(1), reason: "There should be only one root.");
      expect(opaqueCrdt.roots.first, equals(cid2), reason: "The root should be the CID from the second add.");

      // --- Verifications for mock interactions ---
      // Verify DAGSyncer.put interactions
      final capturedPutArgs = verify(opaqueDagSyncer.put(captureAny)).captured;
      expect(capturedPutArgs.length, 2, reason: "DAGSyncer.put should be called twice (once for each add).");
      
      // Check first put call
      final MerkleNode<dynamic> firstPutNode = capturedPutArgs[0] as MerkleNode<dynamic>;
      expect(firstPutNode.cid, cid1, reason: "First captured node's CID should match cid1.");
      expect(const DeepCollectionEquality().equals((firstPutNode.payload as _TestOpaquePayload).toCanonicalBytes(), opaquePayload1.toCanonicalBytes()), isTrue, reason: "First captured node's payload should match opaquePayload1.");

      // Check second put call
      final MerkleNode<dynamic> secondPutNode = capturedPutArgs[1] as MerkleNode<dynamic>;
      expect(secondPutNode.cid, cid2, reason: "Second captured node's CID should match cid2.");
      expect(const DeepCollectionEquality().equals((secondPutNode.payload as _TestOpaquePayload).toCanonicalBytes(), opaquePayload2.toCanonicalBytes()), isTrue, reason: "Second captured node's payload should match opaquePayload2.");

      // Verify Broadcaster.broadcast interactions
      final capturedBroadcastArgs = verify(opaqueBroadcaster.broadcast(captureAny)).captured;
      expect(capturedBroadcastArgs.length, 2, reason: "Broadcaster.broadcast should be called twice (once for each add).");
      
      // Check first broadcast call
      expect(capturedBroadcastArgs[0], equals(cid1.toString()), reason: "First broadcasted argument should be cid1.toString().");
      
      // Check second broadcast call
      expect(capturedBroadcastArgs[1], equals(cid2.toString()), reason: "Second broadcasted argument should be cid2.toString().");
    });
  });
}
