/// Integration tests for request/reply pattern.
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
import 'package:test/test.dart';

void main() {
  group('Request/Reply', () {
    // Helper to connect or skip test
    Future<NatsConnection?> connectOrSkip() async {
      try {
        return await NatsConnection.connect('nats://localhost:4222')
            .timeout(const Duration(milliseconds: 5000));
      } on TimeoutException {
        return null;
      } catch (e) {
        return null;
      }
    }

    test('successful request/reply round-trip', () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final requestSubject = 'test.request.reply';
        final requestData = 'ping';
        final replyData = 'pong';

// Subscribe a responder on the request subject
        final responderSub = await conn.subscribe(requestSubject);
        // Listen for requests and reply to the inbox (fire-and-forget)
        responderSub.messages.first.then((msg) async {
          expect(msg.replyTo, isNotNull,
              reason: 'Request should have reply-to subject');

          // Send reply to the inbox
          await conn.publish(
            msg.replyTo!,
            Uint8List.fromList(replyData.codeUnits),
          );
        });
        // Give subscription time to register
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Make request and wait for reply
        final replyMsg = await conn.request(
          requestSubject,
          Uint8List.fromList(requestData.codeUnits),
        );

        // Verify reply
        expect(replyMsg.payload, isNotNull);
        expect(utf8.decode(replyMsg.payload!), equals(replyData));

        // Clean up responder subscription (close() is synchronous)
        responderSub.close();
      } finally {
        await conn.close();
      }
    });

    test('TimeoutException on no responder', () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final requestSubject =
            'test.request.no.responder.${DateTime.now().millisecondsSinceEpoch}';
        final requestData = 'ping';

        // Make request with short timeout on subject with no subscriber.
        // Use expectLater so the test waits for the async timeout before
        // the finally block closes the connection.
        await expectLater(
          conn.request(
            requestSubject,
            Uint8List.fromList(requestData.codeUnits),
            timeout: const Duration(milliseconds: 200),
          ),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        await conn.close();
      }
    });

    test('subscription cleanup after successful reply', () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final requestSubject = 'test.request.cleanup.success';
        final requestData = 'ping';
        final replyData = 'pong';

// Subscribe responder
        final responderSub = await conn.subscribe(requestSubject);
        final replyFuture = responderSub.messages.first.then((msg) async {
          await conn.publish(
            msg.replyTo!,
            Uint8List.fromList(replyData.codeUnits),
          );
        });

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Capture initial subscription count
        final initialSubCount = conn.subscriptionCount;

        // Make successful request
        await conn.request(
          requestSubject,
          Uint8List.fromList(requestData.codeUnits),
        );

        // Verify reply was received
        await replyFuture.timeout(const Duration(seconds: 5));

        // Verify subscription count is back to initial count
        // (request subscription should have been cleaned up)
        expect(conn.subscriptionCount, equals(initialSubCount),
            reason: 'Request subscription should be cleaned up after success');

        // Clean up responder subscription (close() is synchronous)
        responderSub.close();
      } finally {
        await conn.close();
      }
    });

    test('subscription cleanup after timeout', () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final requestSubject =
            'test.request.cleanup.timeout.${DateTime.now().millisecondsSinceEpoch}';

        // Capture initial subscription count
        final initialSubCount = conn.subscriptionCount;

        // Make request that will timeout
        try {
          await conn.request(
            requestSubject,
            Uint8List.fromList('ping'.codeUnits),
            timeout: const Duration(milliseconds: 200),
          );
          fail('Expected TimeoutException');
        } on TimeoutException {
          // Expected
        }

        // Verify subscription count is back to initial count
        // (request subscription should have been cleaned up after timeout)
        expect(conn.subscriptionCount, equals(initialSubCount),
            reason: 'Request subscription should be cleaned up after timeout');
      } finally {
        await conn.close();
      }
    });

    test('multiple sequential requests do not leak subscriptions', () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final baseSubject = 'test.request.sequential';
        final replyData = 'reply';

// Subscribe a responder for multiple subjects (wildcard)
        final responderSub = await conn.subscribe('test.request.sequential.>');
        // Start responder in background
        final responderFuture = responderSub.messages.listen((msg) async {
          if (msg.replyTo != null) {
            await conn.publish(
              msg.replyTo!,
              Uint8List.fromList(replyData.codeUnits),
            );
          }
        });

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Capture initial subscription count
        final initialSubCount = conn.subscriptionCount;

        // Make multiple sequential requests
        for (int i = 0; i < 5; i++) {
          final replyMsg = await conn.request(
            '$baseSubject.$i',
            Uint8List.fromList('request$i'.codeUnits),
          );

          expect(replyMsg.payload, isNotNull);
          expect(utf8.decode(replyMsg.payload!), equals(replyData));

          // Verify no subscription leak after each request
          expect(conn.subscriptionCount, equals(initialSubCount),
              reason: 'No subscription leak after request $i');
        }

        // Cancel listener and clean up responder subscription
        await responderFuture.cancel();
        responderSub.close();
      } finally {
        await conn.close();
      }
    });

    test('fast-responder race condition prevention (subscribe-before-publish)',
        () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final requestSubject = 'test.request.fast.responder';
        final replyData = 'fast-reply';

        // Pre-create subscription with an immediately-available message
        // This simulates a very fast responder that replies instantly
        final responderSub = await conn.subscribe(requestSubject);
        // Set up a responder that replies IMMEDIATELY (no delay)
        final responderFuture = responderSub.messages.listen((msg) async {
          if (msg.replyTo != null) {
            // Reply immediately without any delay
            await conn.publish(
              msg.replyTo!,
              Uint8List.fromList(replyData.codeUnits),
            );
          }
        });

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Make request - because we subscribe BEFORE publishing,
        // even a very fast responder will successfully deliver the reply
        final replyMsg = await conn.request(
          requestSubject,
          Uint8List.fromList('test'.codeUnits),
          timeout: const Duration(seconds: 5),
        );

        // Verify reply is received - this validates that subscribe-before-publish
        // ordering prevents the race condition
        expect(replyMsg.payload, isNotNull,
            reason:
                'Reply should be received even with extremely fast responder');
        expect(utf8.decode(replyMsg.payload!), equals(replyData));

        // Cancel listener and clean up responder subscription
        await responderFuture.cancel();
        responderSub.close();
      } finally {
        await conn.close();
      }
    });

    test('request with default timeout (10 seconds)', () async {
      final nc = await connectOrSkip();
      if (nc == null) {
        markTestSkipped('NATS server not available');
        return;
      }

      final conn = nc;
      try {
        final requestSubject = 'test.request.default.timeout';
        final replyData = 'reply';

        // Subscribe a responder
        final responderSub = await conn.subscribe(requestSubject);
        final responderFuture = responderSub.messages.listen((msg) async {
          if (msg.replyTo != null) {
            await conn.publish(
              msg.replyTo!,
              Uint8List.fromList(replyData.codeUnits),
            );
          }
        });

        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Make request WITHOUT explicit timeout (uses default 10s)
        final replyMsg = await conn.request(
          requestSubject,
          Uint8List.fromList('test'.codeUnits),
          // No timeout specified - should use default
        );

        expect(replyMsg.payload, isNotNull);
        expect(utf8.decode(replyMsg.payload!), equals(replyData));

        // Cancel listener and clean up responder subscription
        await responderFuture.cancel();
        responderSub.close();
      } finally {
        await conn.close();
      }
    });
  });
}
