# nats_dart

A native Dart/Flutter NATS client with full JetStream and KeyValue support.

## Features

- **Platform Agnostic**: Works on Flutter native (iOS, Android, macOS, Windows, Linux) and Flutter Web
- **Pure Dart Protocol Parser**: Identical wire protocol handling across all platforms
- **Conditional Transports**: TCP for native platforms, WebSocket for web — no code duplication
- **Full JetStream Support**: Streams, consumers, pull and push subscribers, ordered consumers
- **KeyValue Store**: Built on JetStream with watch support
- **JWT & NKey Authentication**: Enterprise-grade security
- **Reconnection Logic**: Automatic reconnection with subscription replay
- **Zero Dependencies**: Uses only `web_socket_channel` (needed for WebSocket)

## Quick Start

### Basic Pub/Sub

```dart
import 'package:nats_dart/nats_dart.dart';

void main() async {
  // Connect to NATS server
  final nc = await NatsConnection.connect('nats://localhost:4222');

  // Subscribe to a subject
  final sub = nc.subscribe('updates');
  sub.messages.listen((msg) {
    print('Received: ${String.fromCharCodes(msg.payload ?? [])}');
  });

  // Publish a message
  await nc.publish('updates', 'Hello, NATS!'.codeUnits as Uint8List);

  // Clean up
  await nc.close();
}
```

### Request/Reply

```dart
// Request
final response = await nc.request('service.action', requestData);
print('Response: ${response.payload}');
```

### JetStream

```dart
final js = nc.jetStream();

// Publish with deduplication
final ack = await js.publish('STREAM_SUBJECT', data, 
  msgId: 'unique-session-id-001');

// Pull consumer
final consumer = await js.consumer('MY_STREAM', 'my-consumer');
final messages = await consumer.fetch(10);
for (final msg in messages) {
  print('Message: ${msg.subject}');
  await msg.ack();
}

// Consume continuously
await for (final msg in consumer.consume(batchSize: 50)) {
  process(msg);
  await msg.ack();
}
```

### KeyValue Store

```dart
// Get KeyValue context
final kv = await js.keyValue('my-bucket');

// Put a value
await kv.put('session:1', sessionData);

// Get a value
final entry = await kv.get('session:1');
print('Session: ${String.fromCharCodes(entry?.value ?? [])}');

// Watch for changes
kv.watch('session:1').listen((entry) {
  print('Session updated: ${entry.value}');
});

// Watch all keys
kv.watchAll().listen((entry) {
  print('${entry.key} = ${entry.value}');
});
```

## Architecture

See [docs/nats_dart_architecture_reference.md](docs/nats_dart_architecture_reference.md) for:

- Complete wire protocol reference (MSG, HMSG, INFO, CONNECT, etc.)
- JetStream protocol and API reference
- Package architecture and directory structure
- Build plan phases
- Test strategy and matrix

## Platform Support

| Platform | Transport | Status |
|----------|-----------|--------|
| Flutter Web | WebSocket | ✅ Supported |
| Flutter iOS | TCP | ✅ Supported |
| Flutter Android | TCP | ✅ Supported |
| Flutter macOS | TCP | ✅ Supported |
| Flutter Windows | TCP | ✅ Supported |
| Flutter Linux | TCP | ✅ Supported |
| Dart VM (server) | TCP/WebSocket | ✅ Supported |

## Server Setup

### Docker (Dev)

```bash
docker run -p 4222:4222 -p 9222:9222 -p 8222:8222 nats:latest \
  -js --websocket_port 9222 --websocket_no_tls
```

### Docker Compose (Integration Testing)

```yaml
services:
  nats:
    image: nats:latest
    command: >
      -js -p 4222 -m 8222
      --websocket_port 9222 --websocket_no_tls
    ports:
      - '4222:4222'   # TCP — native Flutter
      - '9222:9222'   # WebSocket — Flutter Web
      - '8222:8222'   # Monitoring
```

## Authentication

```dart
// Token auth
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(authToken: 'mytoken'),
);

// User/password
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(user: 'alice', pass: 'password'),
);

// JWT + NKey (enterprise)
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    jwt: jwtString,
    nkeyPath: '/path/to/user.nk',
  ),
);
```

## Testing

```bash
# Run all tests
dart test

# Run with coverage
dart test --coverage=coverage
```

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache License 2.0 — See [LICENSE](LICENSE)

## References

- [NATS Protocol Spec](https://docs.nats.io/reference/reference-protocols/nats-protocol)
- [JetStream API Reference](https://docs.nats.io/reference/reference-protocols/nats_api_reference)
- [nats.deno](https://github.com/nats-io/nats.deno) — Reference implementation
- [NATS Documentation](https://docs.nats.io/)
