import 'dart:convert';
import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

/// JetStream example demonstrating publishing with headers.
///
/// Requires a NATS server with JetStream enabled.
///
/// ```bash
/// # Start NATS server with JetStream
/// docker run -p 4222:4222 -p 8222:8222 nats:latest -js
///
/// # Run example
/// dart run example/jetstream.dart
/// ```
void main() async {
  // Connect to NATS
  final nc = await NatsConnection.connect(
    'nats://localhost:4222',
    options: const ConnectOptions(name: 'jetstream-example'),
  );

  // Create session data
  final sessionData = {
    'userId': 'user-123',
    'sessionId': 'session-456',
    'startedAt': DateTime.now().toIso8601String(),
  };

  // Publish with headers for JetStream (Nats-Msg-Id for deduplication)
  await nc.publish(
    'TESTS.session_1',
    Uint8List.fromList(jsonEncode(sessionData).codeUnits),
    headers: {
      'Nats-Msg-Id': 'session-001',
      'Content-Type': 'application/json',
    },
  );

  // Get JetStream context
  // (Phase 2 - publish/ack API planned)
  nc.jetStream();

  // Future: Publish with automatic deduplication  // final ack = await js.publish(
  //   'TESTS.session_1',
  //   Uint8List.fromList(jsonEncode(sessionData).codeUnits),
  //   msgId: 'session-001',
  // );
  // print('Published to ${ack.stream}, sequence ${ack.sequence}');

  // Close connection
  await nc.close();
}
