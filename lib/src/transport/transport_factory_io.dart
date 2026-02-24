import 'tcp_transport.dart';
import 'transport.dart';
import 'websocket_transport.dart';

/// Re-exports platform-specific transport implementations for native platforms.
/// (Definitions are in transport_factory.dart)
export 'tcp_transport.dart';
export 'websocket_transport.dart';
export 'transport.dart';

/// Create transport for native platforms (iOS, Android, macOS, Windows, Linux, Dart server).
/// Prefers TCP for nats:// URIs, uses WebSocket for ws:// and wss:// URIs.
Transport createTransport(Uri uri) {
  if (uri.scheme == 'ws' || uri.scheme == 'wss') {
    return WebSocketTransport(uri);
  }
  // Default to TCP for nats://, nats+tls://, or any other scheme
  return TcpTransport(host: uri.host, port: uri.port);
}
