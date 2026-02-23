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
  Subscription subscribe(
    String subject, {
    String? queueGroup,
  }) {
    final sid = _nuid.next();

    final msgStream =
        _parser.messages.where((msg) => msg.sid == sid).asBroadcastStream();

    final sub = Subscription(
      sid: sid,
      subject: subject,
      messages: msgStream,
      queueGroup: queueGroup,
    );

    _subscriptions[sid] = sub;

    // Send SUB command
    final cmd = NatsEncoder.sub(subject, sid, queueGroup: queueGroup);
    _transport.write(cmd).catchError((_) {
      _statusController.add(ConnectionStatus.closed);
    });
    return sub;
  }

  /// Unsubscribe from a subscription.
  Future<void> unsubscribe(Subscription sub) async {
    _subscriptions.remove(sub.sid);
    final cmd = NatsEncoder.unsub(sub.sid);
    await _transport.write(cmd);
  }

  /// Drain: wait for all pending requests to complete, then close.
  Future<void> drain() async {
    _statusController.add(ConnectionStatus.closed);
    // TODO: implement drain
    await close();
  }

  /// Close the connection.
  Future<void> close() async {
    _subscriptions.clear();
    await _transport.close();
    await _parser.close();
    await _statusController.close();
    _statusController.add(ConnectionStatus.closed);
  }

  Future<void> _connect() async {
    _statusController.add(ConnectionStatus.connecting);

    try {
      // Create transport
      _transport = transport_factory.createTransport(_uri);
      await _transport.connect();

      // Create parser
      _parser = NatsParser();

      // Listen for incoming messages
      _transport.incoming.listen((data) {
        _parser.addBytes(data);
      }, onError: (error) {
        _statusController.add(ConnectionStatus.closed);
        _reconnect();
      });
      // Listen for parsed messages
      _parser.messages.listen(_handleMessage);

      // Send CONNECT
      await _sendConnect();

      // Wait for INFO
      _statusController.add(ConnectionStatus.connected);
    } catch (e) {
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
        break;
      case MessageType.ping:
        _respondPong();
        break;
      case MessageType.msg:
      case MessageType.hmsg:
        // Route to subscriptions
        if (msg.sid != null && _subscriptions.containsKey(msg.sid)) {
          // Message will be picked up by the subscription's stream
        }
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
        _statusController.add(ConnectionStatus.connected);
        return;
      } catch (e) {
        attempts++;
      }
    }

    _statusController.add(ConnectionStatus.closed);
  }
}
