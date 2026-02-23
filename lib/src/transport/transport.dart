import 'dart:typed_data';

/// Abstract transport interface for NATS connections.
///
/// Implementations handle the low-level communication (TCP, WebSocket, etc.)
/// while the protocol parser and encoder work with byte streams identically
/// across all platforms.
abstract class Transport {
  /// Stream of incoming bytes from the server.
  Stream<Uint8List> get incoming;

  /// Send bytes to the server.
  Future<void> write(Uint8List data);

  /// Close the connection.
  Future<void> close();

  /// Whether the transport is currently connected.
  bool get isConnected;

  /// Establish the connection.
  Future<void> connect();

  /// Stream of errors/disconnection events.
  Stream<Object> get errors;
}
