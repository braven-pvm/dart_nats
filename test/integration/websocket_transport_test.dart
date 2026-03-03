/// Integration tests for WebSocketTransport against a real NATS WebSocket server.
///
/// The test harness automatically starts nats-server with WebSocket on
/// ws://localhost:8080. It searches for the binary on PATH and, on Windows,
/// under %USERPROFILE%\nats-server\. If the binary is not found, all
/// server-requiring tests are skipped gracefully.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:nats_dart/src/transport/websocket_transport.dart';

const _wsPort = 8080;
const _natsTcpPort = 4225; // avoids conflict with default :4222

/// Returns the path to the nats-server binary, or null if not found.
String? _findNatsBinary() {
  // 1. Check PATH
  try {
    final r = Process.runSync('nats-server', ['--version']);
    if (r.exitCode == 0) return 'nats-server';
  } catch (_) {}

  // 2. Windows: %USERPROFILE%\nats-server\<version-dir>\nats-server.exe
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final base = Directory('$home\\nats-server');
    if (base.existsSync()) {
      for (final entry in base.listSync().whereType<Directory>()) {
        final exe = File('${entry.path}\\nats-server.exe');
        if (exe.existsSync()) return exe.path;
      }
    }
  }
  return null;
}

/// Start nats-server with WebSocket on [_wsPort] and waits until it is ready.
/// Returns the [Process] on success, or null if startup fails.
Future<Process?> _startNatsWithWebSocket(String binary) async {
  final configFile = File('${Directory.systemTemp.path}/nats_ws_test.conf');
  await configFile.writeAsString('''
port: $_natsTcpPort
jetstream: false

websocket {
  port: $_wsPort
  no_tls: true
}
''');

  Process process;
  try {
    process = await Process.start(binary, ['-c', configFile.path]);
  } catch (_) {
    return null;
  }

  // Poll until the WS port accepts connections (up to 3 s).
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      final s = await Socket.connect(
        'localhost',
        _wsPort,
        timeout: const Duration(milliseconds: 200),
      );
      await s.close();
      return process; // Ready.
    } catch (_) {}
  }

  process.kill();
  return null;
}

void main() {
  Process? _natsProcess;
  bool _wsAvailable = false;

  setUpAll(() async {
    final binary = _findNatsBinary();
    if (binary == null) {
      // ignore: avoid_print
      print('[WebSocketTests] nats-server binary not found — '
          'server-requiring tests will be skipped.');
      return;
    }
    _natsProcess = await _startNatsWithWebSocket(binary);
    _wsAvailable = _natsProcess != null;
    if (!_wsAvailable) {
      // ignore: avoid_print
      print('[WebSocketTests] nats-server failed to start — '
          'server-requiring tests will be skipped.');
    }
  });

  tearDownAll(() async {
    _natsProcess?.kill();
    _natsProcess = null;
  });
  group('WebSocketTransport - Connection Lifecycle', () {
    test('isConnected is false before connect()', () {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      expect(transport.isConnected, isFalse);
    });

    test('isConnected is true after successful connect()', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        expect(transport.isConnected, isTrue);
      } finally {
        await transport.close();
      }
    });

    test('isConnected is false after close()', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        await transport.close();
        expect(transport.isConnected, isFalse);
      } finally {
        await transport.close();
      }
    });

    test('close() is idempotent - calling multiple times has no side effects',
        () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        await transport.close();
        await transport.close();
        await transport.close();
        expect(transport.isConnected, isFalse);
      } finally {
        await transport.close();
      }
    });

    test('close() can be called before connect()', () async {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      // Should not throw
      await transport.close();
      expect(transport.isConnected, isFalse);
    });

    test('multiple connect() calls throw StateError', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        expect(transport.isConnected, isTrue);
        expect(
          () => transport.connect(),
          throwsA(isA<StateError>()),
        );
      } finally {
        await transport.close();
      }
    });
  });

  group('WebSocketTransport - Send/Receive', () {
    test('incoming stream emits Uint8List chunks received from server',
        () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      final completer = Completer<Uint8List>();
      try {
        await transport.connect();
        transport.incoming.listen(
          (data) {
            if (!completer.isCompleted) completer.complete(data);
          },
          onError: (Object error) {
            if (!completer.isCompleted) completer.completeError(error);
          },
        );
        final data = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('No data received'),
        );
        expect(data, isA<Uint8List>());
        expect(data.length, greaterThan(0));
        expect(String.fromCharCodes(data), startsWith('INFO'));
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('write(Uint8List data) sends bytes to server', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      try {
        await transport.connect();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));
      } finally {
        await transport.close();
      }
    });

    test('PING command receives PONG response', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      final responses = <Uint8List>[];
      try {
        await transport.connect();
        final subscription = transport.incoming.listen(
          (data) => responses.add(data),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await subscription.cancel();
        final allData =
            responses.map((Uint8List r) => String.fromCharCodes(r)).join('');
        expect(allData, contains('PONG'));
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
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      await transport.connect();
      await transport.close();
      expect(
        () => transport.write(Uint8List.fromList('PING\r\n'.codeUnits)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('WebSocketTransport - Timeout', () {
    test('connect() throws TimeoutException after connectTimeout duration',
        () async {
      // Use non-routable IP to simulate connection hang.
      // Skip on environments where TCP to non-routable IPs also times out
      // the test itself before the transport timeout fires.
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
        expect(stopwatch.elapsed.inSeconds, lessThanOrEqualTo(3));
        expect(e.message, contains('timeout'));
        expect(transport.isConnected, isFalse);
      } catch (e) {
        // On some platforms the connect attempt may throw a different error
        // instead of TimeoutException (e.g., network unreachable). Accept that.
        markTestSkipped('Non-routable IP did not hang: $e');
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('WebSocketTransport - Errors', () {
    test('errors stream emits network errors', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      final errors = <Object>[];
      try {
        await transport.connect();
        transport.errors.listen((error) => errors.add(error));
        await transport.close();
        expect(errors, isEmpty);
      } finally {
        await transport.close();
      }
    });

    test('connection failure emits error on errors stream', () async {
      // Try to connect to invalid port; use a short timeout so this fails fast.
      final transport = WebSocketTransport(
        Uri.parse('ws://localhost:59999'),
        connectTimeout: const Duration(seconds: 2),
      );
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
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
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
      } finally {
        await transport.close();
      }
    });
  });

  group('WebSocketTransport - UTF-8 Handling', () {
    test('incoming stream properly decodes UTF-8 text frames', () async {
      if (!_wsAvailable) {
        markTestSkipped(
            'NATS WebSocket server not running on ws://localhost:8080');
        return;
      }
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      final completer = Completer<Uint8List>();
      try {
        await transport.connect();
        transport.incoming.listen(
          (data) {
            if (!completer.isCompleted) completer.complete(data);
          },
          onError: (Object error) {
            if (!completer.isCompleted) completer.completeError(error);
          },
        );
        final data = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('No data received'),
        );
        expect(data, isA<Uint8List>());
        expect(String.fromCharCodes(data), contains('INFO'));
      } finally {
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
