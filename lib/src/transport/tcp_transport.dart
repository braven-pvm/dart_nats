// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport.dart';

/// TCP transport using dart:io Socket.
///
/// Supports both regular TCP and TLS connections. This is the primary
/// transport for native platforms (Windows, macOS, Linux, iOS, Android).
///
/// **Platform Note:**
/// This file is one of the ONLY files in the project that may import dart:io
/// per the project constitution's Pure Dart policy. Platform differences are
/// handled exclusively via conditional imports in transport_factory.dart.
///
/// **Usage:**
///
/// ```dart
/// final transport = TcpTransport(host: 'localhost', port: 4222);
/// await transport.connect();///
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
class TcpTransport implements Transport {
  final String host;
  final int port;
  final Duration connectTimeout;
  final bool _useTls;

  Socket? _socket;
  StreamController<Uint8List>? _incomingController;
  StreamController<Object>? _errorsController;
  StreamSubscription<Uint8List>? _socketSubscription;
  bool _isConnected = false;
  bool _isClosing = false;

  TcpTransport({
    required this.host,
    required this.port,
    this.connectTimeout = const Duration(seconds: 10),
    bool useTls = false,
  }) : _useTls = useTls;
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
      throw SocketException('Connection already exists');
    }
    _incomingController = StreamController<Uint8List>.broadcast();
    _errorsController = StreamController<Object>.broadcast();

    try {
      if (_useTls) {
        _socket =
            await SecureSocket.connect(host, port, timeout: connectTimeout);
      } else {
        _socket = await Socket.connect(host, port, timeout: connectTimeout);
      }
      _socketSubscription = _socket!.listen(
        (data) {
          if (_incomingController?.isClosed == false) {
            _incomingController?.add(Uint8List.fromList(data));
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
    if (!_isConnected || _socket == null) {
      throw StateError('Transport not connected');
    }
    _socket!.add(data);
    await _socket!.flush();
  }

  @override
  Future<void> close() async {
    // Idempotent: if already closing or closed, just return
    if (_isClosing) {
      return;
    }
    _isClosing = true;

    try {
      // Cancel socket subscription first
      await _socketSubscription?.cancel();
      _socketSubscription = null;

      // Close the socket
      await _socket?.close();
      _socket = null;

      // Close stream controllers
      await _incomingController?.close();
      await _errorsController?.close();
      _incomingController = null;
      _errorsController = null;

      _isConnected = false;
    } catch (e) {
      // Swallow errors during close - idempotent behavior
      // Still ensure state is cleaned up
      _socket = null;
      _socketSubscription = null;
      _incomingController = null;
      _errorsController = null;
      _isConnected = false;
    }
  }
}
