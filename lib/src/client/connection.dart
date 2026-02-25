import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nats_dart/src/jetstream/jetstream.dart';
import 'package:nats_dart/src/protocol/encoder.dart';
import 'package:nats_dart/src/protocol/message.dart';
import 'package:nats_dart/src/protocol/nuid.dart';
import 'package:nats_dart/src/protocol/parser.dart';
import 'package:nats_dart/src/transport/transport.dart';
import 'package:nats_dart/src/transport/transport_factory.dart'
    as transport_factory;

import 'options.dart';
import 'subscription.dart';

/// Main NATS client connection.
///
/// Handles pub/sub, request/reply, and provides access to JetStream.
class NatsConnection {
  final Uri _uri;
  final ConnectOptions _options;

  late Transport _transport;
  late NatsParser _parser;
  late Nuid _nuid;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final Map<String, Subscription> _subscriptions = {};

  bool _headerSupport = false;
  bool _jetStreamAvailable = false;

  // Connection state flag
  bool _isConnected = false;

  // Completer to wait for initial INFO from server
  Completer<void>? _infoCompleter;

  // Completer to wait for +OK (for verbose mode)
  final Completer<void> _okCompleter = Completer<void>();

  NatsConnection._(this._uri, this._options) {
    _options.validate();
    _nuid = Nuid();
  }

  /// Connect to a NATS server.
  ///
  /// [url] can be in format: `nats://host:port` or `ws://host:port`
  ///
  /// For Flutter Web, `nats://` URIs are automatically converted to `ws://`.
  static Future<NatsConnection> connect(
    String url, {
    ConnectOptions? options,
  }) async {
    final uri = Uri.parse(url);
    final opts = options ?? const ConnectOptions();
    final conn = NatsConnection._(uri, opts);

    await conn._connect();
    return conn;
  }

  /// Stream of connection status changes.
  Stream<ConnectionStatus> get status => _statusController.stream;

  /// Whether the connection is currently active.
  bool get isConnected => _isConnected;

  /// Get the JetStream context for this connection.
  JetStreamContext jetStream({
    String? domain,
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (!_jetStreamAvailable) {
      throw StateError('JetStream is not available on this server');
    }
    return JetStreamContext(this, domain: domain, timeout: timeout);
  }

  /// Publish a message.
  Future<void> publish(
    String subject,
    Uint8List data, {
    String? replyTo,
    Map<String, String>? headers,
  }) async {
    if (!_isConnected) {
      throw StateError('Not connected');
    }
    // Use HPUB if headers or for JetStream subjects
    if (headers != null || subject.startsWith('\$JS')) {
      final cmd =
          NatsEncoder.hpub(subject, data, replyTo: replyTo, headers: headers);
      await _transport.write(cmd);
    } else {
      // Use simple PUB
      final cmd = NatsEncoder.pub(subject, data, replyTo: replyTo);
      await _transport.write(cmd);
    }
  }

  /// Request/reply: send a message and wait for a response.
  Future<NatsMessage> request(
    String subject,
    Uint8List data, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final replyTo = _nuid.inbox();
    final sub = subscribe(replyTo);

    try {
      await publish(subject, data, replyTo: replyTo);

      final msg = await sub.messages.timeout(timeout).first;

      return msg;
    } finally {
      await unsubscribe(sub);
    }
  }

  /// Subscribe to a subject.
  ///
  /// [queueGroup] - optional queue group name for load balancing
  /// [max] - optional max messages before auto-unsubscribe
  Subscription subscribe(
    String subject, {
    String? queueGroup,
    int? max,
  }) {
    if (!_isConnected) {
      throw StateError('Not connected');
    }

    final sid = _nuid.next();

    // Create a subscription that owns its internal StreamController
    final sub = Subscription.owned(
      sid: sid,
      subject: subject,
      queueGroup: queueGroup,
    );

    _subscriptions[sid] = sub;

    // Send SUB command
    final cmd = NatsEncoder.sub(subject, sid, queueGroup: queueGroup);
    _transport.write(cmd).catchError((_) {
      _statusController.add(ConnectionStatus.closed);
    });

    // Send auto-UNSUB if max is specified
    if (max != null) {
      final unsubCmd = NatsEncoder.unsub(sid, maxMsgs: max);
      _transport.write(unsubCmd).catchError((_) {
        // Log error
      });
    }

    return sub;
  }

  /// Unsubscribe from a subscription.
  Future<void> unsubscribe(Subscription sub) async {
    if (!_subscriptions.containsKey(sub.sid)) {
      return; // Already unsubscribed
    }

    _subscriptions.remove(sub.sid);

    // Send UNSUB command to server
    final cmd = NatsEncoder.unsub(sub.sid);
    await _transport.write(cmd);

    // Mark subscription as inactive and close its stream
    sub.close();
  }

  /// Drain: wait for all pending requests to complete, then close.
  Future<void> drain() async {
    _statusController.add(ConnectionStatus.closed);
    // TODO: implement drain
    await close();
  }

  /// Close the connection.
  Future<void> close() async {
    // Emit closed status BEFORE closing the controller
    _statusController.add(ConnectionStatus.closed);

    _isConnected = false;

    // Close all subscriptions
    for (final sub in _subscriptions.values) {
      sub.close();
    }
    _subscriptions.clear();

    await _transport.close();
    await _parser.close();
    await _statusController.close();
  }

  Future<void> _connect() async {
    _statusController.add(ConnectionStatus.connecting);
    _isConnected = false;

    try {
      // Create transport
      _transport = transport_factory.createTransport(_uri);
      await _transport.connect();

      // Create parser
      _parser = NatsParser();

      // Listen for incoming bytes and feed to parser
      _transport.incoming.listen((data) {
        _parser.addBytes(data);
      }, onError: (error) {
        _isConnected = false;
        _statusController.add(ConnectionStatus.closed);
        _reconnect();
      });

      // Listen for parsed protocol messages
      _parser.messages.listen(_handleMessage);

      // Step 1: Wait for INFO from server
      // NATS protocol: server sends INFO first
      _infoCompleter = Completer<void>();

      // Wait for INFO with timeout
      await _infoCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Timeout waiting for INFO from server');
        },
      );

      // Step 2: Send CONNECT to server
      await _sendConnect();

      // Step 3: For verbose mode, wait for +OK
      // (Non-verbose mode doesn't wait for +OK)
      // Default behavior: don't wait for +OK

      // Connection complete
      _isConnected = true;
      _statusController.add(ConnectionStatus.connected);
    } catch (e) {
      _isConnected = false;
      _statusController.add(ConnectionStatus.closed);
      rethrow;
    }
  }

  Future<void> _sendConnect() async {
    final cmd = NatsEncoder.connect(
      version: '0.1.0',
      lang: 'dart',
      headers: true,
      user: _options.user,
      pass: _options.pass,
      token: _options.authToken,
      jwt: _options.jwt,
      name: _options.name,
      noEcho: _options.noEcho,
    );
    await _transport.write(cmd);
  }

  void _handleMessage(NatsMessage msg) {
    switch (msg.type) {
      case MessageType.info:
        _processInfo(msg);
        // Complete the INFO wait
        if (_infoCompleter != null && !_infoCompleter!.isCompleted) {
          _infoCompleter!.complete();
        }
        break;
      case MessageType.ok:
        // Complete the +OK wait (used in verbose mode)
        if (!_okCompleter.isCompleted) {
          _okCompleter.complete();
        }
        break;
      case MessageType.ping:
        _respondPong();
        break;
      case MessageType.msg:
      case MessageType.hmsg:
        // Route message to subscription by SID
        if (msg.sid != null && _subscriptions.containsKey(msg.sid)) {
          final sub = _subscriptions[msg.sid]!;
          sub.addMessage(msg);
        }
        break;
      case MessageType.err:
        // Handle server error
        _statusController.add(ConnectionStatus.closed);
        break;
      default:
        break;
    }
  }

  void _processInfo(NatsMessage msg) {
    if (msg.payload == null) return;

    try {
      final infoJson = jsonDecode(utf8.decode(msg.payload!));
      _headerSupport = infoJson['headers'] == true;
      _jetStreamAvailable = infoJson['jetstream'] == true;

      if (!_headerSupport) {
        throw StateError('Server does not support NATS headers');
      }
    } catch (e) {
      // Log parse error
    }
  }

  void _respondPong() {
    final cmd = NatsEncoder.pong();
    _transport.write(cmd).catchError((e) {
      // Log error
    });
  }

  Future<void> _reconnect() async {
    int attempts = 0;
    while (_options.maxReconnectAttempts == -1 ||
        attempts < _options.maxReconnectAttempts) {
      _statusController.add(ConnectionStatus.reconnecting);
      await Future<void>.delayed(_options.reconnectDelay);

      try {
        // TODO: Implement reconnection with subscription replay
        _isConnected = true;
        _statusController.add(ConnectionStatus.connected);
        return;
      } catch (e) {
        attempts++;
      }
    }

    _isConnected = false;
    _statusController.add(ConnectionStatus.closed);
  }
}
