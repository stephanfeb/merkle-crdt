import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';
import 'dart:async';

// A custom DAGSyncer that can simulate network failures
class FlakyDAGSyncer<T> implements DAGSyncer<T> {
  final Map<String, MerkleNode<T>> _nodes = {};
  bool failNextGet = false;
  bool failNextPut = false;

  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    if (failNextGet) {
      failNextGet = false;
      throw Exception('Simulated network failure during get');
    }
    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    if (failNextPut) {
      failNextPut = false;
      throw Exception('Simulated network failure during put');
    }
    _nodes[node.cid.toString()] = node;
  }
}

// A custom DAGSyncer that can be programmed to return specific values or throw exceptions
class ProgrammableDAGSyncer<T> implements DAGSyncer<T> {
  final Map<String, MerkleNode<T>> _nodes = {};
  final List<Future<MerkleNode<T>?> Function(CID)> _getResponses = [];
  final List<Future<void> Function(MerkleNode<T>)> _putResponses = [];

  // Add a response for the next get call
  void addGetResponse(Future<MerkleNode<T>?> Function(CID) response) {
    _getResponses.add(response);
  }

  // Add a response for the next put call
  void addPutResponse(Future<void> Function(MerkleNode<T>) response) {
    _putResponses.add(response);
  }

  @override
  Future<MerkleNode<T>?> get(CID cid) async {
    if (_getResponses.isNotEmpty) {
      final response = _getResponses.removeAt(0);
      return response(cid);
    }
    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    if (_putResponses.isNotEmpty) {
      final response = _putResponses.removeAt(0);
      return response(node);
    }
    _nodes[node.cid.toString()] = node;
  }
}

// A simple CRDT payload for testing
class TestPayload implements CRDTPayload<TestPayload> {
  final String value;

  TestPayload(this.value);

  @override
  TestPayload merge(TestPayload other) {
    return TestPayload('${value},${other.value}');
  }

  @override
  String toString() => value;
}

void main() {
  group('MerkleCRDT with ProgrammableDAGSyncer', () {
    late ProgrammableDAGSyncer<TestPayload> dagSyncer;
    late MockBroadcaster broadcaster;
    late MerkleCRDT<TestPayload> crdt;

    setUp(() {
      dagSyncer = ProgrammableDAGSyncer<TestPayload>();
      broadcaster = MockBroadcaster();
      crdt = MerkleCRDT<TestPayload>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('MerkleCRDT calls DAGSyncer.get when a broadcast is received', () async {
      // First, add a payload to the CRDT
      final payload1 = TestPayload('test1');
      final cid1 = await crdt.add(payload1);

      // Create a list to track which CIDs are passed to DAGSyncer.get
      final getCalls = <String>[];

      // Program the DAGSyncer to record the CID and return a node
      dagSyncer.addGetResponse((CID cid) async {
        getCalls.add(cid.toString());
        return MerkleNode<TestPayload>(
          cid: cid,
          payload: TestPayload('test-response'),
          children: {},
        );
      });

      // Create a new broadcaster that we can control
      final testBroadcaster = MockBroadcaster();

      // Create a new CRDT with the same DAGSyncer but a different broadcaster
      final testCrdt = MerkleCRDT<TestPayload>(
        dagSyncer: dagSyncer,
        broadcaster: testBroadcaster,
      );

      // Add a payload to the test CRDT
      final payload2 = TestPayload('test2');
      final cid2 = await testCrdt.add(payload2);

      // Now broadcast the CID of the test CRDT's node to the original CRDT
      // This will cause the original CRDT to call _merge, which will call DAGSyncer.get
      await broadcaster.broadcast(cid2.toString());

      // Wait for the broadcast to be processed
      await Future.delayed(Duration(milliseconds: 100));

      // Verify that DAGSyncer.get was called with the correct CID
      expect(getCalls, contains(cid2.toString()));
    });

    test('add throws exception when DAGSyncer.put fails', () async {
      // Program the DAGSyncer to throw an exception on the next put
      dagSyncer.addPutResponse((MerkleNode<TestPayload> node) async {
        throw Exception('Simulated network failure during put');
      });

      // Try to add a payload (this should throw)
      try {
        await crdt.add(TestPayload('test'));
        fail('Expected an exception to be thrown');
      } catch (e) {
        expect(e, isA<Exception>());
        expect(e.toString(), contains('Simulated network failure during put'));
      }
    });
  });
}
