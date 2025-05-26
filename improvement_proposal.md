# Merkle-CRDT Implementation Improvement Proposal

This document outlines recommended improvements for the Merkle-CRDT library based on a code review.

## Checklist of Recommended Improvements

### High Priority / High Impact

-   [ ] **Canonical Node Serialization for CID Generation:**
    -   [ ] Modify `MerkleNode._createContentString` to sort children CIDs by their string values before incorporation.
    -   [ ] Modify `MerkleNode._createContentString` to use a canonical serialization method for the `payload` (not `payload.toString()`).
    -   [ ] Add a method for canonical serialization (e.g., `Object toJsonEncodable()` or `String toCanonicalString()`) to the `CRDTPayload<T>` interface.
    -   [ ] Document that `CRDTPayload.toString()` should be for debugging only.
    -   [ ] Update `GSet` (and any other `CRDTPayload` implementers) to correctly implement the new canonical serialization method (e.g., `GSet` should sort its elements before serializing).

-   [ ] **Refactor Common DAG Logic:**
    -   [ ] Design and implement a base class (e.g., `AbstractMerkleDAG<T>`) to encapsulate common DAG management logic (`_roots`, `_nodeCache`, traversal methods, root merge logic) shared between `MerkleCRDT` and `MerkleClock`.
    -   [ ] Refactor `MerkleCRDT` to extend this new base class.
    -   [ ] Refactor `MerkleClock` to extend this new base class.

-   [ ] **Robust Error Handling:**
    -   [ ] In `MerkleCRDT`, add an `onError` handler to the `broadcaster.subscribe().listen()` call in the constructor to manage errors from `_handleBroadcast` (e.g., log, retry, update CRDT state).
    -   [ ] Document clear error handling contracts in `DAGSyncer` and `Broadcaster` interfaces (e.g., define specific exception types or error reporting mechanisms).

### Medium Priority

-   [ ] **Concurrency Control:**
    -   [ ] Review `MerkleCRDT.add`, `MerkleCRDT._merge`, `MerkleClock.addNode`, and `MerkleClock.merge` for race conditions related to `_roots` and `_nodeCache`.
    -   [ ] Implement locking (e.g., using `Lock` from `package:async`) for critical sections in these methods to ensure atomic updates.

-   [ ] **Correctness of DAG Traversal (`_isDescendant`):**
    -   [ ] Modify the `_isDescendant` method (in `MerkleCRDT`, `MerkleClock`, or the new base class) to fetch nodes from `dagSyncer` if not found in `_nodeCache`, or rename to clarify cache-only behavior and update call sites.

-   [ ] **Node Cache Management:**
    -   [ ] Evaluate the need for a cache eviction policy (e.g., LRU, size-based) for `_nodeCache` in `MerkleCRDT` and `MerkleClock` (or the base class).
    -   [ ] If needed, implement an appropriate cache eviction strategy.

### Low-Medium Priority / Clarity

-   [ ] **Type Safety in `Broadcaster`:**
    -   [ ] Consider using more specific types instead of `dynamic` for data in the `Broadcaster.broadcast()` method and `subscribe()` stream if the data type is fixed (e.g., `String` for CIDs).

-   [ ] **Documentation for `MerkleCRDT.getState()`:**
    -   [ ] Add documentation to `MerkleCRDT.getState()` clarifying that it merges only root node payloads and the underlying assumptions about state-based `CRDTPayload` types.
