import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_cid/dart_cid.dart';
import 'package:merkledag/merkledag.dart'; // This should provide MockBroadcaster
import 'package:test/test.dart';
import 'dart:async';

import 'mock/mock_broadcaster.dart';


// A custom DAGSyncer that can simulate network failures
// P is the type of the CRDT payload object (e.g., TestPayload)
class FlakyDAGSyncer<P> implements DAGSyncer<P> {
  final Map<String, MerkleNode<P>> _nodes = {};
  bool failNextGet = false;
  bool failNextPut = false;

  @override
  Future<MerkleNode<P>?> get(CID cid) async {
    if (failNextGet) {
      failNextGet = false;
      throw Exception('Simulated network failure during get');
    }
    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<P> node) async {
    if (failNextPut) {
      failNextPut = false;
      throw Exception('Simulated network failure during put');
    }
    _nodes[node.cid.toString()] = node;
  }
}

// A custom DAGSyncer that can be programmed to return specific values or throw exceptions
// P is the type of the CRDT payload object (e.g., TestPayload)
class ProgrammableDAGSyncer<P> implements DAGSyncer<P> {
  final Map<String, MerkleNode<P>> _nodes = {};
  final List<Future<MerkleNode<P>?> Function(CID)> _getResponses = [];
  final List<Future<void> Function(MerkleNode<P>)> _putResponses = [];

  void addGetResponse(Future<MerkleNode<P>?> Function(CID) response) {
    _getResponses.add(response);
  }

  void addPutResponse(Future<void> Function(MerkleNode<P>) response) {
    _putResponses.add(response);
  }

  @override
  Future<MerkleNode<P>?> get(CID cid) async {
    if (_getResponses.isNotEmpty) {
      final response = _getResponses.removeAt(0);
      return response(cid);
    }
    return _nodes[cid.toString()];
  }

  @override
  Future<void> put(MerkleNode<P> node) async {
    if (_putResponses.isNotEmpty) {
      final response = _putResponses.removeAt(0);
      return response(node);
    }
    _nodes[node.cid.toString()] = node;
  }
}

// A simple CRDT payload for testing
// Implements CRDTPayload<String> where String is the logical value type (V)
class TestPayload implements CRDTPayload<String> {
  final String _value; // Internal value

  TestPayload(this._value);

  @override
  String get value => _value; // Getter for the logical value

  @override
  TestPayload merge(CRDTPayload<String> other) {
    // other.value is String.
    // For robust code, check: if (other is! TestPayload) throw ...
    return TestPayload('${_value},${other.value}');
  }

  @override
  String toString() => _value; // For debugging

  @override
  Uint8List toCanonicalBytes() {
    return utf8.encode(_value); // Canonical byte representation
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestPayload &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}

void main() {
  group('MerkleCRDT with ProgrammableDAGSyncer', () {
    late ProgrammableDAGSyncer<TestPayload> dagSyncer;
    late MockBroadcaster broadcaster; // Should be available from merkledag.dart
    late MerkleCRDT<String, TestPayload> crdt;

    setUp(() {
      dagSyncer = ProgrammableDAGSyncer<TestPayload>();
      broadcaster = MockBroadcaster(); // No try-catch, assuming it's defined and imported via merkledag.dart
      crdt = MerkleCRDT<String, TestPayload>(
        dagSyncer: dagSyncer,
        broadcaster: broadcaster,
      );
    });

    test('MerkleCRDT calls DAGSyncer.get when a broadcast is received', () async {
      final payload1 = TestPayload('test1');
      await crdt.add(payload1);

      final getCalls = <String>[];
      dagSyncer.addGetResponse((CID cid) async {
        getCalls.add(cid.toString());
        return MerkleNode<TestPayload>( // P is TestPayload
          cid: cid,
          payload: TestPayload('test-response'),
          children: {},
        );
      });
      
      // Simulate a remote CID being broadcast directly to crdt's broadcaster.
      final remotePayload = TestPayload('remoteData');
      // Simulate this payload existing on another CRDT and its CID being generated
      final remoteNodeSimulated = MerkleNode.create(remotePayload, <CID>{});
      final cid2 = remoteNodeSimulated.cid;

      // Broadcast the remote CID on the broadcaster instance crdt is listening to.
      await broadcaster.broadcast(cid2.toString());

      await Future.delayed(Duration(milliseconds: 100)); // Allow time for async broadcast processing
      expect(getCalls, contains(cid2.toString()));
    });

    test('add throws exception when DAGSyncer.put fails', () async {
      dagSyncer.addPutResponse((MerkleNode<TestPayload> node) async { // P is TestPayload
        throw Exception('Simulated network failure during put');
      });

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
