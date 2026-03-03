# NATS Dart Quick Start Guide

Get started with `nats_dart` in 5 minutes. This guide covers basic connection, pub/sub, JetStream, and KeyValue operations.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  nats_dart: ^0.1.0
  web_socket_channel: ^2.4.0
```

Run:

```bash
dart pub get
# or
flutter pub get
```

## Basic Connection

Connect to a NATS server (works on both native and web platforms):

```dart
import 'package:nats_dart/nats_dart.dart';

void main() async {
  // Works on native (TCP) and web (WebSocket)
  final nc = await NatsConnection.connect('nats://localhost:4222');
  
  print('Connected to NATS!');
  
  // Close when done
  await nc.close();
}
```

## Publish and Subscribe

### Subscribe to Messages

```dart
// Subscribe to a subject
final sub = await nc.subscribe('updates.>');

// Listen for messages
await for (final msg in sub.messages) {
  print('Received on ${msg.subject}: ${String.fromCharCodes(msg.payload)}');
}
```

### Publish Messages

```dart
import 'dart:typed_data';

// Publish a message
await nc.publish(
  'updates.user.123',
  Uint8List.fromList('User updated'.codeUnits),
);
```

### Complete Pub/Sub Example

```dart
import 'dart:typed_data';
import 'package:nats_dart/nats_dart.dart';

void main() async {
  final nc = await NatsConnection.connect('nats://localhost:4222');
  
  // Subscribe
  final sub = await nc.subscribe('greetings');
  
  // Publish
  await nc.publish(
    'greetings',
    Uint8List.fromList('Hello, NATS!'.codeUnits),
  );
  
  // Receive
  final msg = await sub.messages.first;
  print('Got: ${String.fromCharCodes(msg.payload)}');
  
  await nc.close();
}
```

## Request/Reply Pattern

Synchronous request/reply communication:

```dart
// Service (responder)
final serviceSub = await nc.subscribe('user.get');
serviceSub.messages.listen((req) async {
  final userId = String.fromCharCodes(req.payload);
  final response = Uint8List.fromList('{"id":"$userId","name":"Alice"}'.codeUnits);
  
  // Reply to the request
  if (req.replyTo != null) {
    await nc.publish(req.replyTo!, response);
  }
});

// Client (requester)
final reply = await nc.request(
  'user.get',
  Uint8List.fromList('123'.codeUnits),
  timeout: Duration(seconds: 5),
);
print('Reply: ${String.fromCharCodes(reply.payload)}');
```

## JetStream Operations

JetStream provides persistence, replay, and advanced messaging patterns.

### Access JetStream Context

```dart
// Get JetStream context
final js = nc.jetStream();
```

### Publish to JetStream Stream

```dart
// Publish with message ID for deduplication
final ack = await js.publish(
  'TESTS.session_1',
  Uint8List.fromList('{"power":285,"hr":148}'.codeUnits),
  msgId: 'session-1-001',
);

print('Published to stream: ${ack.stream}, sequence: ${ack.sequence}');
```

### JetStream Consumer Management

```dart
// Create a pull consumer (Phase 2 - API planned)
// final consumer = await js.consumer('MY_STREAM', 'my-consumer');
// final messages = await consumer.fetch(10);
// for (final msg in messages) {
//   print('Message: ${msg.subject}');
//   await msg.ack();
// }
```

### JetStream Stream Management

```dart
// Manage streams (Phase 2 - API planned)
// final streamInfo = await js.streams.info('MY_STREAM');
// print('Stream: ${streamInfo.config.name}');
```

## KeyValue Store

NATS KeyValue provides a distributed key-value store built on JetStream.

### Access KeyValue Bucket

```dart
// Get KV bucket (Phase 3 - API planned)
// final kv = await js.keyValue('my-bucket');
```

### Put and Get Values

```dart
// Put a value (Phase 3 - API planned)
// await kv.put('session:123', Uint8List.fromList('{"user":"alice"}'.codeUnits));

// Get a value
// final entry = await kv.get('session:123');
// print('Value: ${String.fromCharCodes(entry.value)}');
```

### Watch for Changes

```dart
// Watch a specific key (Phase 3 - API planned)
// kv.watch('session:123').listen((entry) {
//   print('Updated: ${entry.key} = ${String.fromCharCodes(entry.value)}');
// });

// Watch all keys
// kv.watchAll().listen((entry) {
//   print('Change: ${entry.key}');
// });
```

### Delete a Key

```dart
// Delete a key (Phase 3 - API planned)
// await kv.delete('session:123');
```

## Authentication

### Token Authentication

```dart
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    authToken: 'my-secret-token',
  ),
);
```

### Username/Password

```dart
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    user: 'alice',
    pass: 'password123',
  ),
);
```

### JWT + NKey Authentication

```dart
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    jwt: 'eyJhbGciOiJIUzI1NiIs...',  // JWT token
    nkeyPath: '/path/to/nkey.nk',    // NKey seed file
  ),
);
```

## Connection Lifecycle

### Monitor Connection Status

```dart
nc.status.listen((status) {
  switch (status) {
    case ConnectionStatus.connecting:
      print('Connecting...');
    case ConnectionStatus.connected:
      print('Connected!');
    case ConnectionStatus.reconnecting:
      print('Reconnecting...');
    case ConnectionStatus.draining:
      print('Draining...');
    case ConnectionStatus.closed:
      print('Disconnected');
  }
});
```

### Graceful Shutdown with Drain

```dart
// Drain: wait for pending messages, then close
await nc.drain();
```

### Immediate Close

```dart
// Close immediately
await nc.close();
```

## Advanced Topics

### Queue Groups (Load Balancing)

```dart
// Worker 1
final sub1 = await nc.subscribe('tasks', queueGroup: 'workers');

// Worker 2 (same queue group)
final sub2 = await nc.subscribe('tasks', queueGroup: 'workers');

// Only ONE worker receives each message
await nc.publish('tasks', Uint8List.fromList('task data'.codeUnits));
```

### Subject Wildcards

```dart
// Single-token wildcard (*)
final sub1 = await nc.subscribe('user.*.profile');
// Matches: user.123.profile, user.alice.profile
// Does NOT match: user.alice.settings.profile

// Multi-token wildcard (>)
final sub2 = await nc.subscribe('user.>');
// Matches: user.123, user.alice.profile, user.alice.settings.profile
```

### Publish with Headers

```dart
// Publish with headers (for JetStream compatibility)
await nc.publish(
  'orders.new',
  Uint8List.fromList('{"orderId":"123"}'.codeUnits),
  headers: {
    'Nats-Msg-Id': 'order-123-001',
    'Content-Type': 'application/json',
  },
);
```

## Platform Support

The same code runs on all platforms:

| Platform | Transport | Status |
|----------|-----------|--------|
| Flutter Web | WebSocket | ✅ Supported |
| Flutter iOS | TCP | ✅ Supported |
| Flutter Android | TCP | ✅ Supported |
| Flutter macOS | TCP | ✅ Supported |
| Flutter Windows | TCP | ✅ Supported |
| Flutter Linux | TCP | ✅ Supported |
| Dart VM | TCP/WebSocket | ✅ Supported |

## Server Setup

### Docker (Development)

```bash
# Start NATS with JetStream and WebSocket
docker run -p 4222:4222 -p 9222:9222 -p 8222:8222 nats:latest \
  -js --websocket_port 9222 --websocket_no_tls
```

### Verify Server

```bash
# Check server info
curl http://localhost:8222/varz

# Check JetStream status
curl http://localhost:8222/jsz
```

## Next Steps

- ✅ **v0.1.0**: Core pub/sub, request/reply, authentication, reconnection
- 📋 **Phase 2**: Full JetStream implementation (streams, consumers, pull subscriptions)
- 📦 **Phase 3**: KeyValue store implementation (put, get, delete, watch)

For detailed architecture and protocol information, see:
- [Architecture Reference](nats_dart_architecture_reference.md)
- [API Contracts](contracts/)
- [Data Model](data-model.md)
