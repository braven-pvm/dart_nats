// ignore_for_file: avoid_web_libraries_in_flutter

import 'transport.dart';
import 'websocket_transport.dart';

/// Create transport for web platforms (Flutter Web, browser).
/// Coerces nats:// and nats+tls:// to WebSocket URIs (ws://  or wss://).
Transport createTransport(Uri uri) {
  // Coerce scheme to WebSocket for browser
  final wsUri = uri.replace(
    scheme: uri.scheme == 'tls' || uri.scheme == 'nats+tls'
        ? 'wss'
        : uri.scheme == 'nats'
            ? 'ws'
            : uri.scheme,
  );
  return WebSocketTransport(wsUri);
}
