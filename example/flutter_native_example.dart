/// Flutter native example demonstrating NATS client usage.
///
/// This example works on Flutter native platforms (iOS, Android, macOS,
/// Windows, Linux) using TCP transport.
///
/// Requires a NATS server running at localhost:4222:
/// ```bash
/// docker run -p 4222:4222 nats:latest
/// ```
///
/// Run with:
/// ```bash
/// dart run example/flutter_native_example.dart
/// ```

import 'dart:async';
import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

void main() async {
  // Connect to NATS using TCP transport (native platforms)
  final nc = await NatsConnection.connect(
    'nats://localhost:4222',
    options: const ConnectOptions(
      name: 'flutter-native-example',
      maxReconnectAttempts: 5,
      reconnectDelay: Duration(seconds: 2),
    ),
  );

  // Subscribe with wildcard pattern
  final sub = await nc.subscribe('events.>');

  // Listen for messages
  sub.messages.listen((msg) {
    final payload =
        msg.payload != null ? String.fromCharCodes(msg.payload!) : '<empty>';
    // Handle event - in a real app, update UI state
  });

  // Publish an event
  await nc.publish(
    'events.user.created',
    Uint8List.fromList('{"userId":"123","name":"Alice"}'.codeUnits),
  );

  // Request/reply pattern
  final serviceSub = await nc.subscribe('users.get');
  serviceSub.messages.listen((req) async {
    if (req.replyTo != null) {
      // Fetch user from database (simulated)
      final userData =
          Uint8List.fromList('{"id":"123","name":"Alice"}'.codeUnits);

      // Send response
      await nc.publish(req.replyTo!, userData);
    }
  });

  // Make a request to the service
  final response = await nc.request(
    'users.get',
    Uint8List.fromList('123'.codeUnits),
    timeout: const Duration(seconds: 2),
  );

  if (response.payload != null) {
    final user = String.fromCharCodes(response.payload!);
    // Handle response - in a real app, update UI state
  }

  // Publish with headers for JetStream (deduplication)
  await nc.publish(
    'ORDERS.new',
    Uint8List.fromList('{"orderId":"456"}'.codeUnits),
    headers: {
      'Nats-Msg-Id': 'order-456-001',
      'Content-Type': 'application/json',
    },
  );

  // Get JetStream context (Phase 2 - pull consumer API planned)
  final js = nc.jetStream();
  // Future: final consumer = await js.consumer('ORDER_STREAM', 'my-durable');

  // Monitor connection status
  nc.status.listen((status) {
    // Handle status changes - in a real app, update UI
    switch (status) {
      case ConnectionStatus.connected:
        // Reconnected
        break;
      case ConnectionStatus.reconnecting:
        // Connection lost, attempting reconnect
        break;
      case ConnectionStatus.closed:
        // Connection closed
        break;
      default:
        break;
    }
  });

  // Graceful shutdown
  await nc.drain();
}
