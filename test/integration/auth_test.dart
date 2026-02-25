/// Integration tests for NATS authentication.
///
/// Tests token auth, user/pass auth, invalid-credentials rejection,
/// and (skipped) NKey/JWT auth using an AuthenticatedFakeNatsServer
/// that validates credentials in the CONNECT JSON.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nats_dart/src/client/connection.dart';
import 'package:nats_dart/src/client/options.dart';
import 'package:test/test.dart';

/// A NATS test server that requires authentication.
///
/// Sends `auth_required=true` and a fixed nonce in the INFO greeting,
/// then validates the CONNECT JSON credentials.
///
/// - Token auth: checks `auth_token` field matches [expectedToken]
/// - User/pass auth: checks `user` and `pass` fields match [expectedUser]/[expectedPass]
/// - Invalid credentials: writes `-ERR 'Authorization Violation'` and destroys the socket
class AuthenticatedFakeNatsServer {
  ServerSocket? _serverSocket;
  final List<Socket> _clients = [];
  final List<String> _receivedCommands = [];
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  final String nonce;
  final String? expectedToken;
  final String? expectedUser;
  final String? expectedPass;

  AuthenticatedFakeNatsServer({
    this.nonce = 'testNonce123',
    this.expectedToken,
    this.expectedUser,
    this.expectedPass,
  });

  Stream<String> get commands => _commandsController.stream;
  List<String> get receivedCommands => List.unmodifiable(_receivedCommands);
  int get port => _serverSocket!.port;

  Future<void> start({int port = 0}) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _serverSocket!.listen((Socket client) {
      _clients.add(client);
      _handleClient(client);
    });
  }

  void _handleClient(Socket client) {
    // Announce that auth is required, include a nonce for NKey/JWT
    final infoJson = jsonEncode({
      'server_id': 'fake-auth',
      'version': '1.0',
      'proto': 1,
      'headers': true,
      'jetstream': true,
      'auth_required': true,
      'nonce': nonce,
    });
    client.write('INFO $infoJson\r\n');
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
          print('[AuthFakeNatsServer] received: $line');
          _receivedCommands.add(line);
          _commandsController.add(line);
        }

        if (line.startsWith('CONNECT ')) {
          _handleConnect(client, line);
        } else if (line.startsWith('PING')) {
          client.write('PONG\r\n');
        } else if (line.startsWith('SUB ') ||
            line.startsWith('UNSUB ') ||
            line.startsWith('PUB ') ||
            line.startsWith('HPUB ')) {
          client.write('+OK\r\n');
        }
        start = i + 2;
      }
    }
    if (start > 0) {
      buffer.removeRange(0, start);
    }
  }

  void _handleConnect(Socket client, String connectLine) {
    // Extract the JSON body after 'CONNECT '
    final jsonBody = connectLine.substring('CONNECT '.length).trim();
    Map<String, dynamic> connectJson;
    try {
      connectJson = jsonDecode(jsonBody) as Map<String, dynamic>;
    } catch (_) {
      _reject(client, 'Authorization Violation');
      return;
    }

    final bool authorized = _checkCredentials(connectJson);
    if (authorized) {
      client.write('+OK\r\n');
    } else {
      _reject(client, 'Authorization Violation');
    }
  }

  bool _checkCredentials(Map<String, dynamic> connectJson) {
    if (expectedToken != null) {
      return connectJson['auth_token'] == expectedToken;
    }
    if (expectedUser != null) {
      return connectJson['user'] == expectedUser &&
          connectJson['pass'] == expectedPass;
    }
    // No credentials expected — reject everything
    return false;
  }

  void _reject(Socket client, String reason) {
    client.write('-ERR \'$reason\'\r\n');
    client.flush();
    Future<void>.delayed(const Duration(milliseconds: 10)).then((_) {
      client.destroy();
      _clients.remove(client);
    });
  }

  Future<void> stop() async {
    for (final client in List<Socket>.from(_clients)) {
      client.destroy();
    }
    await _serverSocket?.close();
    _serverSocket = null;
    if (!_commandsController.isClosed) {
      await _commandsController.close();
    }
    _receivedCommands.clear();
  }
}

void main() {
  group('Token Authentication (FR-8.1)', () {
    late AuthenticatedFakeNatsServer server;

    setUp(() async {
      server = AuthenticatedFakeNatsServer(
        nonce: 'testNonce123',
        expectedToken: 'secret-token',
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('token auth succeeds when correct authToken is provided', () async {
      // Subscribe to commands stream before connecting
      final connectCmdFuture = server.commands
          .firstWhere((cmd) => cmd.startsWith('CONNECT '))
          .timeout(const Duration(seconds: 5));

      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: const ConnectOptions(authToken: 'secret-token'),
      );

      expect(nc.isConnected, isTrue);

      // Wait for CONNECT command to be received by server (async parsing)
      final connectCmd = await connectCmdFuture;
      final jsonBody = connectCmd.substring('CONNECT '.length).trim();
      final parsed = jsonDecode(jsonBody) as Map<String, dynamic>;
      expect(parsed['auth_token'], equals('secret-token'));

      await nc.close();
    });
    test('connect() throws when auth_required=true and no credentials provided',
        () async {
      await expectLater(
        NatsConnection.connect(
          'nats://127.0.0.1:${server.port}',
          options: const ConnectOptions(), // No credentials
        ).timeout(const Duration(seconds: 5)),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Authentication required'),
        )),
      );
    });
  });

  group('User/Pass Authentication (FR-8.2)', () {
    late AuthenticatedFakeNatsServer server;

    setUp(() async {
      server = AuthenticatedFakeNatsServer(
        nonce: 'testNonce123',
        expectedUser: 'alice',
        expectedPass: 'p@ssw0rd',
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('user/pass auth succeeds when correct credentials are provided',
        () async {
      // Subscribe to commands stream before connecting
      final connectCmdFuture = server.commands
          .firstWhere((cmd) => cmd.startsWith('CONNECT '))
          .timeout(const Duration(seconds: 5));

      final nc = await NatsConnection.connect(
        'nats://127.0.0.1:${server.port}',
        options: const ConnectOptions(user: 'alice', pass: 'p@ssw0rd'),
      );

      expect(nc.isConnected, isTrue);

      // Wait for CONNECT command to be received by server (async parsing)
      final connectCmd = await connectCmdFuture;
      final jsonBody = connectCmd.substring('CONNECT '.length).trim();
      final parsed = jsonDecode(jsonBody) as Map<String, dynamic>;
      expect(parsed['user'], equals('alice'));
      expect(parsed['pass'], equals('p@ssw0rd'));

      await nc.close();
    });
    test('connect() throws when invalid user/pass credentials are provided',
        () async {
      // The server rejects wrong credentials by sending -ERR and closing.
      // NatsConnection should propagate a failure (error or timeout).
      await expectLater(
        NatsConnection.connect(
          'nats://127.0.0.1:${server.port}',
          options: const ConnectOptions(user: 'wrong', pass: 'bad'),
        ).timeout(const Duration(seconds: 5)),
        anyOf(
          throwsA(isA<StateError>()),
          throwsA(isA<TimeoutException>()),
          throwsA(isA<Exception>()),
          throwsA(isA<Error>()),
        ),
      );
    });
  });

  group('Invalid Credentials Rejection', () {
    late AuthenticatedFakeNatsServer server;

    setUp(() async {
      server = AuthenticatedFakeNatsServer(
        nonce: 'testNonce123',
        expectedToken: 'correct-token',
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('connect() fails when wrong token is provided', () async {
      // The server sends -ERR and closes the connection.
      // The client should throw rather than silently succeed.
      await expectLater(
        NatsConnection.connect(
          'nats://127.0.0.1:${server.port}',
          options: const ConnectOptions(authToken: 'wrong-token'),
        ).timeout(const Duration(seconds: 5)),
        anyOf(
          throwsA(isA<StateError>()),
          throwsA(isA<TimeoutException>()),
          throwsA(isA<Exception>()),
          throwsA(isA<Error>()),
        ),
      );
    });
  });

  group('NKey/JWT Authentication (FR-8.3/FR-8.4)', () {
    test(
      'NKey signing is not yet implemented — stub throws UnimplementedError',
      () async {
        // This test intentionally does nothing:
        // NKey signing is stubbed and will throw UnimplementedError.
        // Full test coverage will be added once Ed25519 signing is implemented.
      },
      skip: 'NKey signing not yet implemented — '
          'returns UnimplementedError per FR-8.3/FR-8.4 skeleton',
    );
  });
}
