/// Flutter Web example demonstrating NATS client over WebSocket.
///
/// This example works on Flutter Web platform using WebSocket transport.
/// Note: NATS server must have WebSocket enabled.
///
/// Requires a NATS server with WebSocket support:
/// ```bash
/// docker run -p 4222:4222 -p 9222:9222 nats:latest --websocket_port 9222 --websocket_no_tls
/// ```
///
/// Run with:
/// ```bash
/// # Build for web
/// flutter build web
/// # Or run in browser
/// flutter run -d chrome
/// ```

import 'dart:async';
import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

void main() async {
  // Connect to NATS using WebSocket transport
  // Note: Use ws:// (not wss://) for local development without TLS
  final nc = await NatsConnection.connect(
    'ws://localhost:9222',
    options: const ConnectOptions(
      name: 'flutter-web-example',
      noEcho: true, // Don't receive our own messages in browser
    ),
  );

  // Subscribe to real-time updates
  final updateSub = await nc.subscribe('updates.>');

  // Listen for updates - in a real app, use setState() or Bloc/Provider
  updateSub.messages.listen((msg) {
    if (msg.payload != null) {
      final data = String.fromCharCodes(msg.payload!);

      // Parse the subject to determine update type
      // Example: updates.user.123 -> type=user, id=123
      final parts = msg.subject.split('.');

      // Handle update - in a real app, update UI state
      // setState(() { /* update state */ });
    }
  });

  // Publish a user action
  await nc.publish(
    'actions.click',
    Uint8List.fromList(
        '{"button":"submit","timestamp":"${DateTime.now().toIso8601String()}"}'
            .codeUnits),
  );

  // Request/reply for fetching data
  final response = await nc.request(
    'data.fetch',
    Uint8List.fromList('{"type":"users"}'.codeUnits),
    timeout: const Duration(seconds: 5),
  );

  if (response.payload != null) {
    final data = String.fromCharCodes(response.payload!);
    // Handle fetched data - update UI
  }

  // Queue group for load balancing (multiple browser tabs/workers)
  final workerSub = await nc.subscribe(
    'tasks.process',
    queueGroup: 'workers',
  );

  workerSub.messages.listen((task) async {
    // Process task
    await Future.delayed(const Duration(milliseconds: 100));

    // Acknowledge completion
    if (task.replyTo != null) {
      await nc.publish(
        task.replyTo!,
        Uint8List.fromList('{"status":"completed"}'.codeUnits),
      );
    }
  });

  // Publish with headers for JetStream
  await nc.publish(
    'EVENTS.browser',
    Uint8List.fromList('{"page":"home","action":"view"}'.codeUnits),
    headers: {
      'Nats-Msg-Id': 'event-${DateTime.now().millisecondsSinceEpoch}',
      'User-Agent': 'Flutter Web',
    },
  );

  // Monitor connection for WebSocket-specific issues
  nc.status.listen((status) {
    switch (status) {
      case ConnectionStatus.connected:
        // WebSocket connected
        break;
      case ConnectionStatus.reconnecting:
        // WebSocket disconnected, attempting reconnect
        // In a real app, show "connecting..." indicator
        break;
      case ConnectionStatus.closed:
        // WebSocket closed - redirect or show error
        break;
      default:
        break;
    }
  });

  // Keep connection alive for the session
  // In a real app, close on page unload or logout

  // Example cleanup (not called in this demo)
  // await nc.drain();
}
