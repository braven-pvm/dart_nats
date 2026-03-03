import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

/// Basic example demonstrating connection, pub/sub, and request/reply.
///
/// Requires a NATS server running at localhost:4222.
///
/// ```bash
/// # Start NATS server with Docker
/// docker run -p 4222:4222 -p 8222:8222 nats:latest
///
/// # Run example
/// dart run example/basic.dart
/// ```
void main() async {
  // Basic example: connect, pub/sub, request/reply

  // Connect to NATS
  final nc = await NatsConnection.connect('nats://localhost:4222');

  // Subscribe to a subject
  final sub = await nc.subscribe('hello');
  sub.messages.listen((msg) {
    if (msg.payload != null) {
      // Received message
    }
  });

  // Publish a message
  await nc.publish(
    'hello',
    Uint8List.fromList('Hello, NATS!'.codeUnits),
  );

  // Request/reply
  final response = await nc.request(
    'help',
    Uint8List.fromList('need data'.codeUnits),
    timeout: const Duration(seconds: 2),
  );

  if (response.payload != null) {
    // Process response
  }

  // Clean disconnect
  await nc.close();
}
