/// A Dart implementation of Merkle-CRDTs.
///
/// Merkle-CRDTs combine Merkle-DAGs with Conflict-Free Replicated Data Types (CRDTs)
/// to create distributed systems with strong eventual consistency.
library merkledag;

// Core components
export 'src/merkle_node.dart';
export 'src/dag_syncer.dart';
export 'src/broadcaster.dart';
export 'src/crdt_payload.dart';
export 'src/merkle_clock.dart';
export 'src/merkle_crdt.dart';

// CRDT payloads
export 'src/g_set.dart';

// Mock components for testing
export 'src/mock/mock_dag_syncer.dart';
export 'src/mock/mock_broadcaster.dart';
