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

  // Reconnection guard to prevent concurrent _reconnect() calls
  bool _isReconnecting = false;

  // Buffer for publishes during reconnection
  final List<_BufferedPublish> _publishBuffer = [];

  // Completer to wait for initial INFO from server (current attempt only)
  Completer<void>? _infoCompleter;
  // Completer to wait for +OK (for verbose mode)
  final Completer<void> _okCompleter = Completer<void>();

  // Timeout for receiving INFO during a reconnect attempt (shorter than initial)
  static const Duration _reconnectInfoTimeout = Duration(seconds: 3);
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

  /// Number of active subscriptions (for testing/debugging).
  int get subscriptionCount => _subscriptions.length;

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
    // If not connected but reconnecting, buffer the publish
    if (!_isConnected && _isReconnecting) {
      _publishBuffer.add(_BufferedPublish(
        subject: subject,
        data: data,
        replyTo: replyTo,
        headers: headers,
      ));
      return;
    }

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
    final sub = await subscribe(replyTo);

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
  Future<Subscription> subscribe(
    String subject, {
    String? queueGroup,
    int? max,
  }) async {
    if (!_isConnected) {
      throw StateError('Not connected');
    }

    final sid = _nuid.next();

    // Create a subscription that owns its internal StreamController
    final sub = Subscription.owned(
      sid: sid,
      subject: subject,
      queueGroup: queueGroup,
      maxMsgs: max,
    );

    _subscriptions[sid] = sub;

    // Send SUB command (await to ensure ordering and delivery)
    final cmd = NatsEncoder.sub(subject, sid, queueGroup: queueGroup);
    await _transport.write(cmd);

    // Send auto-UNSUB if max is specified
    if (max != null) {
      final unsubCmd = NatsEncoder.unsub(sid, maxMsgs: max);
      await _transport.write(unsubCmd);
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
  ///
  /// Implements graceful shutdown:
  /// 1. Stops accepting new subscriptions
  /// 2. Sends UNSUB with max for all active subscriptions
  /// 3. Waits for pending messages to be delivered
  /// 4. Closes the connection
  Future<void> drain() async {
    if (!_isConnected) {
      return; // Already disconnected
    }

    // Emit draining status
    _statusController.add(ConnectionStatus.draining);

    // For each active subscription, send UNSUB to stop receiving new messages
    // This allows in-flight messages to complete
    for (final sub in _subscriptions.values.toList()) {
      if (sub.isActive) {
        // Send UNSUB without removing subscription yet
        // This prevents new messages but allows in-flight ones to arrive
        final cmd = NatsEncoder.unsub(sub.sid);
        await _transport.write(cmd);
      }
    }

    // Wait a short time for in-flight messages to be delivered
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Now close the connection
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
      }, onError: (Object error) {
        // Abort any pending INFO wait so _reconnect() can proceed immediately
        if (_infoCompleter != null && !_infoCompleter!.isCompleted) {
          _infoCompleter!.completeError(error);
        }
        if (_isConnected && !_isReconnecting) {
          _isConnected = false;
          // _reconnect() will emit ConnectionStatus.reconnecting
          _reconnect();
        }
      });
      // Listen for transport errors (triggers reconnection)
      _transport.errors.listen((Object error) {
        // Abort any pending INFO wait so _reconnect() can proceed immediately
        if (_infoCompleter != null && !_infoCompleter!.isCompleted) {
          _infoCompleter!.completeError(error);
        }
        if (_isConnected && !_isReconnecting) {
          _isConnected = false;
          // _reconnect() will emit ConnectionStatus.reconnecting
          _reconnect();
        }
      }); // Listen for parsed protocol messages
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
    // Guard against concurrent reconnection attempts
    if (_isReconnecting) {
      return;
    }
    _isReconnecting = true;

    int attempts = 0;
    Duration delay = _options.reconnectDelay;

    // Emit initial reconnecting status before first attempt
    _statusController.add(ConnectionStatus.reconnecting);

    try {
      while (_options.maxReconnectAttempts == -1 ||
          attempts < _options.maxReconnectAttempts) {
        // Wait before attempting (first attempt uses base delay)
        await Future<void>.delayed(delay);

        try {
          // Create new transport and parser for this attempt
          final newTransport = transport_factory.createTransport(_uri);
          await newTransport.connect();
          final newParser = NatsParser();

          // Use a local completer for this specific attempt's INFO wait.
          // Errors on either the incoming or errors stream abort it.
          final infoCompleter = Completer<void>();

          StreamSubscription<Uint8List>? incomingSub;
          StreamSubscription<Object>? errorsSub;
          StreamSubscription<NatsMessage>? msgSub;

          // Abort helper — errors (transport rejected, socket closed, timeout)
          void abortInfo(Object error) {
            if (!infoCompleter.isCompleted) {
              infoCompleter.completeError(error);
            }
          }

          // Feed parser from incoming bytes
          incomingSub = newTransport.incoming.listen(
            (data) => newParser.addBytes(data),
            onError: abortInfo,
          );

          // Transport-level errors also abort the INFO wait
          errorsSub = newTransport.errors.listen(abortInfo);

          // Wait for INFO message from server
          msgSub = newParser.messages.listen((msg) {
            if (msg.type == MessageType.info && !infoCompleter.isCompleted) {
              infoCompleter.complete();
            }
          });

          try {
            await infoCompleter.future.timeout(_reconnectInfoTimeout,
                onTimeout: () {
              throw TimeoutException(
                  'Timeout waiting for INFO during reconnect');
            });
          } finally {
            // Cancel all temporary INFO-phase subscriptions.
            // Don't await — broadcast stream listener removal is synchronous
            // and we don't want to yield to the event loop mid-setup.
            unawaited(incomingSub.cancel());
            unawaited(errorsSub.cancel());
            unawaited(msgSub.cancel());
          } // Replace the instance transport and parser with the new ones
          _transport = newTransport;
          _parser = newParser;
          // Update infoCompleter instance field (for _handleMessage)
          _infoCompleter = Completer<void>()..complete();

          // Set up permanent message handler
          _parser.messages.listen(_handleMessage);

          // Set up permanent error handler (triggers future reconnects)
          _transport.errors.listen((Object error) {
            if (_infoCompleter != null && !_infoCompleter!.isCompleted) {
              _infoCompleter!.completeError(error);
            }
            if (_isConnected && !_isReconnecting) {
              _isConnected = false;
              _reconnect();
            }
          });

          // Set up permanent incoming handler
          _transport.incoming.listen(
            (data) => _parser.addBytes(data),
            onError: (Object error) {
              if (_infoCompleter != null && !_infoCompleter!.isCompleted) {
                _infoCompleter!.completeError(error);
              }
              if (_isConnected && !_isReconnecting) {
                _isConnected = false;
                _reconnect();
              }
            },
          );

          // Send CONNECT
          await _sendConnect();

          // Replay all active subscriptions (re-send SUB commands)
          for (final sub in _subscriptions.values.toList()) {
            if (sub.isActive) {
              final subCmd = NatsEncoder.sub(
                sub.subject,
                sub.sid,
                queueGroup: sub.queueGroup,
              );
              await _transport.write(subCmd);
            }
          }

          // Flush buffered publish messages
          for (final buffered in _publishBuffer) {
            if (buffered.headers != null ||
                buffered.subject.startsWith('\$JS')) {
              final cmd = NatsEncoder.hpub(
                buffered.subject,
                buffered.data,
                replyTo: buffered.replyTo,
                headers: buffered.headers,
              );
              await _transport.write(cmd);
            } else {
              final cmd = NatsEncoder.pub(
                buffered.subject,
                buffered.data,
                replyTo: buffered.replyTo,
              );
              await _transport.write(cmd);
            }
          }
          _publishBuffer.clear();

          // Connection re-established
          _isConnected = true;
          _isReconnecting = false;
          _statusController.add(ConnectionStatus.connected);
          return;
        } catch (e) {
          attempts++;
          // Exponential backoff: double the delay for next attempt
          delay = Duration(milliseconds: delay.inMilliseconds * 2);

          // Emit reconnecting status for next attempt if more remain
          if (_options.maxReconnectAttempts == -1 ||
              attempts < _options.maxReconnectAttempts) {
            _statusController.add(ConnectionStatus.reconnecting);
          }
        }
      }

      // Max attempts reached — emit closed
      _isConnected = false;
      _isReconnecting = false;
      _statusController.add(ConnectionStatus.closed);
    } catch (e) {
      // Unexpected error — reset guard and close
      _isReconnecting = false;
      _statusController.add(ConnectionStatus.closed);
    }
  }
}

/// Check if a subject matches a wildcard pattern per NATS rules.
///
/// - Exact match: pattern equals subject
/// - `*` matches exactly one token (e.g., `foo.*` matches `foo.bar` but NOT `foo.bar.baz`)
/// Internal class for buffering publish calls during reconnection.
class _BufferedPublish {
  final String subject;
  final Uint8List data;
  final String? replyTo;
  final Map<String, String>? headers;

  _BufferedPublish({
    required this.subject,
    required this.data,
    this.replyTo,
    this.headers,
  });
}

/// - `>` matches one or more trailing tokens (e.g., `foo.>` matches `foo.bar`, `foo.bar.baz`, but NOT `foo` alone)
///
/// This is a pure function with no side effects.
bool matchesSubject(String pattern, String subject) {
  // Exact match
  if (pattern == subject) {
    return true;
  }

  // No wildcards in pattern
  if (!pattern.contains('*') && !pattern.contains('>')) {
    return false;
  }

  final patternTokens = pattern.split('.');
  final subjectTokens = subject.split('.');

  for (int i = 0; i < patternTokens.length; i++) {
    final pToken = patternTokens[i];

    // `>` wildcard: must be the last token, matches one or more remaining tokens
    if (pToken == '>') {
      // `>` must be the last token in the pattern
      if (i != patternTokens.length - 1) {
        return false; // Invalid pattern: `>` must be last
      }
      // Must match at least one remaining token
      return subjectTokens.length > i;
    }

    // `*` wildcard: matches exactly one token
    if (pToken == '*') {
      // Check if there's a corresponding subject token
      if (i >= subjectTokens.length) {
        return false;
      }
      continue;
    }

    // Exact token match required
    if (i >= subjectTokens.length || pToken != subjectTokens[i]) {
      return false;
    }
  }

  // All pattern tokens matched; subject must have same number of tokens
  // (unless `>` was used, which returns early above)
  return patternTokens.length == subjectTokens.length;
}
