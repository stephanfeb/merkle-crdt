# Merkle-CRDT Developer Guide

This guide provides a comprehensive overview of how to use the Merkle-CRDT library, explaining the core components, their relationships, and practical usage patterns.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Component Architecture](#component-architecture)
3. [Key Components Explained](#key-components-explained)
4. [MerkleNode vs MerkleCRDT: Understanding the Relationship](#merklenode-vs-merklecrdt-understanding-the-relationship)
5. [Getting Started](#getting-started)
6. [Advanced Usage](#advanced-usage)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Core Concepts

### What are Merkle-CRDTs?

Merkle-CRDTs combine two powerful concepts:

- **Merkle-DAGs**: Content-addressed, immutable data structures where each node is identified by the hash of its content
- **CRDTs**: Conflict-Free Replicated Data Types that guarantee eventual consistency across distributed replicas

This combination provides:
- **Strong eventual consistency** without requiring consensus
- **Content addressing** for efficient synchronization and deduplication
- **Self-verification** through cryptographic hashing
- **Transport agnostic** operation (works with any networking layer)

### Key Benefits

1. **No Coordination Required**: Replicas can operate independently and still converge
2. **Network Partition Tolerance**: System continues to work during network splits
3. **Efficient Synchronization**: Only missing data needs to be transferred
4. **Tamper Detection**: Content addressing makes data corruption detectable
5. **Flexible Replica Sets**: Nodes can join/leave without coordination

## Component Architecture

The library follows a layered architecture:

```
┌─────────────────────────────────────────────────────────┐
│                   Application Layer                     │
│                   (Your CRDT Logic)                     │
├─────────────────────────────────────────────────────────┤
│                   MerkleCRDT Layer                      │
│              (CRDT + Merkle-DAG Logic)                  │
├─────────────────────────────────────────────────────────┤
│                 AbstractMerkleDAG                       │
│              (Common DAG Operations)                    │
├─────────────────────────────────────────────────────────┤
│    MerkleNode    │    DAGSyncer    │   Broadcaster      │
│  (Data Storage)  │   (Transport)   │  (Communication)   │
└─────────────────────────────────────────────────────────┘
```

## Key Components Explained

### 1. MerkleNode<T>

**Purpose**: The fundamental building block that stores data in the Merkle-DAG.

**What it is**:
- A container that holds your data (payload) along with links to child nodes
- Immutable once created
- Identified by a Content Identifier (CID) derived from its content

**Structure**:
```dart
class MerkleNode<T> {
  final CID cid;           // Unique identifier (hash of content)
  final T payload;         // Your actual data
  final Set<CID> children; // Links to child nodes
}
```

**Key characteristics**:
- **Immutable**: Once created, cannot be modified
- **Content-addressed**: CID is deterministically generated from payload + children
- **Self-verifying**: CID mismatch indicates data corruption
- **Serializable**: Can be stored and transmitted

**When to use directly**:
- Rarely used directly in application code
- Mainly used internally by MerkleCRDT
- Useful for low-level DAG operations or custom implementations

### 2. AbstractMerkleDAG<T>

**Purpose**: Base class providing common DAG management functionality.

**What it provides**:
- Root tracking (current "heads" of the DAG)
- Node caching with LRU eviction
- DAG traversal methods
- Thread-safe operations
- Common merge logic

**Key methods**:
```dart
Future<MerkleNode<T>?> getNode(CID cid)     // Fetch node by CID
Future<bool> isIncluded(CID cid)            // Check if CID is in DAG
Future<bool> isDescendantOf(CID desc, CID ancestor) // Check ancestry
Set<CID> get roots                          // Get current root CIDs
```

**When to use**:
- Base class for MerkleCRDT and MerkleClock
- Not used directly in application code

### 3. MerkleCRDT<V, P>

**Purpose**: The main class you'll interact with - implements CRDT semantics on top of Merkle-DAGs.

**Generic parameters**:
- `V`: The logical value type (e.g., `Set<String>` for a set of strings)
- `P`: The CRDT payload type that implements `CRDTPayload<V>` (e.g., `GSet<String>`)

**What it does**:
- Manages CRDT state using Merkle-DAG structure
- Handles automatic merging of concurrent updates
- Provides eventual consistency guarantees
- Manages communication with other replicas

**Key methods**:
```dart
Future<CID> add(P payload)        // Add new CRDT operation/state
Future<P?> getState()             // Get current merged state
Set<CID> get roots                // Get current root CIDs (inherited)
```

**When to use**:
- This is your main entry point for CRDT operations
- Use when you need distributed, eventually consistent data structures

### 4. CRDTPayload<T>

**Purpose**: Interface that your data types must implement to work with MerkleCRDT.

**Required methods**:
```dart
abstract class CRDTPayload<T> {
  T get value;                                    // Logical value
  CRDTPayload<T> merge(CRDTPayload<T> other);    // Merge with another payload
  Uint8List toCanonicalBytes();                  // Deterministic serialization
}
```

**When to implement**:
- When creating custom CRDT types
- The library provides `GSet<T>` as an example implementation

### 5. DAGSyncer<T>

**Purpose**: Interface for storing and retrieving MerkleNodes (transport abstraction).

**Methods**:
```dart
abstract class DAGSyncer<T> {
  Future<MerkleNode<T>?> get(CID cid);    // Retrieve node by CID
  Future<void> put(MerkleNode<T> node);   // Store node
}
```

**Implementations**:
- In-memory storage for testing
- IPFS integration for production
- Database backends
- Network protocols (HTTP, gRPC, etc.)

### 6. Broadcaster

**Purpose**: Interface for announcing updates to other replicas.

**Methods**:
```dart
abstract class Broadcaster {
  Future<void> broadcast(String cidString);  // Announce new root CID
  Stream<String> subscribe();                // Listen for announcements
}
```

**Implementations**:
- PubSub systems (Redis, NATS, etc.)
- WebSocket connections
- IPFS PubSub
- Message queues

## MerkleNode vs MerkleCRDT: Understanding the Relationship

This is a crucial distinction that often confuses developers:

### MerkleNode: The Storage Container

**Think of MerkleNode as a "box" that holds your data:**

```dart
// A MerkleNode is like a container
MerkleNode<GSet<String>> node = MerkleNode.create(
  myGSet,           // Your CRDT data goes inside
  parentCIDs        // Links to previous versions
);

// The node has:
// - A unique ID (CID) based on its contents
// - Your data (the GSet)
// - Links to parent nodes
```

**Characteristics**:
- **Low-level**: Raw storage mechanism
- **Immutable**: Never changes once created
- **Content-addressed**: ID derived from contents
- **No CRDT logic**: Just stores data + links

### MerkleCRDT: The Smart Manager

**Think of MerkleCRDT as a "smart manager" that uses MerkleNodes:**

```dart
// MerkleCRDT manages a collection of MerkleNodes
MerkleCRDT<Set<String>, GSet<String>> crdt = MerkleCRDT(
  dagSyncer: myDAGSyncer,
  broadcaster: myBroadcaster,
);

// The CRDT:
// - Creates MerkleNodes internally
// - Manages the DAG structure
// - Handles merging logic
// - Communicates with other replicas
```

**Characteristics**:
- **High-level**: Application interface
- **Stateful**: Tracks current state across multiple nodes
- **CRDT logic**: Handles merging, consistency, conflicts
- **Network-aware**: Communicates with other replicas

### The Relationship

```
MerkleCRDT                    MerkleNode
    │                             │
    ├─ Manages multiple ──────────┤
    ├─ Creates new ───────────────┤
    ├─ Merges data from ──────────┤
    └─ Tracks roots of ───────────┘
```

**In practice**:

1. **You interact with MerkleCRDT** - it's your main API
2. **MerkleCRDT creates MerkleNodes** - internally, when you add data
3. **MerkleNodes store your data** - immutably, with cryptographic IDs
4. **MerkleCRDT manages the DAG** - tracking which nodes are current

### Practical Example

```dart
// You work with MerkleCRDT
final crdt = MerkleCRDT<Set<String>, GSet<String>>(...);

// When you add data:
final mySet = GSet<String>()..add('apple');
final cid = await crdt.add(mySet);

// Internally, MerkleCRDT:
// 1. Creates a MerkleNode containing your GSet
// 2. Stores it via DAGSyncer
// 3. Updates its internal root tracking
// 4. Broadcasts the new CID

// You get the current state:
final currentState = await crdt.getState();
// MerkleCRDT merges all current root nodes to give you the result
```

**Key takeaway**: You rarely work with MerkleNode directly. MerkleCRDT is your main interface, and it manages MerkleNodes behind the scenes.

## Getting Started

### 1. Basic Setup

```dart
import 'package:merkledag/merkledag.dart';

// Create transport components (mock for testing)
final dagSyncer = MockDAGSyncer<GSet<String>>();
final broadcaster = MockBroadcaster();

// Create your CRDT
final crdt = MerkleCRDT<Set<String>, GSet<String>>(
  dagSyncer: dagSyncer,
  broadcaster: broadcaster,
);
```

### 2. Adding Data

```dart
// Create a CRDT payload
final mySet = GSet<String>();
mySet.add('apple');
mySet.add('banana');

// Add to the CRDT
final cid = await crdt.add(mySet);
print('Added data with CID: $cid');
```

### 3. Reading Current State

```dart
final currentState = await crdt.getState();
if (currentState != null) {
  print('Current elements: ${currentState.elements}');
}
```

### 4. Handling Remote Updates

```dart
// The CRDT automatically handles remote updates via the broadcaster
// You can optionally be notified:
final crdt = MerkleCRDT<Set<String>, GSet<String>>(
  dagSyncer: dagSyncer,
  broadcaster: broadcaster,
  onRemoteUpdateProcessed: () {
    print('Remote update processed!');
  },
);
```

## Advanced Usage

### Creating Custom CRDT Payloads

```dart
class Counter implements CRDTPayload<int> {
  final int _value;
  
  Counter(this._value);
  
  @override
  int get value => _value;
  
  @override
  Counter merge(CRDTPayload<int> other) {
    // Last-writer-wins or max value
    return Counter(math.max(value, other.value));
  }
  
  @override
  Uint8List toCanonicalBytes() {
    return utf8.encode(_value.toString());
  }
  
  // Implement == and hashCode for proper equality
}
```

### Implementing Real Network Components

```dart
class IPFSDAGSyncer<T> implements DAGSyncer<T> {
  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    // Fetch from IPFS network
    final response = await ipfs.dag.get(cid);
    return deserializeNode(response);
  }
  
  @override
  Future<void> put(MerkleNode<T> node) async {
    // Store to IPFS
    await ipfs.dag.put(serializeNode(node));
  }
}

class PubSubBroadcaster implements Broadcaster {
  @override
  Future<void> broadcast(String cidString) async {
    await pubsub.publish('merkle-crdt-updates', cidString);
  }
  
  @override
  Stream<String> subscribe() {
    return pubsub.subscribe('merkle-crdt-updates');
  }
}
```

### Working with Multiple Replicas

```dart
// Replica 1
final crdt1 = MerkleCRDT<Set<String>, GSet<String>>(
  dagSyncer: dagSyncer,
  broadcaster: broadcaster,
);

// Replica 2 (shares same transport)
final crdt2 = MerkleCRDT<Set<String>, GSet<String>>(
  dagSyncer: dagSyncer,
  broadcaster: broadcaster,
);

// Add data to replica 1
await crdt1.add(GSet<String>()..add('apple'));

// Add data to replica 2
await crdt2.add(GSet<String>()..add('banana'));

// Wait for synchronization
await Future.delayed(Duration(milliseconds: 100));

// Both replicas should have converged
final state1 = await crdt1.getState();
final state2 = await crdt2.getState();

assert(state1?.elements.containsAll(['apple', 'banana']) == true);
assert(state2?.elements.containsAll(['apple', 'banana']) == true);
```

## Best Practices

### 1. Choose Appropriate CRDT Types

- **GSet**: For grow-only collections
- **Counter**: For increment-only values
- **LWWRegister**: For last-writer-wins values
- **ORSet**: For sets that support removal

### 2. Batch Operations When Possible

```dart
// Instead of multiple small operations:
await crdt.add(GSet<String>()..add('item1'));
await crdt.add(GSet<String>()..add('item2'));

// Batch them:
final batch = GSet<String>();
batch.add('item1');
batch.add('item2');
await crdt.add(batch);
```

### 3. Handle Network Failures Gracefully

```dart
try {
  await crdt.add(myPayload);
} catch (e) {
  // Handle network errors
  print('Failed to add payload: $e');
  // The operation will be retried when network recovers
}
```

### 4. Monitor DAG Growth

```dart
// Check number of roots (should typically be 1)
print('Current roots: ${crdt.roots.length}');

// Multiple roots indicate concurrent updates that haven't been merged yet
if (crdt.roots.length > 1) {
  print('Concurrent updates detected');
}
```

### 5. Configure Caching Appropriately

```dart
final crdt = MerkleCRDT<Set<String>, GSet<String>>(
  dagSyncer: dagSyncer,
  broadcaster: broadcaster,
  maxCacheSize: 10000, // Adjust based on memory constraints
);
```

## Troubleshooting

### Common Issues

#### 1. "State is null"
```dart
final state = await crdt.getState();
if (state == null) {
  // No data has been added yet
  print('CRDT is empty');
}
```

#### 2. "Multiple roots detected"
```dart
if (crdt.roots.length > 1) {
  // Concurrent updates - this is normal
  // The next add() operation will merge them
  await crdt.add(GSet<String>()); // Empty payload to trigger merge
}
```

#### 3. "CID not found"
```dart
// Ensure your DAGSyncer can retrieve all referenced nodes
// Check network connectivity and storage availability
```

#### 4. "Broadcast not received"
```dart
// Verify broadcaster implementation
// Check network connectivity between replicas
// Ensure all replicas subscribe to the same channel/topic
```

### Debugging Tips

#### 1. Enable Logging
```dart
import 'package:logging/logging.dart';

Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) {
  print('${record.level.name}: ${record.time}: ${record.message}');
});
```

#### 2. Inspect DAG Structure
```dart
print('Current roots: ${crdt.roots}');
print('Root count: ${crdt.roots.length}');

// Check if specific CID is included
final isIncluded = await crdt.isIncluded(someCID);
print('CID $someCID is included: $isIncluded');
```

#### 3. Monitor Network Activity
```dart
// Log DAGSyncer operations
class LoggingDAGSyncer<T> implements DAGSyncer<T> {
  final DAGSyncer<T> _delegate;
  
  LoggingDAGSyncer(this._delegate);
  
  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    print('DAGSyncer.get($cid)');
    final result = await _delegate.get(cid);
    print('DAGSyncer.get($cid) -> ${result != null ? 'found' : 'not found'}');
    return result;
  }
  
  @override
  Future<void> put(MerkleNode<T> node) async {
    print('DAGSyncer.put(${node.cid})');
    await _delegate.put(node);
    print('DAGSyncer.put(${node.cid}) -> done');
  }
}
```

### Performance Considerations

1. **Cache Size**: Larger caches reduce network requests but use more memory
2. **Batch Size**: Larger batches reduce DAG growth but increase latency
3. **Network Latency**: High latency networks benefit from larger batch sizes
4. **Storage Backend**: Choose appropriate DAGSyncer implementation for your use case

## Conclusion

The Merkle-CRDT library provides a powerful foundation for building distributed, eventually consistent applications. By understanding the relationship between MerkleNodes (storage containers) and MerkleCRDTs (smart managers), you can effectively leverage this library to build robust distributed systems.

Remember:
- **MerkleCRDT is your main API** - use it for all CRDT operations
- **MerkleNodes are managed internally** - you rarely interact with them directly
- **Transport components are pluggable** - choose implementations that fit your infrastructure
- **CRDTs guarantee eventual consistency** - design your application logic accordingly

For more examples and advanced patterns, see the `example/` directory and test files in the repository.
