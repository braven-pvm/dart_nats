import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

/// WebSocket transport using web_socket_channel.
///
/// Works on both Flutter Web and native platforms. Uses the `web_socket_channel`
/// package to provide WebSocket connectivity that works identically on native
/// platforms (iOS, Android, desktop) and web browsers.
///
/// **Platform Note:**
/// This transport works on all platforms without conditional imports.
/// The `web_socket_channel` package abstracts platform differences internally.
///
/// **Usage:**
///
/// ```dart
/// final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
/// await transport.connect();
///
/// transport.incoming.listen((data) {
///   // Handle incoming bytes
/// });
///
/// transport.errors.listen((error) {
///   // Handle connection errors
/// });
///
/// await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));
/// await transport.close();
/// ```
class WebSocketTransport implements Transport {
  final Uri uri;
  final Duration connectTimeout;

  WebSocketChannel? _channel;
  StreamController<Uint8List>? _incomingController;
  StreamController<Object>? _errorsController;
  StreamSubscription<dynamic>? _channelSubscription;
  bool _isConnected = false;
  bool _isClosing = false;

  WebSocketTransport(
    this.uri, {
    this.connectTimeout = const Duration(seconds: 10),
  });
  @override
  Stream<Uint8List> get incoming {
    _incomingController ??= StreamController<Uint8List>.broadcast();
    return _incomingController!.stream;
  }

  @override
  Stream<Object> get errors {
    _errorsController ??= StreamController<Object>.broadcast();
    return _errorsController!.stream;
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) {
      throw StateError('Connection already exists');
    }
    _incomingController = StreamController<Uint8List>.broadcast();
    _errorsController = StreamController<Object>.broadcast();

    try {
      _channel = WebSocketChannel.connect(uri);

      // Enforce connection timeout
      await _channel!.ready.timeout(
        connectTimeout,
        onTimeout: () => throw TimeoutException(
          'WebSocket connection timeout',
          connectTimeout,
        ),
      );

      _channelSubscription = _channel!.stream.listen(
        (message) {
          if (_incomingController?.isClosed == false) {
            if (message is List<int>) {
              // Binary WebSocket frame - convert directly
              _incomingController?.add(Uint8List.fromList(message));
            } else if (message is String) {
              // Text WebSocket frame - decode UTF-8 properly
              _incomingController
                  ?.add(Uint8List.fromList(utf8.encode(message)));
            }
          }
        },
        onError: (Object error) {
          if (_errorsController?.isClosed == false) {
            _errorsController?.add(error);
          }
        },
        onDone: () async {
          _isConnected = false;
          await _incomingController?.close();
          await _errorsController?.close();
        },
      );

      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      if (_errorsController?.isClosed == false) {
        _errorsController?.add(e);
      }
      rethrow;
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!_isConnected || _channel == null) {
      throw StateError('Transport not connected');
    }
    _channel!.sink.add(data);
  }

  @override
  Future<void> close() async {
    // Idempotent: if already closing or closed, just return
    if (_isClosing) {
      return;
    }
    _isClosing = true;

    try {
      // Cancel channel subscription first
      await _channelSubscription?.cancel();
      _channelSubscription = null;

      // Close the channel sink
      await _channel?.sink.close();
      _channel = null;

      // Close stream controllers
      await _incomingController?.close();
      await _errorsController?.close();
      _incomingController = null;
      _errorsController = null;

      _isConnected = false;
    } catch (e) {
      // Swallow errors during close - idempotent behavior
      // Still ensure state is cleaned up
      _channel = null;
      _channelSubscription = null;
      _incomingController = null;
      _errorsController = null;
      _isConnected = false;
    }
  }
}
