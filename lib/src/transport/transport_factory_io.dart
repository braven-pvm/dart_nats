// ignore: avoid_web_libraries_in_flutter
import 'dart:io';

import 'tcp_transport.dart';
import 'transport.dart';
import 'websocket_transport.dart';

/// Create transport for native platforms (iOS, Android, macOS, Windows, Linux, Dart server).
/// Prefers TCP for nats:// URIs, uses WebSocket for ws:// and wss:// URIs.
Transport createTransport(Uri uri) {
  if (uri.scheme == 'ws' || uri.scheme == 'wss') {
    return WebSocketTransport(uri);
  }
  // Default to TCP for nats://, nats+tls://, or any other scheme
  return TcpTransport(uri.host, uri.port);
}
