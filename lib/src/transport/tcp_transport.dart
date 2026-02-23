// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport.dart';

/// TCP transport using dart:io Socket.
/// Supports both regular TCP and TLS connections.
class TcpTransport implements Transport {
  final String host;
  final int port;
  final bool _useTls;

  late Socket _socket;
  late StreamController<Uint8List> _incomingController;
  late StreamController<Object> _errorsController;

  TcpTransport(this.host, this.port, {bool useTls = false}) : _useTls = useTls;

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  Stream<Object> get errors => _errorsController.stream;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {
    _incomingController = StreamController<Uint8List>.broadcast();
    _errorsController = StreamController<Object>.broadcast();

    try {
      if (_useTls) {
        _socket = await SecureSocket.connect(host, port);
      } else {
        _socket = await Socket.connect(host, port);
      }

      _socket.listen(
        (data) => _incomingController.add(Uint8List.fromList(data)),
        onError: (Object error) => _errorsController.add(error),
        onDone: () async {
          await _incomingController.close();
          await _errorsController.close();
        },
      );
    } catch (e) {
      _errorsController.add(e);
      rethrow;
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!isConnected) {
      throw StateError('Transport not connected');
    }
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    await _socket.close();
    await _incomingController.close();
    await _errorsController.close();
  }
}
