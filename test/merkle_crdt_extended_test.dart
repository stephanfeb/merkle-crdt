import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';
import 'dart:async';

// A custom CRDT payload for testing
class Counter implements CRDTPayload<Counter> {
  final int value;

  Counter(this.value);

  Counter increment() {
    return Counter(value + 1);
  }

  @override
  Counter merge(Counter other) {
    return Counter(value > other.value ? value : other.value);
  }

  @override
  String toString() => value.toString();
}

// A custom DAGSyncer that can simulate network failures
class FlakyDAGSyncer<T> implements DAGSyncer<T> {
  final Map<String, MerkleNode<T>> _nodes = {};
  bool failNextGet = false;
  bool failNextPut = false;
  int getDelay = 0;
  int putDelay = 0;
  bool getAttemptedAndThrew = false; // Flag to confirm 'get' was called and threw

  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    if (failNextGet) {
      failNextGet = false;
      getAttemptedAndThrew = true; // Set flag
      throw Exception('Simulated network failure during get');
    }

    if (getDelay > 0) {
      await Future.delayed(Duration(milliseconds: getDelay));
    }

    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    if (failNextPut) {
      failNextPut = false;
      throw Exception('Simulated network failure during put');
    }

    if (putDelay > 0) {
      await Future.delayed(Duration(milliseconds: putDelay));
    }

    _nodes[node.cid.toString()] = node;
  }
}

// A custom Broadcaster that can simulate network failures
class FlakyBroadcaster implements Broadcaster {
  final List<StreamController<dynamic>> _controllers = [];
  bool failNextBroadcast = false;
  int broadcastDelay = 0;

  @override
  Future<void> broadcast(data) async {
    if (failNextBroadcast) {
      failNextBroadcast = false;
      throw Exception('Simulated network failure during broadcast');
    }

    if (broadcastDelay > 0) {
      await Future.delayed(Duration(milliseconds: broadcastDelay));
    }

    for (final controller in _controllers) {
      controller.add(data);
    }
  }

  @override
  Stream<dynamic> subscribe() {
    final controller = StreamController<dynamic>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  group('MerkleCRDT Extended Tests', () {
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

    test('Initial state is null', () async {
      final state = await crdt.getState();
      expect(state, isNull);
    });

    test('Adding multiple payloads updates state correctly', () async {
      // Add first payload
      final set1 = GSet<String>();
      set1.add('a');
      await crdt.add(set1);

      // Verify state
      var state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, equals({'a'}));

      // Add second payload
      final set2 = GSet<String>();
      set2.add('b');
      await crdt.add(set2);

      // Verify state includes both elements
      state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, equals({'a', 'b'}));
    });

    test('Multiple CRDTs converge after broadcasts', () async {
      // Create multiple CRDTs with the same components
      final crdt1 = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );

      final crdt2 = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );

      final crdt3 = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );

      // Add different data to each CRDT with a delay between each add
      final set1 = GSet<String>();
      set1.add('a');
      await crdt1.add(set1);

      // Wait for the first broadcast to be processed
      await Future.delayed(Duration(milliseconds: 100));

      final set2 = GSet<String>();
      set2.add('b');
      await crdt2.add(set2);

      // Wait for the second broadcast to be processed
      await Future.delayed(Duration(milliseconds: 100));

      final set3 = GSet<String>();
      set3.add('c');
      await crdt3.add(set3);

      // Wait for the third broadcast to be processed
      await Future.delayed(Duration(milliseconds: 500));

      // Verify all CRDTs have converged to the same state
      final state1 = await crdt1.getState();
      final state2 = await crdt2.getState();
      final state3 = await crdt3.getState();

      // Print the state of each CRDT for debugging
      print('State 1: ${state1!.elements}');
      print('State 2: ${state2!.elements}');
      print('State 3: ${state3!.elements}');

      expect(state1.elements, containsAll(['a', 'b', 'c']));
      expect(state2.elements, containsAll(['a', 'b', 'c']));
      expect(state3.elements, containsAll(['a', 'b', 'c']));
    });
  });

  group('MerkleCRDT with Custom CRDT Payload', () {
    late MockDAGSyncer<Counter> dagSyncer;
    late MockBroadcaster broadcaster;
    late MerkleCRDT<Counter> crdt;

    setUp(() {
      dagSyncer = MockDAGSyncer<Counter>();
      broadcaster = MockBroadcaster();
      crdt = MerkleCRDT<Counter>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('Counter CRDT works correctly', () async {
      // Add a counter with value 5
      await crdt.add(Counter(5));

      // Verify state
      var state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.value, equals(5));

      // Add a counter with value 10
      await crdt.add(Counter(10));

      // Verify state is now 10 (the max value)
      state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.value, equals(10));

      // Add a counter with value 3 (should not change the state)
      await crdt.add(Counter(3));

      // Verify state is still 10
      state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.value, equals(10));
    });

    test('Multiple Counter CRDTs converge to max value', () async {
      // Create multiple CRDTs with the same components
      final crdt1 = MerkleCRDT<Counter>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );

      final crdt2 = MerkleCRDT<Counter>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );

      // Add different values to each CRDT
      await crdt1.add(Counter(5));
      await crdt2.add(Counter(10));

      // Wait for broadcasts to be processed
      await Future.delayed(Duration(milliseconds: 100));

      // Verify both CRDTs have converged to the max value
      final state1 = await crdt1.getState();
      final state2 = await crdt2.getState();

      expect(state1!.value, equals(10));
      expect(state2!.value, equals(10));
    });
  });

  group('MerkleCRDT with Network Failures', () {
    late FlakyDAGSyncer<GSet<String>> dagSyncer;
    late FlakyBroadcaster broadcaster;
    late MerkleCRDT<GSet<String>> crdt;

    setUp(() {
      dagSyncer = FlakyDAGSyncer<GSet<String>>();
      broadcaster = FlakyBroadcaster();
      crdt = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('Handles DAGSyncer.put failure gracefully', () async {
      // Set up the DAGSyncer to fail on the next put
      dagSyncer.failNextPut = true;

      // Add a payload (this should throw)
      final set = GSet<String>();
      set.add('a');

      expect(() => crdt.add(set), throwsException);
    });

    test('Handles DAGSyncer.get failure gracefully', () async {
      // Create a shared broadcaster to allow communication between CRDTs
      final sharedBroadcaster = MockBroadcaster();

      // Create a custom DAGSyncer that can be programmed to throw exceptions
      final customDagSyncer = FlakyDAGSyncer<GSet<String>>();

      // Create a CRDT with the custom DAGSyncer
      final customCrdt1 = MerkleCRDT<GSet<String>>(
        dagSyncer: customDagSyncer,
        broadcaster: sharedBroadcaster,
      );

      // Create a second CRDT with the same DAGSyncer and broadcaster
      final customCrdt2 = MerkleCRDT<GSet<String>>(
        dagSyncer: customDagSyncer,
        broadcaster: sharedBroadcaster,
      );

      // Add an initial payload to customCrdt1. customCrdt2 receives and processes it successfully.
      final initialSet = GSet<String>();
      initialSet.add('initial_item');
      await customCrdt1.add(initialSet);
      // Ensure customCrdt2 has a chance to process this broadcast (e.g., update its clock).
      // With MockBroadcaster, stream events are typically handled as microtasks.
      await Future.delayed(Duration.zero);

      // Set up the DAGSyncer to fail on the next get
      customDagSyncer.failNextGet = true;

      // Now, customCrdt1 adds a *new* item.
      // This item's CID will be broadcast to customCrdt2.
      // customCrdt2 will know about this new CID.
      final failingSet = GSet<String>();
      failingSet.add('failing_item');
      await customCrdt1.add(failingSet);
      // Ensure customCrdt2 has a chance to process this new broadcast (e.g., update its clock with the new CID).
      // This delay ensures that _handleBroadcast in customCrdt2, if scheduled as a microtask, completes
      // at least to the point of recognizing the new CID before getState() is called.
      await Future.delayed(Duration.zero);

      // When customCrdt2.getState() is called, it should attempt to fetch 'failing_item'
      // because it knows its CID from the broadcast but doesn't have its content (assuming deferred fetching).
      // This fetch attempt will use customDagSyncer.get(), which is now set to fail.

      // Allow time for broadcast processing and the async error within _handleBroadcast to occur.
      // The original test had a delay here, suggesting MerkleCRDT might need it.
      await Future.delayed(Duration(milliseconds: 100));

      // Check the state of customCrdt2.
      // If MerkleCRDT retries 'dagSyncer.get()' after an initial failure,
      // the first 'get' will throw (setting getAttemptedAndThrew = true, failNextGet = false),
      // and a subsequent 'get' (the retry) will succeed because failNextGet is now false.
      // In this case, getState() should return the fully merged data.
      final state = await customCrdt2.getState();
      expect(
        state?.elements, 
        equals({'initial_item', 'failing_item'}),
        reason: "getState should return the complete state if MerkleCRDT successfully retries after an initial 'get' failure."
      );

      // Additionally, verify that the FlakyDAGSyncer's 'get' method was called in a way that triggered its failure logic initially.
      expect(
        customDagSyncer.getAttemptedAndThrew, 
        isTrue, 
        reason: "FlakyDAGSyncer should have initially attempted a 'get' operation that triggered its programmed failure."
      );

      // Note: The unhandled async error "Exception: Simulated network failure during get"
      // from the first failed 'get' attempt (if not caught by MerkleCRDT's stream listener)
      // might still be reported by the test runner. This test now focuses on the final state
      // and the fact that the syncer's failure path was triggered at least once.
    });

    test('Handles Broadcaster.broadcast failure gracefully', () async {
      // Set up the Broadcaster to fail on the next broadcast
      broadcaster.failNextBroadcast = true;

      // Add a payload (this should throw)
      final set = GSet<String>();
      set.add('a');

      expect(() => crdt.add(set), throwsException);
    });

    test('Recovers after temporary network failures', () async {
      // Set up the DAGSyncer to fail on the next put
      dagSyncer.failNextPut = true;

      // Add a payload (this should throw)
      final set1 = GSet<String>();
      set1.add('a');

      expect(() => crdt.add(set1), throwsException);

      // Try again (this should succeed)
      final set2 = GSet<String>();
      set2.add('b');
      await crdt.add(set2);

      // Verify state
      final state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, equals({'b'}));
    });
  });

  group('MerkleCRDT with Network Latency', () {
    late FlakyDAGSyncer<GSet<String>> dagSyncer;
    late FlakyBroadcaster broadcaster;
    late MerkleCRDT<GSet<String>> crdt1;
    late MerkleCRDT<GSet<String>> crdt2;

    setUp(() {
      dagSyncer = FlakyDAGSyncer<GSet<String>>();
      broadcaster = FlakyBroadcaster();
      crdt1 = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
      crdt2 = MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('CRDTs converge despite network latency', () async {
      // Set up network delays
      dagSyncer.getDelay = 50;
      dagSyncer.putDelay = 50;
      broadcaster.broadcastDelay = 50;

      // Add data to both CRDTs
      final set1 = GSet<String>();
      set1.add('a');
      await crdt1.add(set1);

      final set2 = GSet<String>();
      set2.add('b');
      await crdt2.add(set2);

      // Wait for broadcasts to be processed (with extra time for delays)
      await Future.delayed(Duration(milliseconds: 300));

      // Verify both CRDTs have converged
      final state1 = await crdt1.getState();
      final state2 = await crdt2.getState();

      expect(state1!.elements, containsAll(['a', 'b']));
      expect(state2!.elements, containsAll(['a', 'b']));
    });
  });

  group('MerkleCRDT Concurrent Updates', () {
    late MockDAGSyncer<GSet<String>> dagSyncer;
    late MockBroadcaster broadcaster;
    late List<MerkleCRDT<GSet<String>>> crdts;

    setUp(() {
      dagSyncer = MockDAGSyncer<GSet<String>>();
      broadcaster = MockBroadcaster();

      // Create 10 CRDTs
      crdts = List.generate(10, (_) => MerkleCRDT<GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      ));
    });

    test('Multiple concurrent updates converge', () async {
      // Add different data to each CRDT concurrently
      final futures = <Future<void>>[];

      for (var i = 0; i < crdts.length; i++) {
        final set = GSet<String>();
        set.add('value$i');
        futures.add(crdts[i].add(set));
      }

      // Wait for all updates to complete
      await Future.wait(futures);

      // Wait for broadcasts to be processed
      await Future.delayed(Duration(milliseconds: 200));

      // Verify all CRDTs have converged to the same state
      final states = await Future.wait(crdts.map((crdt) => crdt.getState()));

      // All states should be non-null
      for (final state in states) {
        expect(state, isNotNull);
      }

      // All states should contain all values
      for (final state in states) {
        for (var i = 0; i < crdts.length; i++) {
          expect(state!.elements, contains('value$i'));
        }
      }
    });
  });
}
