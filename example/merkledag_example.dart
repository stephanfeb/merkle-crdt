import 'dart:convert'; // Added
import 'dart:typed_data'; // Added
import 'package:merkledag/merkledag.dart';

void main() async {
  // Create mock components for testing
  // P is GSet<String>
  final dagSyncer = MockDAGSyncer<GSet<String>>();
  final broadcaster = MockBroadcaster();

  // Create a Merkle-CRDT
  // V is Set<String>, P is GSet<String>
  final crdt = MerkleCRDT<Set<String>, GSet<String>>(
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );

  // Add some data
  final set1 = GSet<String>();
  set1.add('apple');
  set1.add('banana');
  await crdt.add(set1);

  // Get the state after adding the first set
  final stateAfterSet1 = await crdt.getState();
  print('State after adding set1: ${stateAfterSet1?.elements}'); // Access .elements

  // Add more data by merging with the current state
  final currentState = await crdt.getState();
  if (currentState != null) {
    // currentState is a GSet. To add to it for the *next* crdt.add operation,
    // we typically create a new GSet or modify a copy if GSet was mutable (it's not deeply mutable here).
    // The way GSet.merge works, it's better to create a new GSet representing the desired new state.
    // However, the original example implies modifying the current GSet instance and re-adding it.
    // Let's clarify: crdt.add(payload) where payload is the *new total state* or a *delta* depends on
    // how payload.merge(existingState) is designed.
    // Given MerkleCRDT.add merges `payload` with `currentState.merge(payload)`,
    // if `payload` is intended to be a delta, then `currentState.merge(payload)` should produce the new total state.
    // If `payload` is the new total state, then `currentState.merge(payload)` should still correctly merge.
    // The original code `final set2 = currentState; set2.add('cherry');` means `set2` IS `currentState`.
    // When `crdt.add(set2)` is called, `set2` (which is `currentState` now containing 'cherry', 'date')
    // will be merged with the result of `(await crdt.getState()).merge(set2)`.
    // This is a bit convoluted. A cleaner way to add 'cherry' and 'date' to the existing state:
    final GSet<String> set2 = GSet<String>();
    set2.add('cherry');
    set2.add('date');
    // `crdt.add` will internally merge `set2` with the current state of `crdt`.
    await crdt.add(set2);
  }

  // Get the current state
  final state = await crdt.getState();
  print('Current state: ${state?.elements}');
  // Output: Current state: {apple, banana, cherry, date}

  // Create a second CRDT with the same components
  // V is Set<String>, P is GSet<String>
  final crdt2 = MerkleCRDT<Set<String>, GSet<String>>(
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );

  // Add different data to the second CRDT
  final set3 = GSet<String>();
  set3.add('elderberry');
  set3.add('fig');
  await crdt2.add(set3);

  // Wait for the broadcast to be processed
  await Future.delayed(Duration(milliseconds: 100));

  // Get the state of the first CRDT
  final updatedState = await crdt.getState();
  print('Updated state: ${updatedState?.elements}');
  // Output should include all fruits from both CRDTs

  // Demonstrate creating a custom CRDT payload
  await demonstrateCustomCRDT();
}

/// Demonstrates how to create and use a custom CRDT payload
Future<void> demonstrateCustomCRDT() async {
  print('\nDemonstrating custom CRDT payload:');

  // Create mock components for testing
  // P is Counter
  final dagSyncer = MockDAGSyncer<Counter>();
  final broadcaster = MockBroadcaster();

  // Create a Merkle-CRDT with the Counter payload
  // V is int, P is Counter
  final crdt = MerkleCRDT<int, Counter>(
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );

  // Add a counter with value 5
  await crdt.add(Counter(5));

  // Create a second CRDT with the same components
  // V is int, P is Counter
  final crdt2 = MerkleCRDT<int, Counter>(
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );

  // Add a counter with value 10
  await crdt2.add(Counter(10));

  // Wait for the broadcast to be processed
  await Future.delayed(Duration(milliseconds: 100));

  // Get the state of the first CRDT
  final state = await crdt.getState();
  print('Counter state: ${state?.value}'); // Access .value
  // Output: Counter state: 10 (the max value)
}

/// A simple Counter CRDT that keeps the maximum value
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
    // Assuming other.value is int.
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
