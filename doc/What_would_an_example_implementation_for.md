
# Multi-Writer Chat Room Implementation Using Merkle-CRDT

Here's an example implementation for a multi-writer chat room that uses Merkle-CRDT to replicate the state of the chat log with support for nested replies.

## Data Model

First, let's define our chat message data structure:

```dart
class ChatMessage {
  final String id;          // Unique message ID
  final String author;      // Author of the message
  final String content;     // Content of the message
  final DateTime timestamp; // When the message was created
  final String? parentId;   // ID of the parent message (null for top-level messages)
  
  ChatMessage({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
    this.parentId,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'parentId': parentId,
  };
  
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'],
    author: json['author'],
    content: json['content'],
    timestamp: DateTime.parse(json['timestamp']),
    parentId: json['parentId'],
  );
}
```

## CRDT Payload Implementation

Now, let's implement a CRDT payload that can handle the chat room state:

```dart
class ChatRoom implements CRDTPayload<ChatRoom> {
  // Using a map to store messages by their ID for efficient lookup
  final Map<String, ChatMessage> messages;
  
  ChatRoom([Map<String, ChatMessage>? messages]) 
      : messages = messages ?? {};
  
  // Add a new message to the chat room
  ChatRoom addMessage(ChatMessage message) {
    final newMessages = Map<String, ChatMessage>.from(messages);
    newMessages[message.id] = message;
    return ChatRoom(newMessages);
  }
  
  // Get all top-level messages (messages without a parent)
  List<ChatMessage> get topLevelMessages => 
      messages.values.where((msg) => msg.parentId == null).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  
  // Get replies to a specific message
  List<ChatMessage> getReplies(String messageId) =>
      messages.values.where((msg) => msg.parentId == messageId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  
  // Implement the merge function required by CRDTPayload
  @override
  ChatRoom merge(ChatRoom other) {
    // Merge the two sets of messages
    final mergedMessages = Map<String, ChatMessage>.from(messages);
    
    // Add all messages from the other chat room
    for (final entry in other.messages.entries) {
      // If we already have this message, keep it (idempotent)
      // If we don't have it, add it
      if (!mergedMessages.containsKey(entry.key)) {
        mergedMessages[entry.key] = entry.value;
      }
    }
    
    return ChatRoom(mergedMessages);
  }
  
  // Helper method to convert to JSON for serialization
  Map<String, dynamic> toJson() => {
    'messages': messages.map((k, v) => MapEntry(k, v.toJson())),
  };
  
  // Helper method to create from JSON for deserialization
  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final messagesJson = json['messages'] as Map<String, dynamic>;
    final messages = messagesJson.map(
      (k, v) => MapEntry(k, ChatMessage.fromJson(v as Map<String, dynamic>))
    );
    return ChatRoom(messages);
  }
}
```

## Chat Room Application Implementation

Now, let's implement the chat room application using the Merkle-CRDT:

```dart
class ChatRoomApp {
  final String username;
  final MerkleCRDT<ChatRoom> crdt;
  
  ChatRoomApp({
    required this.username,
    required DAGSyncer<ChatRoom> dagSyncer,
    required Broadcaster broadcaster,
  }) : crdt = MerkleCRDT<ChatRoom>(
         dagSyncer: dagSyncer,
         broadcaster: broadcaster,
       );
  
  // Send a new top-level message
  Future<void> sendMessage(String content) async {
    final message = ChatMessage(
      id: _generateUniqueId(),
      author: username,
      content: content,
      timestamp: DateTime.now(),
    );
    
    // Get current state or create a new one
    final currentState = await crdt.getState() ?? ChatRoom();
    
    // Add the new message
    final newState = currentState.addMessage(message);
    
    // Update the CRDT
    await crdt.add(newState);
  }
  
  // Send a reply to an existing message
  Future<void> sendReply(String parentMessageId, String content) async {
    final message = ChatMessage(
      id: _generateUniqueId(),
      author: username,
      content: content,
      timestamp: DateTime.now(),
      parentId: parentMessageId,
    );
    
    // Get current state or create a new one
    final currentState = await crdt.getState() ?? ChatRoom();
    
    // Add the new message
    final newState = currentState.addMessage(message);
    
    // Update the CRDT
    await crdt.add(newState);
  }
  
  // Get all messages in the chat room
  Future<ChatRoom> getChatRoom() async {
    return await crdt.getState() ?? ChatRoom();
  }
  
  // Helper method to generate a unique ID
  String _generateUniqueId() {
    return '${username}_${DateTime.now().millisecondsSinceEpoch}_${_randomString(8)}';
  }
  
  // Helper method to generate a random string
  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length, 
        (_) => chars.codeUnitAt(random.nextInt(chars.length))
      )
    );
  }
}
```

## Network Implementation

For a real-world application, we need to implement the `DAGSyncer` and `Broadcaster` interfaces:

```dart
class ChatDAGSyncer implements DAGSyncer<ChatRoom> {
  final String serverUrl;
  final Map<String, MerkleNode<ChatRoom>> _localCache = {};
  
  ChatDAGSyncer(this.serverUrl);
  
  @override
  Future<MerkleNode<ChatRoom>?> get(CID cid) async {
    // First check local cache
    if (_localCache.containsKey(cid.value)) {
      return _localCache[cid.value];
    }
    
    // If not in cache, fetch from server
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/nodes/${cid.value}'),
      );
      
      if (response.statusCode == 200) {
        final nodeData = jsonDecode(response.body);
        final node = _deserializeNode(nodeData);
        _localCache[cid.value] = node;
        return node;
      }
    } catch (e) {
      print('Error fetching node: $e');
    }
    
    return null;
  }
  
  @override
  Future<void> put(MerkleNode<ChatRoom> node) async {
    // Store in local cache
    _localCache[node.cid.value] = node;
    
    // Send to server
    try {
      await http.post(
        Uri.parse('$serverUrl/nodes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_serializeNode(node)),
      );
    } catch (e) {
      print('Error storing node: $e');
    }
  }
  
  // Helper methods for serialization/deserialization
  Map<String, dynamic> _serializeNode(MerkleNode<ChatRoom> node) {
    return {
      'cid': node.cid.value,
      'payload': node.payload.toJson(),
      'children': node.children.map((cid) => cid.value).toList(),
    };
  }
  
  MerkleNode<ChatRoom> _deserializeNode(Map<String, dynamic> data) {
    final payload = ChatRoom.fromJson(data['payload']);
    final children = (data['children'] as List)
        .map((cidValue) => CID(cidValue as String))
        .toSet();
    
    return MerkleNode<ChatRoom>(
      CID(data['cid']),
      payload,
      children,
    );
  }
}

class ChatBroadcaster implements Broadcaster {
  final String serverUrl;
  final String roomId;
  final StreamController<dynamic> _controller = StreamController.broadcast();
  WebSocketChannel? _channel;
  
  ChatBroadcaster(this.serverUrl, this.roomId) {
    _connect();
  }
  
  void _connect() {
    _channel = WebSocketChannel.connect(
      Uri.parse('$serverUrl/ws/rooms/$roomId'),
    );
    
    _channel!.stream.listen(
      (data) {
        _controller.add(jsonDecode(data));
      },
      onError: (error) {
        print('WebSocket error: $error');
        // Reconnect after a delay
        Future.delayed(Duration(seconds: 5), _connect);
      },
      onDone: () {
        print('WebSocket connection closed');
        // Reconnect after a delay
        Future.delayed(Duration(seconds: 5), _connect);
      },
    );
  }
  
  @override
  Future<void> broadcast(dynamic data) async {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }
  
  @override
  Stream<dynamic> subscribe() {
    return _controller.stream;
  }
  
  void dispose() {
    _channel?.sink.close();
    _controller.close();
  }
}
```

## Usage Example

Here's how you would use this implementation:

```dart
void main() async {
  final username = 'alice';
  final serverUrl = 'https://chat-server.example.com';
  final roomId = 'general';
  
  // Create the DAGSyncer and Broadcaster
  final dagSyncer = ChatDAGSyncer(serverUrl);
  final broadcaster = ChatBroadcaster(serverUrl, roomId);
  
  // Create the chat room app
  final chatApp = ChatRoomApp(
    username: username,
    dagSyncer: dagSyncer,
    broadcaster: broadcaster,
  );
  
  // Send a message
  await chatApp.sendMessage('Hello, world!');
  
  // Get the chat room state
  final chatRoom = await chatApp.getChatRoom();
  final messages = chatRoom.topLevelMessages;
  
  // Print all messages
  for (final message in messages) {
    print('${message.author}: ${message.content}');
    
    // Print replies
    final replies = chatRoom.getReplies(message.id);
    for (final reply in replies) {
      print('  └─ ${reply.author}: ${reply.content}');
      
      // Print nested replies (you can make this recursive for deeper nesting)
      final nestedReplies = chatRoom.getReplies(reply.id);
      for (final nestedReply in nestedReplies) {
        print('     └─ ${nestedReply.author}: ${nestedReply.content}');
      }
    }
  }
  
  // Clean up
  broadcaster.dispose();
}
```

## Key Features of This Implementation

1. **Conflict-Free Merging**: The `merge` method in `ChatRoom` ensures that all messages are preserved when merging chat states from different replicas.

2. **Nested Replies**: The `parentId` field in `ChatMessage` allows for creating a tree structure of messages and replies.

3. **Efficient Lookups**: Using a map to store messages by ID allows for O(1) lookups when retrieving replies.

4. **Persistence**: The `ChatDAGSyncer` implementation can be extended to use a local database for persistent storage.

5. **Real-time Updates**: The `ChatBroadcaster` implementation uses WebSockets to provide real-time updates to all connected clients.

6. **Eventual Consistency**: The Merkle-CRDT ensures that all replicas eventually converge to the same state, even with network partitions or offline operation.

This implementation provides a solid foundation for a distributed, multi-writer chat application with support for nested replies, leveraging the Merkle-CRDT library for state replication and consistency.