/// Integration tests against real NATS server.
///
/// These tests require a running NATS server (e.g., via Docker):
/// ```bash
/// docker run -p 4222:4222 nats:latest
/// ```
///
/// Tests are skipped if a server is not available.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Connection', () {
    test('connect to NATS server', () async {
      // TODO: Connect to nats://localhost:4222 and verify connection
    },
        skip:
            'Requires running NATS server. Run: docker run -p 4222:4222 nats:latest');

    test('close connection', () async {
      // TODO: Connect, then close and verify cleanup
    }, skip: 'Requires running NATS server');
  });

  group('Pub/Sub', () {
    test('publish and subscribe', () async {
      // TODO: Subscribe to subject, publish message, verify receipt
    }, skip: 'Requires running NATS server');

    test('wildcards', () async {
      // TODO: Test * and > wildcard patterns with multiple subscriptions
    }, skip: 'Requires running NATS server');
  });

  group('Request/Reply', () {
    test('basic request/reply round-trip', () async {
      // TODO: Send request to responder, verify reply received
    }, skip: 'Requires running NATS server');
  });

  group('Queue Groups', () {
    test('distribute messages across queue group', () async {
      // TODO: Create multiple subscribers in same queue group, verify distribution
    }, skip: 'Requires running NATS server');
  });

  group('Reconnection', () {
    test('auto-reconnect on server restart', () async {
      // TODO: Disconnect server, verify auto-reconnect, resubscribe
    }, skip: 'Requires running NATS server');
  });

  group('Authentication', () {
    test('token authentication', () async {
      // TODO: Connect with token, verify auth succeeds
    }, skip: 'Requires NATS server with token auth');

    test('user/password authentication', () async {
      // TODO: Connect with user/pass, verify auth succeeds
    }, skip: 'Requires NATS server with user/pass auth');
  });

  group('JetStream', () {
    test('create and list streams', () async {
      // TODO: Create stream, list streams, verify creation
    }, skip: 'Requires NATS server with JetStream enabled');

    test('create and list consumers', () async {
      // TODO: Create pull consumer, list consumers, verify
    }, skip: 'Requires NATS server with JetStream enabled');

    test('pull consumer fetch', () async {
      // TODO: Publish messages, fetch batch with pull consumer, verify
    }, skip: 'Requires NATS server with JetStream enabled');

    test('ordered consumer auto-recreate on gap', () async {
      // TODO: Simulate gap, verify ordered consumer recreates consumer
    }, skip: 'Requires NATS server with JetStream enabled');
  });

  group('KeyValue Store', () {
    test('create bucket and put/get values', () async {
      // TODO: Create KV bucket, put key, get key, verify value
    }, skip: 'Requires NATS server with JetStream enabled');

    test('delete key and verify watch', () async {
      // TODO: Watch bucket, delete key, verify watch receives delete
    }, skip: 'Requires NATS server with JetStream enabled');

    test('update with expected version (ETag)', () async {
      // TODO: Put key, get version, update with expected version, verify
      // TODO: Update with wrong expected version, verify failure
    }, skip: 'Requires NATS server with JetStream enabled');
  });
}
