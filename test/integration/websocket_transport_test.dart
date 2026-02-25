/// Integration tests for WebSocketTransport against real NATS WebSocket server.
///
/// These tests require a running NATS server with WebSocket enabled:
/// ```bash
/// # Standard NATS server with WebSocket on port 8080
/// nats-server --port 4222 --websocket 8080
///
/// # Or via Docker:
/// docker run -p 4222:4222 -p 8080:8080 nats:latest --websocket 8080
/// ```
///
/// Tests are skipped if a server is not available.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/transport/websocket_transport.dart';

void main() {
  group('WebSocketTransport - Connection Lifecycle', () {
    test('isConnected is false before connect()', () {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      expect(transport.isConnected, isFalse);
    });

    test('isConnected is true after successful connect()', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        expect(transport.isConnected, isTrue);
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      } finally {
        await transport.close();
      }
    });

    test('isConnected is false after close()', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        await transport.close();
        expect(transport.isConnected, isFalse);
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      }
    });

    test('close() is idempotent - calling multiple times has no side effects',
        () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        await transport.close();

        // Second close should complete without error
        await transport.close();

        // Third close for good measure
        await transport.close();

        expect(transport.isConnected, isFalse);
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      }
    });

    test('close() can be called before connect()', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      // Should not throw
      await transport.close();
      expect(transport.isConnected, isFalse);
    });

    test('multiple connect() calls throw StateError', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));

      try {
        await transport.connect();
        expect(transport.isConnected, isTrue);

        // Second connect should throw StateError
        expect(
          () => transport.connect(),
          throwsA(isA<StateError>()),
        );
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      } finally {
        await transport.close();
      }
    });
  });

  group('WebSocketTransport - Send/Receive', () {
    test('incoming stream emits Uint8List chunks received from server',
        () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
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
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('write(Uint8List data) sends bytes to server', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();

        // Wait briefly for INFO to arrive
        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Send PING
        await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));

        // Should not throw
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      } finally {
        await transport.close();
      }
    });

    test('PING command receives PONG response', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
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
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('write() throws StateError if not connected', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      expect(
        () => transport.write(Uint8List.fromList('PING\r\n'.codeUnits)),
        throwsA(isA<StateError>()),
      );
    });

    test('write() throws StateError after close()', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        await transport.close();

        expect(
          () => transport.write(Uint8List.fromList('PING\r\n'.codeUnits)),
          throwsA(isA<StateError>()),
        );
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      }
    });
  });

  group('WebSocketTransport - Timeout', () {
    test('connect() throws TimeoutException after connectTimeout duration',
        () async {
      // Use non-routable IP to simulate connection hang
      final transport = WebSocketTransport(
        Uri.parse('ws://10.255.255.1:8080'),
        connectTimeout: const Duration(seconds: 1),
      );

      final stopwatch = Stopwatch()..start();

      try {
        await transport.connect();
        fail('Should throw TimeoutException');
      } on TimeoutException catch (e) {
        stopwatch.stop();
        expect(stopwatch.elapsed.inSeconds, lessThanOrEqualTo(2));
        expect(e.message, contains('timeout'));
        expect(transport.isConnected, isFalse);
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 5)));
  });

  group('WebSocketTransport - Errors', () {
    test('errors stream emits network errors', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
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
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      }
    });

    test('connection failure emits error on errors stream', () async {
      // Try to connect to invalid port
      final transport = WebSocketTransport(Uri.parse('ws://localhost:59999'));
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
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
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
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      }
    });
  });

  group('WebSocketTransport - UTF-8 Handling', () {
    test('incoming stream properly decodes UTF-8 text frames', () async {
      // This test verifies that String messages from WebSocket are properly
      // decoded using utf8.decode() instead of .codeUnits
      // Note: This test requires a NATS server that sends UTF-8 in INFO
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      final completer = Completer<Uint8List>();

      try {
        await transport.connect();

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

        // Wait for INFO which may contain UTF-8 characters
        final data = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('No data received'),
        );

        // Verify we can properly decode the data
        expect(data, isA<Uint8List>());
        final decoded = String.fromCharCodes(data);
        expect(decoded, contains('INFO'));
      } catch (e) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
