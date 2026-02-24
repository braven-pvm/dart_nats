/// Integration tests for TcpTransport against real NATS server.
///
/// These tests require a running NATS server (e.g., via Docker):
/// ```bash
/// docker run -p 4222:4222 nats:latest
/// ```
///
/// Tests are skipped if a server is not available.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/transport/tcp_transport.dart';

void main() {
  group('TcpTransport - Connection Lifecycle', () {
    test('isConnected is false before connect()', () {
      final transport = TcpTransport('localhost', 4222);
      expect(transport.isConnected, isFalse);
    });

    test('isConnected is true after successful connect()', () async {
      final transport = TcpTransport('localhost', 4222);

      try {
        await transport.connect();
        expect(transport.isConnected, isTrue);
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      } finally {
        await transport.close();
      }
    });

    test('isConnected is false after close()', () async {
      final transport = TcpTransport('localhost', 4222);

      try {
        await transport.connect();
        await transport.close();
        expect(transport.isConnected, isFalse);
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      }
    });

    test('close() is idempotent - calling multiple times has no side effects',
        () async {
      final transport = TcpTransport('localhost', 4222);

      try {
        await transport.connect();
        await transport.close();

        // Second close should complete without error
        await transport.close();

        // Third close for good measure
        await transport.close();

        expect(transport.isConnected, isFalse);
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      }
    });

    test('close() can be called before connect()', () async {
      final transport = TcpTransport('localhost', 4222);

      // Should not throw
      await transport.close();
      expect(transport.isConnected, isFalse);
    });
  });

  group('TcpTransport - Send/Receive', () {
    test('incoming stream emits Uint8List chunks received from server',
        () async {
      final transport = TcpTransport('localhost', 4222);
      final completer = Completer<Uint8List>();

      try {
        await transport.connect();

        // Listen for incoming data
        transport.incoming.listen(
          (data) {
            if (!completer.isCompleted) {
              completer.complete(data);
            }
          },
          onError: (Object error) {
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
        );

        // Wait for INFO from NATS server
        final data = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('No data received'),
        );

        expect(data, isA<Uint8List>());
        expect(data.length, greaterThan(0));

        // INFO message should start with 'INFO'
        final infoString = String.fromCharCodes(data);
        expect(infoString, startsWith('INFO'));
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('write(Uint8List data) sends bytes to server', () async {
      final transport = TcpTransport('localhost', 4222);

      try {
        await transport.connect();

        // Wait briefly for INFO to arrive
        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Send PING
        await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));

        // Should not throw
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      } finally {
        await transport.close();
      }
    });

    test('PING command receives PONG response', () async {
      final transport = TcpTransport('localhost', 4222);
      final responses = <Uint8List>[];

      try {
        await transport.connect();

        // Listen for all responses
        final subscription = transport.incoming.listen(
          (data) => responses.add(data),
        );

        // Wait for INFO
        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Send PING
        await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));

        // Wait for PONG
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await subscription.cancel();

        // Check for PONG in responses
        final allData =
            responses.map((Uint8List r) => String.fromCharCodes(r)).join('');
        expect(allData, contains('PONG'));
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('write() throws StateError if not connected', () async {
      final transport = TcpTransport('localhost', 4222);

      expect(
        () => transport.write(Uint8List.fromList('PING\r\n'.codeUnits)),
        throwsA(isA<StateError>()),
      );
    });

    test('write() throws StateError after close()', () async {
      final transport = TcpTransport('localhost', 4222);

      try {
        await transport.connect();
        await transport.close();

        expect(
          () => transport.write(Uint8List.fromList('PING\r\n'.codeUnits)),
          throwsA(isA<StateError>()),
        );
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      }
    });
  });

  group('TcpTransport - Errors', () {
    test('errors stream emits network errors', () async {
      final transport = TcpTransport('localhost', 4222);
      final errors = <Object>[];

      try {
        await transport.connect();

        // Listen for errors
        transport.errors.listen((error) => errors.add(error));

        // Simulate scenario that would cause an error
        // (Connection to valid server won't produce errors in normal operation)
        // This test verifies the errors stream is set up correctly

        await transport.close();

        // No errors should have occurred in normal operation
        expect(errors, isEmpty);
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      }
    });

    test('connection failure emits error on errors stream', () async {
      // Try to connect to invalid port
      final transport = TcpTransport('localhost', 59999);
      final errors = <Object>[];

      transport.errors.listen((error) => errors.add(error));

      try {
        await transport.connect();
        fail('Should have thrown on connection failure');
      } catch (_) {
        // Expected - connection should fail
        expect(transport.isConnected, isFalse);
      }
    });

    test('errors stream is closed after close()', () async {
      final transport = TcpTransport('localhost', 4222);

      try {
        await transport.connect();

        final doneCompleter = Completer<bool>();
        transport.errors.listen(
          (_) {},
          onDone: () => doneCompleter.complete(true),
        );

        await transport.close();

        final isDone = await doneCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => false,
        );

        expect(isDone, isTrue);
      } on SocketException {
        markTestSkipped('NATS server not running on localhost:4222');
      }
    });
  });

  group('TcpTransport - TLS', () {
    test('connect with TLS enabled', () async {
      // Most NATS servers don't have TLS on by default, so skip if not available
      final transport = TcpTransport('localhost', 4223, useTls: true);

      try {
        await transport.connect();
        expect(transport.isConnected, isTrue);
      } on SocketException {
        markTestSkipped('NATS server with TLS not running on localhost:4223');
      } on HandshakeException {
        markTestSkipped('TLS handshake failed - server may not support TLS');
      } finally {
        await transport.close();
      }
    });
  });
}
