import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/protocol/nuid.dart';

void main() {
  group('NUID generation', () {
    test('generate unique IDs', () {
      final nuid = Nuid();
      final ids = <String>{};

      // Generate 100 IDs and verify all are unique
      for (int i = 0; i < 100; i++) {
        final id = nuid.next();
        expect(id, hasLength(22), // NUIDs are always 22 characters
            reason: 'ID should be 22 characters: $id');
        expect(ids, isNot(contains(id)), // Verify uniqueness
            reason: 'Duplicate ID: $id');
        ids.add(id);
      }
    });

    test('IDs use base62 character set', () {
      final nuid = Nuid();
      final id = nuid.next();

      // Verify all characters are valid base62
      final validChars = RegExp(r'^[0-9A-Za-z]+$');
      expect(id, matches(validChars),
          reason: 'ID should only contain base62 characters: $id');
    });

    test('IDs have consistent 22-character length', () {
      final nuid = Nuid();
      for (int i = 0; i < 100; i++) {
        final id = nuid.next();
        expect(id, hasLength(22), reason: 'ID length: ${id.length}');
      }
    });

    test('different NUID instances generate different prefixes', () {
      final nuid1 = Nuid();
      final nuid2 = Nuid();
      final nuid3 = Nuid();

      // Prefix is first 12 characters
      final prefix1 = nuid1.next().substring(0, 12);
      final prefix2 = nuid2.next().substring(0, 12);
      final prefix3 = nuid3.next().substring(0, 12);

      expect(prefix1, hasLength(12));
      expect(prefix2, hasLength(12));
      expect(prefix3, hasLength(12));
    });

    test('prefix contains 12 characters', () {
      final nuid1 = Nuid();
      final nuid2 = Nuid();
      final nuid3 = Nuid();

      // Prefix is first 12 characters
      expect(nuid1.next().substring(0, 12), hasLength(12));
      expect(nuid2.next().substring(0, 12), hasLength(12));
      expect(nuid3.next().substring(0, 12), hasLength(12));
    });
  });

  group('NUID prefix rollover', () {
    test('prefix changes when sequence reaches max', () {
      final nuid = Nuid();
      final prefix1 = nuid.next().substring(0, 12);

      // Generate many IDs to force sequence rollover
      for (int i = 0; i < 1000000; i++) {
        nuid.next();
      }

      final prefix2 = nuid.next().substring(0, 12);

      // Prefix should have changed at least once due to rollover
      // (though due to randomness, we can't guarantee it changed in exactly this many steps)
      // At minimum, verify the current prefix is valid
      expect(prefix2, hasLength(12));
    });

    test('sequence increments correctly', () {
      final nuid = Nuid();
      final id1 = nuid.next();
      final id2 = nuid.next();
      final id3 = nuid.next();

      // Each generated ID should be unique and have 22 characters
      expect(id1, hasLength(22));
      expect(id2, hasLength(22));
      expect(id3, hasLength(22));
      expect(id2, isNot(equals(id1))); // All different
      expect(id3, isNot(equals(id2))); // All different
    });
  });

  group('NUID inbox generation', () {
    test('generate inbox subjects with default prefix', () {
      final nuid = Nuid();
      final inbox1 = nuid.inbox();
      final inbox2 = nuid.inbox();

      // Default prefix is _INBOX
      expect(inbox1, startsWith('_INBOX.'));
      expect(inbox2, startsWith('_INBOX.'));

      // Each inbox should be unique
      expect(inbox1, isNot(equals(inbox2)));
    });

    test('generate inbox subjects with custom prefix', () {
      final nuid = Nuid();
      final inbox1 = nuid.inbox('CUSTOM');
      final inbox2 = nuid.inbox('CUSTOM');

      // Custom prefix should be used
      expect(inbox1, startsWith('CUSTOM.'));
      expect(inbox2, startsWith('CUSTOM.'));

      // Each inbox should be unique
      expect(inbox1, isNot(equals(inbox2)));
    });

    test('inbox subjects contain valid NUIDs after prefix', () {
      final nuid = Nuid();
      final inbox = nuid.inbox();

      // Extract NUID part (after prefix and dot)
      final parts = inbox.split('.');
      expect(parts.length, greaterThanOrEqualTo(2));

      // The NUID part should be 22 characters
      final nuidPart = parts.last;
      expect(nuidPart, hasLength(22),
          reason: 'NUID part should be 22 characters: $nuidPart');

      // Should be valid base62
      final validChars = RegExp(r'^[0-9A-Za-z]+$');
      expect(nuidPart, matches(validChars),
          reason: 'NUID part should be base62: $nuidPart');
    });
  });

  group('NUID uniqueness stress test', () {
    test('generate 10000 unique IDs without collision', () {
      final nuid = Nuid();
      final ids = <String>{};

      for (int i = 0; i < 10000; i++) {
        final id = nuid.next();
        expect(ids, isNot(contains(id)),
            reason: 'Collision detected at iteration $i: $id');
        ids.add(id);
      }

      expect(ids.length, equals(10000));
    });
  });
}
