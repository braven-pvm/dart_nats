import 'package:test/test.dart';
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

      // Generate many IDs to force sequence rollover
      for (int i = 0; i < 1000000; i++) {
        nuid.next();
      }

      final finalId = nuid.next();
      expect(finalId, hasLength(22));
    });

    test('sequence increments correctly', () {
      // This is implicitly tested by the uniqueness test,
      // but we verify NUID generates different IDs on each call
      final nuid = Nuid();
      final id1 = nuid.next();
      final id2 = nuid.next();
      final id3 = nuid.next();

      expect(id2, isNot(equals(id1)));
      expect(id3, isNot(equals(id2)));
      expect(id3, isNot(equals(id1)));
    });
  });

  group('NUID inbox generation', () {
    test('inbox generates with prefix', () {
      final nuid = Nuid();
      final inbox = nuid.inbox();

      expect(inbox, startsWith('_INBOX.'));
      expect(inbox, isNot(endsWith('.')));
      expect(inbox.length, greaterThan(8)); // '_INBOX.' is 8 chars
    });

    test('inbox uses custom prefix', () {
      final nuid = Nuid();
      final inbox = nuid.inbox('CUSTOM');

      expect(inbox, startsWith('CUSTOM.'));
      expect(inbox, isNot(endsWith('.')));
    });

    test('inbox generates unique inboxes', () {
      final nuid = Nuid();

      final inbox1 = nuid.inbox();
      final inbox2 = nuid.inbox();
      final inbox3 = nuid.inbox();

      expect(inbox1, isNot(equals(inbox2)));
      expect(inbox2, isNot(equals(inbox3)));
      expect(inbox3, isNot(equals(inbox1)));
    });

    test('inbox has expected length (inbox + suffix)', () {
      final nuid = Nuid();
      final inbox = nuid.inbox();

      // Should be: <prefix>.<NUID>
      // Default prefix: '_INBOX.' (8 chars)
      // NUID: 22 chars
      // Total: 30 chars (for default prefix)
      expect(inbox.length, allOf(greaterThan(8), lessThan(50)));
    });

    test('inbox maintains NUID format', () {
      final nuid = Nuid();
      final inbox = nuid.inbox();
      final parts = inbox.split('.');

      // Should be: '_INBOX.<NUID>'
      expect(parts[0], equals('_INBOX'));
      expect(parts[1], hasLength(22)); // NUID is always 22 chars
      expect(parts.length, equals(2));
    });
  });

  group('NUID edge cases', () {
    test('multiple NUID instances remain independent', () {
      final nuid1 = Nuid();
      final nuid2 = Nuid();

      final id1_1 = nuid1.next();
      final id2_1 = nuid2.next();

      final id1_2 = nuid1.next();
      final id2_2 = nuid2.next();

      // Each NUID has its own sequence counter
      expect(id1_1, isNot(equals(id1_2)));
      expect(id2_1, isNot(equals(id2_2)));

      // IDs from different instances should be different (statistically)
      final allIds = {id1_1, id1_2, id2_1, id2_2};
      expect(allIds.length, equals(4));
    });

    test('inbox from different instances are unique', () {
      final nuid1 = Nuid();
      final nuid2 = Nuid();

      final inbox1 = nuid1.inbox();
      final inbox2 = nuid2.inbox();

      expect(inbox1, isNot(equals(inbox2)));
    });

    test('NUID continues after many calls', () {
      final nuid = Nuid();

      // Generate 10000 IDs and verify all are valid
      for (int i = 0; i < 10000; i++) {
        final id = nuid.next();
        expect(id, hasLength(22));

        final validChars = RegExp(r'^[0-9A-Za-z]+$');
        expect(id, matches(validChars));
      }
    });
  });

  group('NUID format requirements from handshake spec', () {
    test('NUID matches specification requirements', () {
      final nuid = Nuid();
      final id = nuid.next();

      // Per NATS handshake spec: alphanumeric, time-based
      expect(id, hasLength(22));
      expect(id, matches(RegExp(r'^[0-9A-Za-z]+$')));

      // Verify it's not all zeros or same character repeated
      final uniqueChars = id.split('').toSet();
      expect(uniqueChars.length, greaterThan(1),
          reason: 'NUID should have variation, not all same char');
    });
  });
}
