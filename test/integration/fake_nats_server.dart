import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fake NATS server for integration testing reconnection logic.
///
/// Supports minimal protocol:
/// - Sends INFO on connect
/// - Responds +OK to CONNECT, SUB, PUB, UNSUB
/// - Responds PONG to PING
/// - Tracks received commands for verification
///
/// Can simulate disconnects and reject connections for backoff testing.
/// In reject mode, sockets are immediately destroyed (fast reset) so that
/// reconnect attempts are deterministic and measurable.
class FakeNatsServer {
  ServerSocket? _serverSocket;
  final List<Socket> _clients = [];
  final List<String> _receivedCommands = [];
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  /// When false, new connections are immediately destroyed (fast reset).
  bool _acceptConnections = true;

  Stream<String> get commands => _commandsController.stream;
  List<String> get receivedCommands => List.unmodifiable(_receivedCommands);
  bool get isRunning => _serverSocket != null;
  bool get acceptConnections => _acceptConnections;
  set acceptConnections(bool value) => _acceptConnections = value;
  int get port => _serverSocket!.port;

  Future<void> start({int port = 0}) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);

    _serverSocket!.listen((Socket client) {
      if (!_acceptConnections) {
        // Fast reset: immediately destroy the connection so the client
        // gets a deterministic error without waiting for a timeout.
        client.destroy();
        return;
      }
      _clients.add(client);
      _handleClient(client);
    });
  }

  void _handleClient(Socket client) {
    // Send INFO
    final info =
        'INFO {"server_id":"fake","version":"1.0","proto":1,"headers":true,"jetstream":true}\r\n';
    client.write(info);
    client.flush();

    final List<int> buffer = [];
    client.listen(
      (List<int> data) {
        buffer.addAll(data);
        _parseBuffer(client, buffer);
      },
      onDone: () {
        _clients.remove(client);
      },
      onError: (Object error) {
        _clients.remove(client);
      },
    );
  }

  void _parseBuffer(Socket client, List<int> buffer) {
    int start = 0;
    for (int i = 0; i < buffer.length - 1; i++) {
      if (buffer[i] == 13 && buffer[i + 1] == 10) {
        // \r\n
        final lineBytes = buffer.sublist(start, i);
        final line = utf8.decode(lineBytes).trim();
        if (line.isNotEmpty) {
          // ignore: avoid_print
          print('[FakeNatsServer] received: $line');
          _receivedCommands.add(line);
          _commandsController.add(line);
        }
        // Respond to commands
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
        start = i + 2;
      }
    }
    if (start > 0) {
      buffer.removeRange(0, start);
    }
  }

  /// Disconnect all currently connected clients.
  ///
  /// Uses [Socket.destroy] for an immediate hard close so that
  /// the client side sees the connection drop right away.
  Future<void> disconnectClients() async {
    for (final client in List<Socket>.from(_clients)) {
      client.destroy();
    }
    // Give the OS a moment to flush the disconnect events.
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  Future<void> stop() async {
    await disconnectClients();
    await _serverSocket?.close();
    _serverSocket = null;
    if (!_commandsController.isClosed) {
      await _commandsController.close();
    }
    _receivedCommands.clear();
  }

  void clearReceivedCommands() {
    _receivedCommands.clear();
  }
}
