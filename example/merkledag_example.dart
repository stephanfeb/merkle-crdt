import 'package:merkledag/merkledag.dart';

void main() async {
  // Create mock components for testing
  final dagSyncer = MockDAGSyncer<GSet<String>>();
  final broadcaster = MockBroadcaster();

  // Create a Merkle-CRDT
  final crdt = MerkleCRDT<GSet<String>>(
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
  print('State after adding set1: $stateAfterSet1');

  // Add more data by merging with the current state
  final currentState = await crdt.getState();
  if (currentState != null) {
    final set2 = currentState;
    set2.add('cherry');
    set2.add('date');
    await crdt.add(set2);
  }

  // Get the current state
  final state = await crdt.getState();
  print('Current state: $state');
  // Output: Current state: {apple, banana, cherry, date}

  // Create a second CRDT with the same components
  final crdt2 = MerkleCRDT<GSet<String>>(
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
  print('Updated state: $updatedState');
  // Output should include all fruits from both CRDTs

  // Demonstrate creating a custom CRDT payload
  await demonstrateCustomCRDT();
}

/// Demonstrates how to create and use a custom CRDT payload
Future<void> demonstrateCustomCRDT() async {
  print('\nDemonstrating custom CRDT payload:');

  // Create mock components for testing
  final dagSyncer = MockDAGSyncer<Counter>();
  final broadcaster = MockBroadcaster();

  // Create a Merkle-CRDT with the Counter payload
  final crdt = MerkleCRDT<Counter>(
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );

  // Add a counter with value 5
  await crdt.add(Counter(5));

  // Create a second CRDT with the same components
  final crdt2 = MerkleCRDT<Counter>(
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );

  // Add a counter with value 10
  await crdt2.add(Counter(10));

  // Wait for the broadcast to be processed
  await Future.delayed(Duration(milliseconds: 100));

  // Get the state of the first CRDT
  final state = await crdt.getState();
  print('Counter state: $state');
  // Output: Counter state: 10 (the max value)
}

/// A simple Counter CRDT that keeps the maximum value
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
