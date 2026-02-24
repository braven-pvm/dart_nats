import 'dart:async';
import 'dart:typed_data';

/// Abstract transport interface for NATS connections.
///
/// This is the ONLY abstraction point for all network I/O in the NATS client.
/// Implementations handle low-level communication (TCP, WebSocket, etc.) while
/// the protocol parser and encoder work with byte streams identically across
/// all platforms.
///
/// **Platform Independence:**
/// This interface is completely platform-agnostic with NO imports of:
/// - dart:io (native platforms)
/// - dart:html (web browsers)
///
/// Platform-specific implementations are provided via:
/// - TCP transport for native platforms (uses dart:io)
/// - WebSocket transport for web and cross-platform (uses web_socket_channel)
/// - Mock transport for unit testing (no platform dependencies)///
/// High-level modules (NatsConnection, JetStream, KV) depend only on this
/// abstraction, following the Dependency Inversion Principle (SOLID-D).
///
/// **Usage:**
///
/// ```dart
/// // Via factory (recommended - handles platform differences):
/// final transport = createTransport(Uri.parse('nats://localhost:4222'));
///
/// // Or directly with named parameters:
/// final transport = TcpTransport(host: 'localhost', port: 4222);
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
abstract class Transport {
  /// Stream of incoming bytes from the NATS server.
  ///
  /// The stream emits [Uint8List] chunks as they arrive from the network.
  /// Consumers (like protocol parsers) must handle:
  /// - Partial messages (fragmented across multiple chunks)
  /// - Multiple messages in a single chunk
  /// - Binary payloads (not just UTF-8 text)  ///
  /// The stream closes when the connection is terminated.
  Stream<Uint8List> get incoming;

  /// Send bytes to the NATS server.
  ///
  /// Throws [StateError] if the transport is not connected.
  ///
  /// [data] will be flushed to the network before returning.
  Future<void> write(Uint8List data);

  /// Close the connection and release resources.
  ///
  /// Closes both [incoming] and [errors] streams.
  /// Sets [isConnected] to false.
  Future<void> close();

  /// Whether the transport is currently connected.
  ///
  /// Returns `true` after successful [connect] and before [close].
  /// Returns `false` initially and after [close].
  bool get isConnected;

  /// Establish the connection to the server.
  ///
  /// Must be called before [write].
  /// Sets [isConnected] to `true` on success.
  ///
  /// Throws on connection failure (network errors, DNS failures, etc.).
  Future<void> connect();

  /// Stream of errors and disconnection events.
  ///
  /// Emits:
  /// - Network errors (socket failures, TLS errors)
  /// - Protocol errors from the transport layer
  /// - Connection loss events
  ///
  /// The stream closes when the connection is terminated.
  Stream<Object> get errors;
}
