
# Handling a "Like" for a Post Deep in the Merkle-CRDT Hierarchy

When implementing a social media feed using Merkle-CRDT with primitives like Post, Like, and Actor, you need a strategy for handling events that enhance historical data - such as a "Like" on a post that's buried deep in the Merkle-CRDT hierarchy.

## The Challenge

The challenge arises because:

1. Merkle-CRDTs are immutable - once a node is created, it cannot be modified
2. The post being liked might be several levels deep in the DAG hierarchy
3. We need to maintain the relationship between the "Like" and the original post
4. All replicas need to converge to the same state

## Solution Approach

There are two main approaches to handle this scenario:

### 1. Reference-Based Approach (Recommended)

In this approach, each "Like" is a new CRDT operation that references the original post by its CID:

```dart
class SocialFeed implements CRDTPayload<SocialFeed> {
  // Maps post CIDs to Post objects
  final Map<String, Post> posts;
  
  // Maps post CIDs to sets of Like objects
  final Map<String, Set<Like>> likes;
  
  // Implementation of merge function
  @override
  SocialFeed merge(SocialFeed other) {
    // Merge posts
    final mergedPosts = Map<String, Post>.from(posts);
    for (final entry in other.posts.entries) {
      mergedPosts[entry.key] = entry.value;
    }
    
    // Merge likes (union of sets)
    final mergedLikes = Map<String, Set<Like>>.from(likes);
    for (final entry in other.likes.entries) {
      if (mergedLikes.containsKey(entry.key)) {
        mergedLikes[entry.key]!.addAll(entry.value);
      } else {
        mergedLikes[entry.key] = Set.from(entry.value);
      }
    }
    
    return SocialFeed(
      posts: mergedPosts,
      likes: mergedLikes,
    );
  }
}

class Like {
  final String actorId;
  final DateTime timestamp;
  
  Like(this.actorId, this.timestamp);
}
```

When a user likes a post:

1. Create a new `Like` object with the actor's ID and timestamp
2. Add it to the `likes` map using the post's CID as the key
3. Create a new Merkle-CRDT node with the updated `SocialFeed` payload
4. Broadcast this new node to all replicas

This approach:
- Maintains the immutability of the Merkle-CRDT
- Creates an explicit reference between the Like and the Post
- Allows efficient querying of all likes for a specific post
- Handles concurrent likes from different users correctly

### 2. Path-Based Approach

An alternative approach is to use a path-based system where each entity has a unique path:

```dart
class SocialEvent implements CRDTPayload<SocialEvent> {
  final Map<String, dynamic> events;
  
  // Add a new event at a specific path
  SocialEvent addEvent(String path, dynamic event) {
    final newEvents = Map<String, dynamic>.from(events);
    newEvents[path] = event;
    return SocialEvent(newEvents);
  }
  
  @override
  SocialEvent merge(SocialEvent other) {
    return SocialEvent({...events, ...other.events});
  }
}
```

With this approach:
- Posts might have paths like `posts/user123/post456`
- Likes would have paths like `likes/post456/user789`
- The path structure creates implicit relationships

## Implementation Example

Here's how you would implement the reference-based approach with the Merkle-CRDT library:

```dart
// Create a new like
Future<void> likePost(String postCid, String actorId) async {
  // Get current state
  final currentState = await crdt.getState() ?? SocialFeed();
  
  // Create a new like
  final like = Like(actorId, DateTime.now());
  
  // Add the like to the current state
  final newState = currentState.addLike(postCid, like);
  
  // Update the CRDT
  await crdt.add(newState);
}

// Get all likes for a post
Set<Like> getLikesForPost(SocialFeed feed, String postCid) {
  return feed.likes[postCid] ?? {};
}

// Check if a user has liked a post
bool hasUserLikedPost(SocialFeed feed, String postCid, String actorId) {
  final postLikes = feed.likes[postCid] ?? {};
  return postLikes.any((like) => like.actorId == actorId);
}
```

## Advantages of This Approach

1. **Efficiency**: No need to traverse the entire DAG to find the post or its likes
2. **Scalability**: Works well even with thousands of posts and likes
3. **Convergence**: All replicas will converge to the same state, even with concurrent likes
4. **Query Performance**: Fast lookup of all likes for a specific post

## Considerations

1. **Memory Usage**: The reference-based approach may use more memory as the social graph grows
2. **Garbage Collection**: You may need strategies to prune old posts and their associated likes
3. **Indexing**: For complex queries, you might need additional indexes in your data structure

By using this approach, you can efficiently handle "Likes" for posts that are deep in the Merkle-CRDT hierarchy while maintaining the convergence properties of CRDTs.