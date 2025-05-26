import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';
import 'dart:async';

// A custom CRDT payload for testing
class Counter implements CRDTPayload<int> {
  final int _value; // Changed to private

  Counter(this._value);

  @override
  int get value => _value; // Implemented getter

  Counter increment() {
    return Counter(_value + 1);
  }

  @override
  Counter merge(CRDTPayload<int> other) { // Changed other type
    // Assuming other.value is int. For robust code, consider type check if other could be different CRDTPayload<int>
    return Counter(value > other.value ? value : other.value);
  }

  @override
  String toString() => _value.toString(); // For debugging

  @override
  Uint8List toCanonicalBytes() { // Implemented
    return utf8.encode(_value.toString());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Counter &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

// A custom DAGSyncer that can simulate network failures
// P is the CRDT payload type (e.g. GSet<String> or Counter)
class FlakyDAGSyncer<P> implements DAGSyncer<P> {
  final Map<String, MerkleNode<P>> _nodes = {};
  bool failNextGet = false;
  bool failNextPut = false;
  int getDelay = 0;
  int putDelay = 0;
  bool getAttemptedAndThrew = false;

  @override
  Future<MerkleNode<P>?> get(CID cid) async {
    if (failNextGet) {
      failNextGet = false;
      getAttemptedAndThrew = true;
      throw Exception('Simulated network failure during get');
    }
    if (getDelay > 0) {
      await Future.delayed(Duration(milliseconds: getDelay));
    }
    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<P> node) async {
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
  final List<StreamController<String>> _controllers = [];
  bool failNextBroadcast = false;
  int broadcastDelay = 0;

  @override
  Future<void> broadcast(String cidString) async {
    if (failNextBroadcast) {
      failNextBroadcast = false;
      throw Exception('Simulated network failure during broadcast');
    }
    if (broadcastDelay > 0) {
      await Future.delayed(Duration(milliseconds: broadcastDelay));
    }
    for (final controller in _controllers) {
      if (!controller.isClosed) controller.add(cidString);
    }
  }

  @override
  Stream<String> subscribe() {
    final controller = StreamController<String>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }

  void closeAll() {
    for (final controller in _controllers) {
      controller.close();
    }
    _controllers.clear();
  }
}

void main() {
  group('MerkleCRDT Extended Tests with GSet', () {
    // P is GSet<String>, V is Set<String>
    late MockDAGSyncer<GSet<String>> dagSyncer;
    late MockBroadcaster broadcaster;
    late MerkleCRDT<Set<String>, GSet<String>> crdt;

    setUp(() {
      dagSyncer = MockDAGSyncer<GSet<String>>();
      broadcaster = MockBroadcaster();
      crdt = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('Initial state is null', () async {
      final state = await crdt.getState();
      expect(state, isNull);
    });

    test('Adding multiple payloads updates state correctly', () async {
      final set1 = GSet<String>();
      set1.add('a');
      await crdt.add(set1);
      var state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.elements, equals({'a'}));

      final set2 = GSet<String>();
      set2.add('b');
      await crdt.add(set2); // This will merge with current state 'a' then add 'b'
      state = await crdt.getState();
      expect(state, isNotNull);
      // The GSet merge logic means the payload of the new node will be {'a', 'b'}
      // So getState() which merges roots (in this case, one root) will yield {'a', 'b'}
      expect(state!.elements, equals({'a', 'b'}));
    });

    test('Multiple CRDTs converge after broadcasts', () async {
      final crdt1 = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: dagSyncer, broadcaster: broadcaster);
      final crdt2 = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: dagSyncer, broadcaster: broadcaster);
      final crdt3 = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: dagSyncer, broadcaster: broadcaster);

      final set1 = GSet<String>();
      set1.add('a');
      await crdt1.add(set1);
      await Future.delayed(Duration(milliseconds: 100));

      final set2 = GSet<String>();
      set2.add('b');
      await crdt2.add(set2);
      await Future.delayed(Duration(milliseconds: 100));

      final set3 = GSet<String>();
      set3.add('c');
      await crdt3.add(set3);
      await Future.delayed(Duration(milliseconds: 500));

      final state1 = await crdt1.getState();
      final state2 = await crdt2.getState();
      final state3 = await crdt3.getState();

      print('State 1: ${state1?.elements}');
      print('State 2: ${state2?.elements}');
      print('State 3: ${state3?.elements}');

      expect(state1?.elements, containsAll(['a', 'b', 'c']));
      expect(state2?.elements, containsAll(['a', 'b', 'c']));
      expect(state3?.elements, containsAll(['a', 'b', 'c']));
    });
  });

  group('MerkleCRDT with Custom CRDT Payload (Counter)', () {
    // P is Counter, V is int
    late MockDAGSyncer<Counter> dagSyncer;
    late MockBroadcaster broadcaster;
    late MerkleCRDT<int, Counter> crdt;

    setUp(() {
      dagSyncer = MockDAGSyncer<Counter>();
      broadcaster = MockBroadcaster();
      crdt = MerkleCRDT<int, Counter>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('Counter CRDT works correctly', () async {
      await crdt.add(Counter(5));
      var state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.value, equals(5));

      await crdt.add(Counter(10));
      state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.value, equals(10));

      await crdt.add(Counter(3));
      state = await crdt.getState();
      expect(state, isNotNull);
      expect(state!.value, equals(10));
    });

    test('Multiple Counter CRDTs converge to max value', () async {
      final crdt1 = MerkleCRDT<int, Counter>(
        dagSyncer: dagSyncer, broadcaster: broadcaster);
      final crdt2 = MerkleCRDT<int, Counter>(
        dagSyncer: dagSyncer, broadcaster: broadcaster);

      await crdt1.add(Counter(5));
      await crdt2.add(Counter(10));
      await Future.delayed(Duration(milliseconds: 100));

      final state1 = await crdt1.getState();
      final state2 = await crdt2.getState();

      expect(state1?.value, equals(10));
      expect(state2?.value, equals(10));
    });
  });

  group('MerkleCRDT with Network Failures (GSet)', () {
    // P is GSet<String>, V is Set<String>
    late FlakyDAGSyncer<GSet<String>> dagSyncer;
    late FlakyBroadcaster flakyBroadcaster; // Use FlakyBroadcaster instance
    late MerkleCRDT<Set<String>, GSet<String>> crdt;

    setUp(() {
      dagSyncer = FlakyDAGSyncer<GSet<String>>();
      flakyBroadcaster = FlakyBroadcaster(); // Instantiate FlakyBroadcaster
      crdt = MerkleCRDT<Set<String>, GSet<String>>(
        dagSyncer: dagSyncer,
        broadcaster: flakyBroadcaster, // Use the instance
      );
    });
    
    tearDown(() {
      flakyBroadcaster.closeAll(); // Clean up stream controllers
    });

    test('Handles DAGSyncer.put failure gracefully', () async {
      dagSyncer.failNextPut = true;
      final set = GSet<String>();
      set.add('a');
      expect(() => crdt.add(set), throwsException);
    });

    test('Handles DAGSyncer.get failure gracefully', () async {
      final sharedBroadcaster = FlakyBroadcaster(); // Use FlakyBroadcaster for test control
      final customDagSyncer = FlakyDAGSyncer<GSet<String>>();

      final customCrdt1 = MerkleCRDT<Set<String>, GSet<String>>(
          dagSyncer: customDagSyncer, broadcaster: sharedBroadcaster);
      final customCrdt2 = MerkleCRDT<Set<String>, GSet<String>>(
          dagSyncer: customDagSyncer, broadcaster: sharedBroadcaster);

      final initialSet = GSet<String>()..add('initial_item');
      await customCrdt1.add(initialSet);
      await Future.delayed(Duration.zero); // Allow broadcast to be processed

      customDagSyncer.failNextGet = true;
      final failingSet = GSet<String>()..add('failing_item');
      // This add will broadcast. crdt2's _handleBroadcast will try to _merge, then getNode, which uses dagSyncer.get
      await customCrdt1.add(failingSet);
      
      // Allow time for broadcast and potential error handling within _handleBroadcast
      // The error from dagSyncer.get is caught in MerkleCRDT._handleBroadcast
      // so getState should not throw but might reflect a state before the failing node.
      // However, if MerkleCRDT is robust, it might eventually get the node if retries were implemented (not currently).
      // Given current implementation, the node from failingSet might not be part of state2.
      await Future.delayed(Duration(milliseconds: 100)); 

      final state2 = await customCrdt2.getState();
      
      // If the get for 'failing_item' node fails, it won't be part of state2's merged roots.
      // So state2 should only contain 'initial_item'.
      expect(state2?.elements, equals({'initial_item'}),
        reason: "If get fails for a node, it shouldn't be part of the merged state.");
      
      expect(customDagSyncer.getAttemptedAndThrew, isTrue,
        reason: "FlakyDAGSyncer should have attempted a 'get' that failed.");
      
      sharedBroadcaster.closeAll();
    });

    test('Handles Broadcaster.broadcast failure gracefully', () async {
      flakyBroadcaster.failNextBroadcast = true; // Use the instance variable
      final set = GSet<String>();
      set.add('a');
      expect(() => crdt.add(set), throwsException);
    });

    test('Recovers after temporary network failures (put)', () async {
      dagSyncer.failNextPut = true;
      final set1 = GSet<String>()..add('a');
      expect(() => crdt.add(set1), throwsException);

      dagSyncer.failNextPut = false; // Network recovered
      final set2 = GSet<String>()..add('b');
      await crdt.add(set2);
      final state = await crdt.getState();
      expect(state?.elements, equals({'b'}));
    });
  });

  group('MerkleCRDT with Network Latency (GSet)', () {
    late FlakyDAGSyncer<GSet<String>> dagSyncer;
    late FlakyBroadcaster flakyBroadcaster;
    late MerkleCRDT<Set<String>, GSet<String>> crdt1;
    late MerkleCRDT<Set<String>, GSet<String>> crdt2;

    setUp(() {
      dagSyncer = FlakyDAGSyncer<GSet<String>>();
      flakyBroadcaster = FlakyBroadcaster();
      crdt1 = MerkleCRDT<Set<String>, GSet<String>>(
          dagSyncer: dagSyncer, broadcaster: flakyBroadcaster);
      crdt2 = MerkleCRDT<Set<String>, GSet<String>>(
          dagSyncer: dagSyncer, broadcaster: flakyBroadcaster);
    });
    
    tearDown(() {
      flakyBroadcaster.closeAll();
    });

    test('CRDTs converge despite network latency', () async {
      dagSyncer.getDelay = 50;
      dagSyncer.putDelay = 50;
      flakyBroadcaster.broadcastDelay = 50;

      final set1 = GSet<String>()..add('a');
      await crdt1.add(set1);

      final set2 = GSet<String>()..add('b');
      await crdt2.add(set2);

      await Future.delayed(Duration(milliseconds: 500)); // Increased delay

      final state1 = await crdt1.getState();
      final state2 = await crdt2.getState();

      expect(state1?.elements, containsAll(['a', 'b']));
      expect(state2?.elements, containsAll(['a', 'b']));
    });
  });

  group('MerkleCRDT Concurrent Updates (GSet)', () {
    late MockDAGSyncer<GSet<String>> dagSyncer;
    late MockBroadcaster broadcaster;
    late List<MerkleCRDT<Set<String>, GSet<String>>> crdts;

    setUp(() {
      dagSyncer = MockDAGSyncer<GSet<String>>();
      broadcaster = MockBroadcaster();
      crdts = List.generate(
          10,
          (_) => MerkleCRDT<Set<String>, GSet<String>>(
              dagSyncer: dagSyncer, broadcaster: broadcaster));
    });

    test('Multiple concurrent updates converge', () async {
      final futures = <Future<void>>[];
      for (var i = 0; i < crdts.length; i++) {
        final set = GSet<String>()..add('value$i');
        futures.add(crdts[i].add(set));
      }
      await Future.wait(futures);
      await Future.delayed(Duration(milliseconds: 500)); // Increased delay

      final states = await Future.wait(crdts.map((crdt) => crdt.getState()));
      for (final state in states) {
        expect(state, isNotNull);
        for (var i = 0; i < crdts.length; i++) {
          expect(state!.elements, contains('value$i'));
        }
      }
    });
  });
}
