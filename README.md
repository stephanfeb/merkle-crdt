# Merkle-CRDT

A Dart implementation of Merkle-CRDTs, which combine Merkle-DAGs with Conflict-Free Replicated Data Types (CRDTs) to create distributed systems with strong eventual consistency.

## Overview

Merkle-CRDTs are a powerful approach to building distributed systems that can maintain consistency even in challenging network conditions with partitions, high latency, or intermittent connectivity. They combine the content-addressing and self-verification properties of Merkle-DAGs with the strong eventual consistency of CRDTs.

This library provides a complete implementation of Merkle-CRDTs as described in the academic paper ["Merkle-CRDTs: Merkle-DAGs Meet CRDTs"](https://arxiv.org/pdf/2004.00107).

## Features

- **Content-addressed data**: All nodes are identified by the hash of their content
- **Tamper-resistant**: Any change in content changes the hash, making modifications detectable
- **Strong eventual consistency**: All replicas that have seen the same updates will converge to the same state
- **Transport-agnostic**: Works with weak messaging layer guarantees
- **Flexible replica set**: Replicas can join and leave at will without coordination
- **Self-verification**: Content addressing ensures data integrity
- **Efficient synchronization**: Only missing parts of the DAG need to be fetched

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  merkledag: ^1.0.0
```

Then run:

```
dart pub get
```

## Usage

### Basic Usage

```dart
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

  // Add more data
  final set2 = GSet<String>();
  set2.add('cherry');
  set2.add('date');
  await crdt.add(set2);

  // Get the current state
  final state = await crdt.getState();
  print('Current state: $state');
  // Output: Current state: {apple, banana, cherry, date}
}
```

### Creating Custom CRDT Payloads

You can create your own CRDT payloads by implementing the `CRDTPayload` interface:

```dart
class Counter implements CRDTPayload<Counter> {
  final int value;

  Counter(this.value);

  void increment() {
    return Counter(value + 1);
  }

  @override
  Counter merge(Counter other) {
    return Counter(value > other.value ? value : other.value);
  }

  @override
  String toString() => value.toString();
}
```

### Implementing Real Network Components

In a real application, you would implement the `DAGSyncer` and `Broadcaster` interfaces with actual networking code:

```dart
class NetworkDAGSyncer<T> implements DAGSyncer<T> {
  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    // Fetch the node from a network source
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    // Make the node available on the network
  }
}

class NetworkBroadcaster implements Broadcaster {
  @override
  Future<void> broadcast(dynamic data) async {
    // Broadcast the data to other replicas
  }

  @override
  Stream<dynamic> subscribe() {
    // Return a stream of broadcasts from other replicas
  }
}
```

## Additional information

For more information about Merkle-CRDTs, see the following resources:

- [Merkle-CRDTs: Merkle-DAGs Meet CRDTs](https://arxiv.org/pdf/2004.00107) - The academic paper that describes the theory behind Merkle-CRDTs
- [IPFS](https://ipfs.io/) - A content-addressed, peer-to-peer file system that uses Merkle-DAGs
- [CRDTs](https://crdt.tech/) - A website with resources about Conflict-Free Replicated Data Types
