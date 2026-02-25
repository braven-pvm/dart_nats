/// Unit tests for PING/PONG keepalive behavior in NatsConnection.
///
/// Uses a minimal in-process TCP server to exercise NatsConnection's
/// ping/pong handling without any external NATS server.
///
/// Tests:
///   (a) Server PING causes client to write PONG immediately
///   (b) Client sends PING periodically; _pendingPings increments observed
///       via the number of PING commands the in-process server receives
///   (c) PONG replies from the server prevent reconnection (_pendingPings resets)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nats_dart/src/client/connection.dart';
import 'package:nats_dart/src/client/options.dart';
import 'package:nats_dart/src/protocol/encoder.dart';
import 'package:test/test.dart';

// ─── Minimal in-process NATS stub server ─────────────────────────────────────

/// A minimal NATS-protocol stub server that only lives in-process.
///
/// Functionality:
///  - Sends INFO on connect
///  - Responds +OK to CONNECT
///  - Responds PONG to PING (configurable)
///  - Tracks all received commands
class _StubServer {
  ServerSocket? _socket;
  final List<Socket> _clients = [];
  final List<String> _receivedCommands = [];
  final StreamController<String> _commandCtrl =
      StreamController<String>.broadcast();

  /// When false, PING commands are NOT answered with PONG.
  bool answerPong = true;

  int get port => _socket!.port;
  List<String> get receivedCommands => List.unmodifiable(_receivedCommands);
  Stream<String> get commands => _commandCtrl.stream;

  Future<void> start() async {
    _socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket!.listen(_handleClient);
  }

  void _handleClient(Socket client) {
    _clients.add(client);
    // Send INFO immediately (NATS protocol requires server to send INFO first)
    const info =
        'INFO {"server_id":"stub","version":"2.0","proto":1,"headers":true,"jetstream":false}\r\n';
    client.write(info);

    final buf = <int>[];
    client.listen(
      (data) {
        buf.addAll(data);
        _parseBuffer(client, buf);
      },
      onDone: () => _clients.remove(client),
      onError: (_) => _clients.remove(client),
    );
  }

  void _parseBuffer(Socket client, List<int> buf) {
    int start = 0;
    for (int i = 0; i < buf.length - 1; i++) {
      if (buf[i] == 13 && buf[i + 1] == 10) {
        final line = utf8.decode(buf.sublist(start, i)).trim();
        if (line.isNotEmpty) {
          _receivedCommands.add(line);
          _commandCtrl.add(line);
          _autoRespond(client, line);
        }
        start = i + 2;
      }
    }
    if (start > 0) buf.removeRange(0, start);
  }

  void _autoRespond(Socket client, String line) {
    if (line.startsWith('CONNECT')) {
      client.write('+OK\r\n');
    } else if (line == 'PING') {
      if (answerPong) client.write('PONG\r\n');
    } else if (line.startsWith('PUB ') ||
        line.startsWith('HPUB ') ||
        line.startsWith('SUB ') ||
        line.startsWith('UNSUB ')) {
      client.write('+OK\r\n');
    }
  }

  /// Send raw data to all connected clients (simulates server push).
  void sendToAll(String data) {
    final bytes = data.codeUnits;
    for (final c in List<Socket>.from(_clients)) {
      c.add(bytes);
    }
  }

  /// Wait until [command] appears in receivedCommands.
  Future<void> waitForCommand(String command,
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (_receivedCommands.contains(command)) return;
    final completer = Completer<void>();
    late StreamSubscription<String> sub;
    sub = _commandCtrl.stream.listen((cmd) {
      if (cmd == command && !completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });
    return completer.future.timeout(timeout, onTimeout: () {
      sub.cancel();
      throw TimeoutException(
          'waitForCommand($command) timed out. Got: $_receivedCommands');
    });
  }

  /// Wait until at least [n] occurrences of [command] appear.
  Future<void> waitForN(String command, int n,
      {Duration timeout = const Duration(seconds: 5)}) async {
    bool isDone() => _receivedCommands.where((c) => c == command).length >= n;
    if (isDone()) return;
    final completer = Completer<void>();
    late StreamSubscription<String> sub;
    sub = _commandCtrl.stream.listen((_) {
      if (isDone() && !completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });
    return completer.future.timeout(timeout, onTimeout: () {
      sub.cancel();
      throw TimeoutException(
          'waitForN($command, $n) timed out. Got: $_receivedCommands');
    });
  }

  Future<void> stop() async {
    for (final c in List<Socket>.from(_clients)) {
      c.destroy();
    }
    _clients.clear();
    await _socket?.close();
    _socket = null;
    if (!_commandCtrl.isClosed) await _commandCtrl.close();
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ── Protocol-level encoder unit tests ──────────────────────────────────────
  group('NatsEncoder PING/PONG commands', () {
    test('NatsEncoder.ping() produces PING\\r\\n', () {
      final bytes = NatsEncoder.ping();
      expect(utf8.decode(bytes), equals('PING\r\n'));
    });

    test('NatsEncoder.pong() produces PONG\\r\\n', () {
      final bytes = NatsEncoder.pong();
      expect(utf8.decode(bytes), equals('PONG\r\n'));
    });
  });

  // ── Behavioural tests via in-process stub server ──────────────────────────
  group('NatsConnection PING/PONG keepalive', () {
    late _StubServer server;

    setUp(() async {
      server = _StubServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('(a) server PING causes client to write PONG immediately', () async {
      // Suppress client's own PING timer so it doesn't interfere.
      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: ConnectOptions(
          pingInterval: const Duration(hours: 1),
          maxPingOut: 2,
        ),
      );
      addTearDown(nc.close);
      expect(nc.isConnected, isTrue);

      // Server sends PING to the client.
      server.sendToAll('PING\r\n');

      // Client must respond with PONG.
      await server.waitForCommand('PONG', timeout: const Duration(seconds: 2));

      expect(server.receivedCommands, contains('PONG'));
    });

    test('(b) _pendingPings increments: client sends PING on each timer tick',
        () async {
      // Short interval so we see at least 2 PINGs quickly.
      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: ConnectOptions(
          pingInterval: const Duration(milliseconds: 100),
          maxPingOut: 20, // prevent reconnect from firing during this test
        ),
      );
      addTearDown(nc.close);
      expect(nc.isConnected, isTrue);

      // Wait for at least 2 PING commands from client (each tick increments
      // _pendingPings by 1 before writing PING).
      await server.waitForN('PING', 2, timeout: const Duration(seconds: 3));

      final pingCount =
          server.receivedCommands.where((c) => c == 'PING').length;
      expect(pingCount, greaterThanOrEqualTo(2),
          reason: 'Expected >= 2 client PINGs (one per timer tick)');
    });

    test(
        '(c) PONG receipt resets _pendingPings: no reconnect while server replies',
        () async {
      // With maxPingOut=2, if _pendingPings ever reaches 2 without reset,
      // NatsConnection triggers reconnect.  If the server always answers PONG,
      // _pendingPings stays at 0 and no reconnect should happen.
      final statuses = <ConnectionStatus>[];

      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: ConnectOptions(
          pingInterval: const Duration(milliseconds: 80),
          maxPingOut: 2,
        ),
      );
      addTearDown(nc.close);
      nc.status.listen(statuses.add);

      expect(nc.isConnected, isTrue);
      // server.answerPong = true by default, so every PONG resets counter.

      // Run through several ping cycles.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(nc.isConnected, isTrue,
          reason: 'Should remain connected when server answers every PONG');
      expect(statuses, isNot(contains(ConnectionStatus.reconnecting)),
          reason: 'Should not reconnect when _pendingPings is reset by PONG');
    });
  });
}
