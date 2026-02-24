import 'dart:async';
import 'dart:typed_data';

import 'transport.dart';

/// Mock transport implementation for unit testing.
///
/// Provides test helpers for simulating server responses and network failures:
/// - [pumpData] injects data into the incoming stream
/// - [pumpError] simulates network/protocol errors
/// - [writtenBytes] records all data sent via [write]
/// - [setConnected] controls the connection state for testing disconnect scenarios
class MockTransport implements Transport {
  late StreamController<Uint8List> _incomingController;
  late StreamController<Object> _errorsController;
  final List<Uint8List> _writtenBytes = [];
  bool _isConnected = false;

  MockTransport() {
    _incomingController = StreamController<Uint8List>.broadcast(sync: true);
    _errorsController = StreamController<Object>.broadcast(sync: true);
  }

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  Stream<Object> get errors => _errorsController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    _isConnected = true;
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!_isConnected) {
      throw StateError('Transport not connected');
    }
    _writtenBytes.add(Uint8List.fromList(data));
  }

  @override
  Future<void> close() async {
    _isConnected = false;
    await _incomingController.close();
    await _errorsController.close();
  }

  /// Inject data into the incoming stream to simulate server responses.
  void pumpData(Uint8List data) {
    if (!_incomingController.isClosed) {
      _incomingController.add(data);
    }
  }

  /// Inject an error into the errors stream to simulate network failures.
  void pumpError(Object error) {
    if (!_errorsController.isClosed) {
      _errorsController.add(error);
    }
  }

  /// Control the connection state for testing disconnect scenarios.
  void setConnected(bool connected) {
    _isConnected = connected;
  }

  /// Get all bytes written via [write] for assertion in tests.
  List<Uint8List> get writtenBytes => List.unmodifiable(_writtenBytes);

  /// Clear the recorded written bytes.
  void clearWrittenBytes() {
    _writtenBytes.clear();
  }
}
