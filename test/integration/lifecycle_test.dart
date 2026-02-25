/// Integration tests for NatsConnection lifecycle (close and drain).
///
/// Uses FakeNatsServer for deterministic testing without a live NATS server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nats_dart/src/client/connection.dart';
import 'package:nats_dart/src/client/options.dart';
import 'package:test/test.dart';

import 'fake_nats_server.dart';

void main() {
  group('NatsConnection.close() lifecycle', () {
    late FakeNatsServer server;
    late NatsConnection nc;

    setUp(() async {
      server = FakeNatsServer();
      await server.start();
      nc = await NatsConnection.connect('nats://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      // Best-effort cleanup — connection may already be closed
      try {
        await nc.close();
      } catch (_) {}
      await server.stop();
    });

    test('close() sets isConnected to false', () async {
      expect(nc.isConnected, isTrue,
          reason: 'Should be connected before close()');

      await nc.close();

      expect(nc.isConnected, isFalse,
          reason: 'isConnected should be false after close()');
    });

    test('close() is idempotent — calling twice does not throw', () async {
      // First close
      await nc.close();
      expect(nc.isConnected, isFalse);

      // Second close — must not throw
      await expectLater(nc.close(), completes);

      // Connection is still closed
      expect(nc.isConnected, isFalse);
    });

    test('close() emits ConnectionStatus.closed on status stream', () async {
      final statuses = <ConnectionStatus>[];
      final sub = nc.status.listen(statuses.add);

      await nc.close();

      // Allow events to propagate
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(statuses, contains(ConnectionStatus.closed),
          reason: 'Status stream should emit closed after close()');
    });

    test('close() clears all active subscriptions', () async {
      // Create some subscriptions
      await nc.subscribe('test.one');
      await nc.subscribe('test.two');
      expect(nc.subscriptionCount, equals(2));

      await nc.close();

      expect(nc.subscriptionCount, equals(0),
          reason: 'All subscriptions should be cleared after close()');
    });
  });

  group('NatsConnection.drain() lifecycle', () {
    late FakeNatsServer server;
    late NatsConnection nc;

    setUp(() async {
      server = FakeNatsServer();
      await server.start();
      nc = await NatsConnection.connect('nats://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      // Best-effort cleanup
      try {
        await nc.close();
      } catch (_) {}
      await server.stop();
    });

    test('drain() emits ConnectionStatus.draining then closed', () async {
      final statuses = <ConnectionStatus>[];
      final sub = nc.status.listen(statuses.add);

      await nc.drain();

      // Allow events to propagate
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(statuses, contains(ConnectionStatus.draining),
          reason: 'drain() should emit draining status');
      expect(statuses, contains(ConnectionStatus.closed),
          reason: 'drain() should emit closed status after draining');

      // draining should come before closed
      final drainingIndex = statuses.indexOf(ConnectionStatus.draining);
      final closedIndex = statuses.indexOf(ConnectionStatus.closed);
      expect(drainingIndex, lessThan(closedIndex),
          reason: 'draining should be emitted before closed');
    });

    test('drain() sets isConnected to false', () async {
      expect(nc.isConnected, isTrue);

      await nc.drain();

      expect(nc.isConnected, isFalse,
          reason: 'isConnected should be false after drain()');
    });

    test('drain() on already-closed connection is a no-op', () async {
      await nc.close();
      expect(nc.isConnected, isFalse);

      // drain() on closed connection should return immediately without throwing
      await expectLater(nc.drain(), completes);

      expect(nc.isConnected, isFalse);
    });

    test('drain() sends UNSUB for active subscriptions', () async {
      server.clearReceivedCommands();

      // Create a subscription
      await nc.subscribe('test.drain.subject');

      server.clearReceivedCommands();

      // Drain should send UNSUB before closing
      await nc.drain();

      // FakeNatsServer tracks commands received — verify UNSUB was sent
      final commands = server.receivedCommands;
      expect(
        commands.any((cmd) => cmd.startsWith('UNSUB ')),
        isTrue,
        reason: 'drain() should send UNSUB for active subscriptions',
      );
    });
  });

  group('max_payload enforcement', () {
    late _MaxPayloadFakeServer server;

    setUp(() async {
      server = _MaxPayloadFakeServer();
    });

    tearDown(() async {
      await server.stop();
    });

    test('publish() throws ArgumentError when payload exceeds max_payload',
        () async {
      await server.start(maxPayload: 10);
      final nc =
          await NatsConnection.connect('nats://127.0.0.1:${server.port}');
      try {
        // Create a payload that exceeds max_payload=10
        final bigPayload = Uint8List(20);
        await expectLater(
          nc.publish('test.subject', bigPayload),
          throwsA(isA<ArgumentError>()),
          reason:
              'publish() should throw ArgumentError when payload > max_payload',
        );
      } finally {
        await nc.close();
      }
    });

    test('publish() succeeds when payload is within max_payload', () async {
      await server.start(maxPayload: 100);
      final nc =
          await NatsConnection.connect('nats://127.0.0.1:${server.port}');
      try {
        // Create a payload within max_payload=100
        final smallPayload = Uint8List(50);
        await expectLater(
          nc.publish('test.subject', smallPayload),
          completes,
          reason: 'publish() should not throw when payload <= max_payload',
        );
      } finally {
        await nc.close();
      }
    });
  });
}

/// A standalone fake NATS server that includes max_payload in its INFO message.
///
/// Used to test that NatsConnection enforces max_payload from server INFO.
class _MaxPayloadFakeServer {
  ServerSocket? _serverSocket;
  final List<Socket> _clients = [];

  int get port => _serverSocket!.port;

  Future<void> start({required int maxPayload, int port = 0}) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _serverSocket!.listen((Socket client) {
      _clients.add(client);
      _handleClient(client, maxPayload);
    });
  }

  void _handleClient(Socket client, int maxPayload) {
    final infoJson = jsonEncode({
      'server_id': 'fake-maxpayload',
      'version': '1.0',
      'proto': 1,
      'headers': true,
      'jetstream': false,
      'max_payload': maxPayload,
    });
    client.write('INFO $infoJson\r\n');
    client.flush();

    final List<int> buffer = [];
    client.listen(
      (List<int> data) {
        buffer.addAll(data);
        _parseBuffer(client, buffer);
      },
      onDone: () => _clients.remove(client),
      onError: (Object error) => _clients.remove(client),
    );
  }

  void _parseBuffer(Socket client, List<int> buffer) {
    int start = 0;
    for (int i = 0; i < buffer.length - 1; i++) {
      if (buffer[i] == 13 && buffer[i + 1] == 10) {
        final lineBytes = buffer.sublist(start, i);
        final line = utf8.decode(lineBytes).trim();
        if (line.isNotEmpty) {
          if (line.startsWith('CONNECT ')) {
            client.write('+OK\r\n');
          } else if (line.startsWith('PING')) {
            client.write('PONG\r\n');
          } else if (line.startsWith('PUB ') ||
              line.startsWith('HPUB ') ||
              line.startsWith('SUB ') ||
              line.startsWith('UNSUB ')) {
            client.write('+OK\r\n');
          }
        }
        start = i + 2;
      }
    }
    if (start > 0) {
      buffer.removeRange(0, start);
    }
  }

  Future<void> stop() async {
    for (final client in List<Socket>.from(_clients)) {
      client.destroy();
    }
    await _serverSocket?.close();
    _serverSocket = null;
  }
}
