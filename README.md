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
  merkledag: ^1.0.0 # Ensure this version is current with your library version
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
  // P (payload type) is GSet<String>
  final dagSyncer = MockDAGSyncer<GSet<String>>();
  final broadcaster = MockBroadcaster();

  // Create a Merkle-CRDT
  // V (value type) is Set<String>, P (payload type) is GSet<String>
  final crdt = MerkleCRDT<Set<String>, GSet<String>>(
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
  print('Current state: ${state?.elements}'); // Access .elements for GSet
  // Output: Current state: {apple, banana, cherry, date}
}
```

### Creating Custom CRDT Payloads

You can create your own CRDT payloads by implementing the `CRDTPayload<V>` interface, where `V` is the logical value type.

```dart
import 'dart:convert'; // For utf8
import 'dart:typed_data'; // For Uint8List
import 'package:merkledag/merkledag.dart'; // For CRDTPayload

// Counter implements CRDTPayload<int>, where int is the logical value type V.
class Counter implements CRDTPayload<int> {
  final int _value; // Store the actual integer value

  Counter(this._value);

  // Getter for the logical value, required by CRDTPayload<int>
  @override
  int get value => _value;

  // Example method specific to Counter
  Counter increment() {
    return Counter(_value + 1);
  }

  // Merge with another CRDTPayload<int>.
  // It's common for the 'other' payload to be of the same concrete type (Counter).
  @override
  Counter merge(CRDTPayload<int> other) {
    // other.value gives the int value from the other payload.
    return Counter(value > other.value ? value : other.value);
  }

  // Required by CRDTPayload for canonical serialization
  @override
  Uint8List toCanonicalBytes() {
    // For a simple integer, its string representation encoded to UTF-8 can be canonical.
    return utf8.encode(_value.toString());
  }

  @override
  String toString() => _value.toString(); // For debugging

  // It's good practice to implement == and hashCode as well.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Counter && runtimeType == other.runtimeType && _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}
```

### Implementing Real Network Components

In a real application, you would implement the `DAGSyncer` and `Broadcaster` interfaces with actual networking code:

```dart
import 'package:merkledag/merkledag.dart'; // For CID, MerkleNode, DAGSyncer, Broadcaster

class NetworkDAGSyncer<P> implements DAGSyncer<P> { // P is the payload type
  @override
  Future<MerkleNode<P>?> get(CID cid) async {
    // Fetch the node from a network source
    // Example:
    // final response = await http.get(Uri.parse('https://my-network-source/nodes/${cid.toString()}'));
    // if (response.statusCode == 200) {
    //   // Deserialize response.body into a MerkleNode<P>
    //   // This requires a way to know the type P and how to deserialize its payload.
    //   // For simplicity, returning null.
    //   return null; 
    // }
    // return null;
    throw UnimplementedError('Get method not implemented in example');
  }

  @override
  Future<void> put(MerkleNode<P> node) async {
    // Make the node available on the network
    // Example:
    // final serializedNode = ... // Serialize node to bytes or JSON
    // await http.post(Uri.parse('https://my-network-source/nodes'), body: serializedNode);
    throw UnimplementedError('Put method not implemented in example');
  }
}

class NetworkBroadcaster implements Broadcaster {
  @override
  Future<void> broadcast(String cidString) async {
    // Broadcast the CID string to other replicas
    // Example:
    // await myWebSocketClient.send(cidString);
    // await myMessageQueueClient.publish('cids_topic', cidString);
    throw UnimplementedError('Broadcast method not implemented in example');
  }

  @override
  Stream<String> subscribe() {
    // Return a stream of CID strings from other replicas
    // Example: return myWebSocketClient.onMessage.where((msg) => isCidString(msg));
    // Example: return myMessageQueueClient.subscribe('cids_topic');
    throw UnimplementedError('Subscribe method not implemented in example');
  }
}
```

## Additional information

For more information about Merkle-CRDTs, see the following resources:

- [Merkle-CRDTs: Merkle-DAGs Meet CRDTs](https://arxiv.org/pdf/2004.00107) - The academic paper that describes the theory behind Merkle-CRDTs
- [IPFS](https://ipfs.io/) - A content-addressed, peer-to-peer file system that uses Merkle-DAGs
- [CRDTs](https://crdt.tech/) - A website with resources about Conflict-Free Replicated Data Types
