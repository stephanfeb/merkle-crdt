import 'package:dcid/dcid.dart';
import 'package:merkledag/merkledag.dart';
import 'package:test/test.dart';
import 'dart:async';

import 'mock/mock_broadcaster.dart';
import 'mock/mock_dag_syncer.dart';

void main() {
  // Helper to create a CID from a string content for testing
  CID cidFromContent(String content) => MerkleNode.create(content, <CID>{}).cid;

  group('MockDAGSyncer Tests', () {
    late MockDAGSyncer<String> dagSyncer;

    setUp(() {
      dagSyncer = MockDAGSyncer<String>();
    });

    test('Get returns null for non-existent CID', () async {
      final cid = cidFromContent('non-existent'); // Generate a valid CID
      final node = await dagSyncer.get(cid);
      expect(node, isNull);
    });

    test('Put stores node and get retrieves it', () async {
      final cid = cidFromContent('test-cid-content'); // CID from content
      final node = MerkleNode<String>( // Construct node with this CID
        cid: cid, 
        payload: 'test-payload',
        children: {},
      );

      await dagSyncer.put(node);
      final retrievedNode = await dagSyncer.get(cid);

      expect(retrievedNode, isNotNull);
      expect(retrievedNode!.cid, equals(cid)); // Compare the CID objects
      expect(retrievedNode.payload, equals('test-payload'));
      expect(retrievedNode.children, isEmpty);
    });

    test('Put overwrites existing node with same CID', () async {
      final cid = cidFromContent('test-cid-content'); // Use the same content to get the same CID
      final node1 = MerkleNode<String>(
        cid: cid,
        payload: 'payload1',
        children: {},
      );
      final node2 = MerkleNode<String>(
        cid: cid, // Same CID
        payload: 'payload2',
        children: {},
      );

      await dagSyncer.put(node1);
      await dagSyncer.put(node2);
      final retrievedNode = await dagSyncer.get(cid);

      expect(retrievedNode, isNotNull);
      expect(retrievedNode!.payload, equals('payload2'));
    });
  });

  group('MockBroadcaster Tests', () {
    late MockBroadcaster broadcaster;

    setUp(() {
      broadcaster = MockBroadcaster();
    });

    test('Subscribe returns a stream', () {
      final stream = broadcaster.subscribe();
      expect(stream, isA<Stream>());
    });

    test('Broadcast sends data to all subscribers', () async {
      // Create a completer to wait for the broadcast
      final completer1 = Completer<dynamic>();
      final completer2 = Completer<dynamic>();

      // Subscribe to the broadcaster
      broadcaster.subscribe().listen((data) {
        completer1.complete(data);
      });
      broadcaster.subscribe().listen((data) {
        completer2.complete(data);
      });

      // Broadcast some data
      await broadcaster.broadcast('test-data');

      // Wait for the data to be received
      final data1 = await completer1.future;
      final data2 = await completer2.future;

      // Verify the data
      expect(data1, equals('test-data'));
      expect(data2, equals('test-data'));
    });

    test('Multiple broadcasts are received in order', () async {
      // Create a list to store received data
      final receivedData = <String>[];

      // Subscribe to the broadcaster
      broadcaster.subscribe().listen((data) {
        receivedData.add(data as String);
      });

      // Broadcast multiple messages
      await broadcaster.broadcast('message1');
      await broadcaster.broadcast('message2');
      await broadcaster.broadcast('message3');

      // Wait for all messages to be processed
      await Future.delayed(Duration(milliseconds: 100));

      // Verify the messages were received in order
      expect(receivedData, equals(['message1', 'message2', 'message3']));
    });

    test('Late subscribers receive only new broadcasts', () async {
      // Broadcast a message before subscribing
      await broadcaster.broadcast('message1');

      // Create a list to store received data
      final receivedData = <String>[];

      // Subscribe after the first broadcast
      broadcaster.subscribe().listen((data) {
        receivedData.add(data as String);
      });

      // Broadcast more messages
      await broadcaster.broadcast('message2');
      await broadcaster.broadcast('message3');

      // Wait for all messages to be processed
      await Future.delayed(Duration(milliseconds: 100));

      // Verify only the messages after subscribing were received
      expect(receivedData, equals(['message2', 'message3']));
    });
  });
}
