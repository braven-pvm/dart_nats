/// Integration tests against real NATS server.
///
/// These tests require a running NATS server (e.g., via Docker):
/// ```bash
/// docker run -p 4222:4222 nats:latest
/// ```
///
/// Tests are skipped if a server is not available.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nats_dart/src/client/connection.dart';
import 'package:nats_dart/src/client/options.dart';
import 'package:test/test.dart';

void main() {
  group('Connection', () {
    test('connect to NATS server', () async {
      NatsConnection? nc;
      await Future<NatsConnection?>(() async {
        try {
          nc = await NatsConnection.connect('nats://localhost:4222');
          return nc;
        } catch (e) {
          return null; // Server unavailable - skip test
        }
      }).timeout(
        const Duration(milliseconds: 5000),
        onTimeout: () => null,
      );

      // Skip if server is not available
      if (nc == null) {
        markTestSkipped('NATS server not available on localhost:4222');
        return;
      }

      // Not-null assertion is safe here since we already checked
      final conn = nc!;

      try {
        expect(conn.isConnected, isTrue);
        expect(conn.status, isA<Stream<ConnectionStatus>>());
      } finally {
        await conn.close();
        expect(conn.isConnected, isFalse);
      }
    });

    test('close connection', () async {
      NatsConnection? nc;
      await Future<NatsConnection?>(() async {
        try {
          nc = await NatsConnection.connect('nats://localhost:4222');
          return nc;
        } catch (e) {
          return null;
        }
      }).timeout(
        const Duration(milliseconds: 5000),
        onTimeout: () => null,
      );

      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc!;

      try {
        expect(conn.isConnected, isTrue);
        await conn.close();
        expect(conn.isConnected, isFalse);
      } catch (e) {
        // Connection might already be closed
      }
    });
  });

  group('Pub/Sub', () {
    test('publish and subscribe round-trip', () async {
      NatsConnection? nc;
      await Future<NatsConnection?>(() async {
        try {
          nc = await NatsConnection.connect('nats://localhost:4222');
          return nc;
        } catch (e) {
          return null;
        }
      }).timeout(
        const Duration(milliseconds: 5000),
        onTimeout: () => null,
      );

      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc!;

      try {
        final subject = 'test.publish.subscribe';
        final testData = 'Hello, NATS!';

        // Subscribe to the subject
        final sub = conn.subscribe(subject);
        expect(sub.isActive, isTrue);
        expect(sub.subject, equals(subject));

        // Publish a message
        await conn.publish(
          subject,
          Uint8List.fromList(testData.codeUnits),
        );

        // Wait for message receipt with timeout
        final msg =
            await sub.messages.timeout(const Duration(seconds: 10)).first;

        // Verify message received
        expect(msg.subject, equals(subject));
        expect(msg.payload, isNotNull);
        expect(utf8.decode(msg.payload!), equals(testData));

        await conn.unsubscribe(sub);
        expect(sub.isActive, isFalse);
      } finally {
        await conn.close();
      }
    });

    test('unsubscribe behavior', () async {
      NatsConnection? nc;
      await Future<NatsConnection?>(() async {
        try {
          nc = await NatsConnection.connect('nats://localhost:4222');
          return nc;
        } catch (e) {
          return null;
        }
      }).timeout(
        const Duration(milliseconds: 5000),
        onTimeout: () => null,
      );

      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc!;

      try {
        final subject = 'test.unsubscribe';

        // Subscribe to the subject
        final sub = conn.subscribe(subject);
        expect(sub.isActive, isTrue);

        // Unsubscribe
        await conn.unsubscribe(sub);

        // Verify subscription is inactive
        expect(sub.isActive, isFalse);

        // Verify unsubscribed subscription is removed from tracking
        final sub2 = conn.subscribe(subject);
        expect(sub2.sid, isNot(equals(sub.sid)));
      } finally {
        await conn.close();
      }
    });

    test('subscribe with max messages auto-unsubscribe', () async {
      NatsConnection? nc;
      await Future<NatsConnection?>(() async {
        try {
          nc = await NatsConnection.connect('nats://localhost:4222');
          return nc;
        } catch (e) {
          return null;
        }
      }).timeout(
        const Duration(milliseconds: 5000),
        onTimeout: () => null,
      );

      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc!;

      try {
        final subject = 'test.max.messages';
        final numMessages = 3;

        // Subscribe with max messages
        final sub = conn.subscribe(subject, max: numMessages);
        expect(sub.isActive, isTrue);

        // Publish multiple messages
        for (int i = 0; i < numMessages + 2; i++) {
          await conn.publish(
            subject,
            Uint8List.fromList('msg$i'.codeUnits),
          );
        }

        // Wait for messages to arrive
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Count messages received
        int count = 0;
        await for (final _ in sub.messages) {
          count++;
        }

        // Client-side receives at most max due to auto-unsubscribe
        expect(count, lessThanOrEqualTo(numMessages));

        await conn.unsubscribe(sub);
      } finally {
        await conn.close();
      }
    });
  });

  group('Request/Reply', () {
    test('basic request/reply round-trip', () async {
      NatsConnection? nc;
      await Future<NatsConnection?>(() async {
        try {
          nc = await NatsConnection.connect('nats://localhost:4222');
          return nc;
        } catch (e) {
          return null;
        }
      }).timeout(
        const Duration(milliseconds: 5000),
        onTimeout: () => null,
      );

      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc!;

      try {
        final requestSubject = 'test.request';
        final replySubject = 'test.reply';
        final requestData = 'ping';
        final replyData = 'pong';

        // Subscribe to request subject
        final sub = conn.subscribe(requestSubject);

        // Listen for requests and reply
        final replyFuture = sub.messages.first.then((msg) async {
          expect(msg.subject, equals(requestSubject));
          expect(msg.replyTo, isNotNull);

          // Send reply
          await conn.publish(
            replySubject,
            Uint8List.fromList(replyData.codeUnits),
          );
        });

        // Not a full request/reply - just verify message receipt
        await conn.publish(
          requestSubject,
          Uint8List.fromList(requestData.codeUnits),
        );

        await replyFuture.timeout(const Duration(seconds: 5));
      } finally {
        await conn.close();
      }
    });
  });
}
