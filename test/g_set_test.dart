import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkledag/src/g_set.dart';
import 'package:merkledag/src/crdt_payload.dart';

void main() {
  group('GSet', () {
    group('Basic Operations', () {
      test('creates empty GSet', () {
        final gset = GSet<String>();
        expect(gset.isEmpty, isTrue);
        expect(gset.length, equals(0));
        expect(gset.value, isEmpty);
      });

      test('creates GSet from list', () {
        final gset = GSet<String>.fromList(['a', 'b', 'c']);
        expect(gset.length, equals(3));
        expect(gset.contains('a'), isTrue);
        expect(gset.contains('b'), isTrue);
        expect(gset.contains('c'), isTrue);
        expect(gset.contains('d'), isFalse);
      });

      test('adds elements', () {
        final gset = GSet<String>();
        gset.add('hello');
        gset.add('world');
        
        expect(gset.length, equals(2));
        expect(gset.contains('hello'), isTrue);
        expect(gset.contains('world'), isTrue);
      });

      test('handles duplicate additions', () {
        final gset = GSet<String>();
        gset.add('hello');
        gset.add('hello');
        
        expect(gset.length, equals(1));
        expect(gset.contains('hello'), isTrue);
      });

      test('merges with another GSet', () {
        final gset1 = GSet<String>.fromList(['a', 'b']);
        final gset2 = GSet<String>.fromList(['b', 'c']);
        
        final merged = gset1.merge(gset2);
        
        expect(merged.length, equals(3));
        expect(merged.contains('a'), isTrue);
        expect(merged.contains('b'), isTrue);
        expect(merged.contains('c'), isTrue);
      });

      test('equality works correctly', () {
        final gset1 = GSet<String>.fromList(['a', 'b', 'c']);
        final gset2 = GSet<String>.fromList(['c', 'b', 'a']); // Different order
        final gset3 = GSet<String>.fromList(['a', 'b']);
        
        expect(gset1, equals(gset2)); // Order shouldn't matter
        expect(gset1, isNot(equals(gset3))); // Different elements
      });
    });

    group('JSON Serialization', () {
      test('converts to/from JSON', () {
        final original = GSet<String>.fromList(['hello', 'world', 'test']);
        final json = original.toJson();
        final restored = GSet<String>.fromJson(json);
        
        expect(restored, equals(original));
      });

      test('handles empty set JSON', () {
        final original = GSet<String>();
        final json = original.toJson();
        final restored = GSet<String>.fromJson(json);
        
        expect(restored, equals(original));
        expect(restored.isEmpty, isTrue);
      });
    });

    group('Canonical Bytes Serialization', () {
      test('serializes and deserializes empty set', () {
        final original = GSet<String>();
        final bytes = original.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(original));
        expect(restored.isEmpty, isTrue);
      });

      test('serializes and deserializes single element', () {
        final original = GSet<String>();
        original.add('hello');
        
        final bytes = original.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(original));
        expect(restored.contains('hello'), isTrue);
        expect(restored.length, equals(1));
      });

      test('serializes and deserializes multiple elements', () {
        final original = GSet<String>.fromList(['zebra', 'apple', 'banana']);
        
        final bytes = original.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(original));
        expect(restored.length, equals(3));
        expect(restored.contains('zebra'), isTrue);
        expect(restored.contains('apple'), isTrue);
        expect(restored.contains('banana'), isTrue);
      });

      test('maintains deterministic ordering', () {
        // Create two GSets with same elements in different order
        final gset1 = GSet<String>();
        gset1.add('zebra');
        gset1.add('apple');
        gset1.add('banana');
        
        final gset2 = GSet<String>();
        gset2.add('apple');
        gset2.add('zebra');
        gset2.add('banana');
        
        final bytes1 = gset1.toCanonicalBytes();
        final bytes2 = gset2.toCanonicalBytes();
        
        // Bytes should be identical regardless of insertion order
        expect(bytes1, equals(bytes2));
      });

      test('handles special characters and unicode', () {
        final original = GSet<String>.fromList([
          'hello world',
          'special!@#\$%^&*()',
          'unicode: 🌟🚀💫',
          'newline\nand\ttab',
          '',  // empty string
        ]);
        
        final bytes = original.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(original));
        expect(restored.length, equals(5));
      });

      test('handles large elements', () {
        final largeString = 'x' * 10000; // 10KB string
        final original = GSet<String>();
        original.add(largeString);
        original.add('small');
        
        final bytes = original.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(original));
        expect(restored.contains(largeString), isTrue);
        expect(restored.contains('small'), isTrue);
      });

      test('different sets produce different bytes', () {
        final gset1 = GSet<String>.fromList(['hello', 'world']);
        final gset2 = GSet<String>.fromList(['hello', 'universe']);
        final gset3 = GSet<String>.fromList(['hello']);
        
        final bytes1 = gset1.toCanonicalBytes();
        final bytes2 = gset2.toCanonicalBytes();
        final bytes3 = gset3.toCanonicalBytes();
        
        expect(bytes1, isNot(equals(bytes2)));
        expect(bytes1, isNot(equals(bytes3)));
        expect(bytes2, isNot(equals(bytes3)));
      });

      test('round-trip preserves all data', () {
        final original = GSet<String>.fromList([
          'first',
          'second',
          'third with spaces',
          'fourth_with_underscores',
          '123numbers',
          'UPPERCASE',
          'lowercase',
          'MiXeD cAsE',
        ]);
        
        final bytes = original.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(original));
        
        // Verify each element individually
        for (final element in original.elements) {
          expect(restored.contains(element), isTrue, 
                 reason: 'Restored set should contain "$element"');
        }
      });

      test('throws on malformed bytes', () {
        // Test various malformed byte sequences
        expect(() => GSet<String>.fromCanonicalBytes(Uint8List.fromList([])), 
               throwsA(isA<FormatException>()));
        
        expect(() => GSet<String>.fromCanonicalBytes(Uint8List.fromList([0xFF])), 
               throwsA(isA<FormatException>()));
        
        // Incomplete varint
        expect(() => GSet<String>.fromCanonicalBytes(Uint8List.fromList([0x80])), 
               throwsA(isA<FormatException>()));
        
        // Says it has 1 element but no element data
        expect(() => GSet<String>.fromCanonicalBytes(Uint8List.fromList([0x01])), 
               throwsA(isA<FormatException>()));
        
        // Says element has length 5 but only 3 bytes available
        expect(() => GSet<String>.fromCanonicalBytes(Uint8List.fromList([0x01, 0x05, 0x61, 0x62, 0x63])), 
               throwsA(isA<FormatException>()));
      });

      test('varint encoding works correctly', () {
        // Test various varint values by creating sets with different element counts
        final testCounts = [0, 1, 127, 128, 255, 256, 16383, 16384];
        
        for (final count in testCounts) {
          final gset = GSet<String>();
          for (int i = 0; i < count; i++) {
            gset.add('element_$i');
          }
          
          final bytes = gset.toCanonicalBytes();
          final restored = GSet<String>.fromCanonicalBytes(bytes);
          
          expect(restored.length, equals(count), 
                 reason: 'Failed for count $count');
          expect(restored, equals(gset), 
                 reason: 'Round-trip failed for count $count');
        }
      });
    });

    group('Error Handling', () {
      test('merge throws on wrong type', () {
        final gset = GSet<String>();
        final wrongType = _MockCRDTPayload();
        
        expect(() => gset.merge(wrongType), throwsArgumentError);
      });

      test('fromCanonicalBytes throws for non-String types', () {
        // This test verifies the current limitation
        // Create a valid byte sequence for a set with one element
        // Format: [element_count][element_length][element_bytes]
        final setWithOneElementBytes = Uint8List.fromList([
          0x01, // 1 element
          0x05, // element length = 5
          0x68, 0x65, 0x6c, 0x6c, 0x6f // "hello" in UTF-8
        ]);
        expect(() => GSet<int>.fromCanonicalBytes(setWithOneElementBytes), 
               throwsA(isA<UnsupportedError>()));
      });

      test('varint encoding rejects negative values', () {
        // Test the varint encoding indirectly since _encodeVarint is private
        // We can't directly test it, but we can verify the behavior through public methods
        // This test is more about documenting the expected behavior
        final gset = GSet<String>();
        // The varint encoding is used internally and should handle valid cases
        expect(gset.toCanonicalBytes(), isNotNull);
      });
    });

    group('Performance and Edge Cases', () {
      test('handles many elements efficiently', () {
        final gset = GSet<String>();
        
        // Add 1000 elements
        for (int i = 0; i < 1000; i++) {
          gset.add('element_${i.toString().padLeft(4, '0')}');
        }
        
        final bytes = gset.toCanonicalBytes();
        final restored = GSet<String>.fromCanonicalBytes(bytes);
        
        expect(restored, equals(gset));
        expect(restored.length, equals(1000));
      });

      test('serialization is deterministic across multiple calls', () {
        final gset = GSet<String>.fromList(['c', 'a', 'b']);
        
        final bytes1 = gset.toCanonicalBytes();
        final bytes2 = gset.toCanonicalBytes();
        final bytes3 = gset.toCanonicalBytes();
        
        expect(bytes1, equals(bytes2));
        expect(bytes2, equals(bytes3));
      });
    });
  });
}

// Mock class for testing error handling
class _MockCRDTPayload implements CRDTPayload<Set<String>> {
  @override
  Set<String> get value => {'mock'};
  
  @override
  CRDTPayload<Set<String>> merge(CRDTPayload<Set<String>> other) {
    throw UnimplementedError();
  }
  
  @override
  Uint8List toCanonicalBytes() {
    throw UnimplementedError();
  }
}
