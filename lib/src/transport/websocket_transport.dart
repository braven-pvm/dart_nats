import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

/// WebSocket transport using web_socket_channel.
/// Works on both Flutter Web and native platforms.
class WebSocketTransport implements Transport {
  final Uri uri;

  late WebSocketChannel _channel;
  late StreamController<Uint8List> _incomingController;
  late StreamController<Object> _errorsController;

  WebSocketTransport(this.uri);

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
      _channel = WebSocketChannel.connect(uri);

      _channel.stream.listen(
        (message) {
          if (message is List<int>) {
            _incomingController.add(Uint8List.fromList(message));
          } else if (message is String) {
            _incomingController.add(Uint8List.fromList(message.codeUnits));
          }
        },
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
    _channel.sink.add(data);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close();
    await _incomingController.close();
    await _errorsController.close();
  }
}
