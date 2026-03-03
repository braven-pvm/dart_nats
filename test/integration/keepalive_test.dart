/// Integration tests for NATS PING/PONG keepalive using FakeNatsServer.
///
/// Tests:
///   (a) Client sends PING to FakeNatsServer within one pingInterval period
///   (b) maxPingOut exceeded (PONG suppressed) → reconnecting status emitted

import 'dart:async';
import 'dart:io';

import 'package:nats_dart/src/client/connection.dart';
import 'package:nats_dart/src/client/options.dart';
import 'package:test/test.dart';

import 'fake_nats_server.dart';

// ─── FakeNatsServer extension for PONG suppression ───────────────────────────
//
// The existing FakeNatsServer always responds PONG to PING.  For test (b) we
// need to suppress PONG replies.  We do this with a thin wrapper that
// intercepts the server's socket-level output by routing through a custom
// server that never sends PONG.

/// A variant of FakeNatsServer that can be instructed to NOT reply PONG.
///
/// Delegates most logic to raw socket handling (mirrors FakeNatsServer) so we
/// don't need to modify the production class.
class _SilentPongServer {
  ServerSocket? _socket;
  final List<Socket> _clients = [];
  final List<String> _receivedCommands = [];
  final StreamController<String> _commandCtrl =
      StreamController<String>.broadcast();

  int get port => _socket!.port;
  List<String> get receivedCommands => List.unmodifiable(_receivedCommands);
  Stream<String> get commands => _commandCtrl.stream;

  Future<void> start() async {
    _socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket!.listen(_handleClient);
  }

  void _handleClient(Socket client) {
    _clients.add(client);
    const info =
        'INFO {"server_id":"silent","version":"2.0","proto":1,"headers":true,"jetstream":false}\r\n';
    client.write(info);
    client.flush();

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
        final lineBytes = buf.sublist(start, i);
        final line = String.fromCharCodes(lineBytes).trim();
        if (line.isNotEmpty) {
          _receivedCommands.add(line);
          _commandCtrl.add(line);
          // Respond to CONNECT but deliberately NOT to PING (silent PONG)
          if (line.startsWith('CONNECT')) {
            client.write('+OK\r\n');
            client.flush();
          }
          // PING is intentionally ignored (no PONG sent)
        }
        start = i + 2;
      }
    }
    if (start > 0) buf.removeRange(0, start);
  }

  Future<void> waitForN(String command, int n,
      {Duration timeout = const Duration(seconds: 10)}) {
    bool isDone() => _receivedCommands.where((c) => c == command).length >= n;
    if (isDone()) return Future<void>.value();
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
  group('Keepalive: client sends periodic PING', () {
    late FakeNatsServer server;

    setUp(() async {
      server = FakeNatsServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('(a) client sends PING within one pingInterval + margin', () async {
      const interval = Duration(milliseconds: 150);
      const margin = Duration(milliseconds: 500);

      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: ConnectOptions(
          pingInterval: interval,
          maxPingOut: 10, // prevent reconnect during this test
        ),
      );
      addTearDown(nc.close);
      expect(nc.isConnected, isTrue);

      // Wait for the first PING from the client within interval + margin.
      final completer = Completer<void>();
      late StreamSubscription<String> sub;
      sub = server.commands.listen((cmd) {
        if (cmd == 'PING' && !completer.isCompleted) {
          completer.complete();
          sub.cancel();
        }
      });

      // In case PING already arrived before the listener was set up.
      if (server.receivedCommands.contains('PING')) {
        completer.complete();
        await sub.cancel();
      }

      await completer.future.timeout(
        interval + margin,
        onTimeout: () {
          sub.cancel();
          throw TimeoutException(
              'No PING received within ${(interval + margin).inMilliseconds}ms. '
              'Commands: ${server.receivedCommands}');
        },
      );

      expect(server.receivedCommands, contains('PING'));
    });
  });

  group('Keepalive: maxPingOut exceeded triggers reconnecting', () {
    late _SilentPongServer server;

    setUp(() async {
      server = _SilentPongServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test(
        '(b) maxPingOut exceeded when PONG suppressed → reconnecting status emitted',
        () async {
      // pingInterval=100ms, maxPingOut=2.
      // After 2 unanswered PINGs the client checks >= maxPingOut on the THIRD
      // tick and triggers reconnect.
      // So reconnecting should appear within ~3 ticks = ~300ms + margin.

      const interval = Duration(milliseconds: 100);
      const maxPingOut = 2;
      const waitTime = Duration(milliseconds: 1500);

      final statuses = <ConnectionStatus>[];

      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: ConnectOptions(
          pingInterval: interval,
          maxPingOut: maxPingOut,
          // Use maxReconnectAttempts=0 so the reconnect loop closes immediately
          // (no second INFO from silent server).
          maxReconnectAttempts: 0,
          reconnectDelay: const Duration(milliseconds: 50),
        ),
      );
      nc.status.listen(statuses.add);
      expect(nc.isConnected, isTrue);

      // Wait long enough for maxPingOut logic to fire.
      await Future<void>.delayed(waitTime);

      expect(
        statuses,
        anyOf(
          contains(ConnectionStatus.reconnecting),
          contains(ConnectionStatus.closed),
        ),
        reason: 'Expected reconnecting or closed after maxPingOut, '
            'got: $statuses',
      );
    });
  });
}
