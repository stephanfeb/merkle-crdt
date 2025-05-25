import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';
import 'dart:async';

// A custom DAGSyncer that can simulate network failures
class FlakyDAGSyncer<T> implements DAGSyncer<T> {
  final Map<String, MerkleNode<T>> _nodes = {};
  bool failNextGet = false;
  bool failNextPut = false;

  @override
  Future<MerkleNode<T>?> get(MerkleDagCID cid) async {
    if (failNextGet) {
      failNextGet = false;
      throw Exception('Simulated network failure during get');
    }
    return _nodes[cid.value];
  }

  @override
  Future<void> put(MerkleNode<T> node) async {
    if (failNextPut) {
      failNextPut = false;
      throw Exception('Simulated network failure during put');
    }
    _nodes[node.cid.value] = node;
  }
}

void main() {
  group('FlakyDAGSyncer Tests', () {
    late FlakyDAGSyncer<String> dagSyncer;

    setUp(() {
      dagSyncer = FlakyDAGSyncer<String>();
    });

    test('Get throws exception when failNextGet is true', () async {
      // Set up the DAGSyncer to fail on the next get
      dagSyncer.failNextGet = true;
      
      // Try to get a node (this should throw)
      await expectLater(dagSyncer.get(MerkleDagCID('test')), throwsException);
    });

    test('Put throws exception when failNextPut is true', () async {
      // Set up the DAGSyncer to fail on the next put
      dagSyncer.failNextPut = true;
      
      // Try to put a node (this should throw)
      final node = MerkleNode<String>(
        cid: MerkleDagCID('test'),
        payload: 'test',
        children: {},
      );
      
      await expectLater(dagSyncer.put(node), throwsException);
    });
  });
}