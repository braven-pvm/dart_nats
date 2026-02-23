# Quick Start Guide: NATS Foundation & Core Client

**Purpose**: Help developers get started with nats_dart in 5 minutes  
**Phase**: 1 (Design)

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  nats_dart: ^1.0.0
  web_socket_channel: ^2.4.0
```

Run:
```bash
dart pub get
# or
flutter pub get
```

---

## 5-Minute Example: Pub/Sub

### 1. Import

```dart
import 'package:nats_dart/nats_dart.dart';
import 'dart:typed_data';
```

### 2. Connect

```dart
// Works on native (TCP) and web (WebSocket) — same code!
final nc = await NatsConnection.connect('nats://localhost:4222');
print('Connected!');
```

### 3. Subscribe

```dart
// Listen to messages
final sub = nc.subscribe('updates.>');

// Process messages
await for (final msg in sub.messages) {
  print('Received on ${msg.subject}: ${String.fromCharCodes(msg.payload)}');
}
```

### 4. Publish

```dart
// Publish a message
await nc.publish(
  'updates.user.123',
  Uint8List.fromList('User updated'.codeUnits),
);
```

### 5. Cleanup

```dart
// Unsubscribe
await nc.unsubscribe(sub);

// Close connection
await nc.close();
```

---

## Request/Reply Pattern

**Use when**: You need synchronous request/reply communication (like RPC)

```dart
// Service (listens for requests)
final sub = nc.subscribe('user.get');
await for (final req in sub.messages) {
  final userId = String.fromCharCodes(req.payload);
  final response = Uint8List.fromList('{"id":"$userId","name":"Alice"}'.codeUnits);
  await nc.publish(req.replyTo!, response);
}

// Client (sends request, waits for reply)
final reply = await nc.request(
  'user.get',
  Uint8List.fromList('123'.codeUnits),
  timeout: Duration(seconds: 5),
);
print('Reply: ${String.fromCharCodes(reply.payload)}');
```

---

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

### NKey Authentication

```dart
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    nkeyPath: '/path/to/nkey.nk',  // NKey seed file
  ),
);
```

### JWT Authentication

```dart
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    jwt: 'eyJhbGciOiJIUzI1NiIs...',  // JWT token
    nkeyPath: '/path/to/nkey.nk',    // NKey to sign nonce
  ),
);
```

---

## Monitoring Connection Status

```dart
// Listen for connection status changes
nc.status.listen((status) {
  switch (status) {
    case ConnectionStatus.connecting:
      print('🔄 Connecting...');
    case ConnectionStatus.connected:
      print('✅ Connected!');
    case ConnectionStatus.reconnecting:
      print('🔄 Reconnecting...');
    case ConnectionStatus.closed:
      print('❌ Disconnected');
  }
});
```

---

## Handling Reconnection

**Automatic Reconnection**: By default, the client automatically reconnects on network failure.

```dart
// Configure reconnection behavior
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    maxReconnectAttempts: -1,        // Infinite reconnection (default)
    reconnectDelay: Duration(seconds: 2), // Wait 2s between attempts
    maxPingOut: 2,                   // Reconnect after 2 unresponded PINGs
  ),
);

// Subscribe before reconnection to auto-restore after network recovery
final sub = nc.subscribe('updates.>');

// Even if network drops, subscriptions are restored automatically
await for (final msg in sub.messages) {
  print('Received: ${msg.subject}');
}
```

---

## Queue Groups (Load Balancing)

**Use when**: Multiple subscribers should share a workload.

```dart
// Worker 1
final sub1 = nc.subscribe(
  'tasks.process',
  queueGroup: 'workers',
);

// Worker 2 (same queue group)
final sub2 = nc.subscribe(
  'tasks.process',
  queueGroup: 'workers',
);

// Publisher sends one message per request
await nc.publish(
  'tasks.process',
  Uint8List.fromList('task data'.codeUnits),
);

// Only ONE worker receives the message (round-robin)
await for (final msg in sub1.messages) {
  print('Worker 1 received');
}

await for (final msg in sub2.messages) {
  print('Worker 2 got this one (not both!)');
}
```

---

## Subject Wildcards

**Subjects support pattern matching:**

```dart
// Single-token wildcard (*)
final sub1 = nc.subscribe('user.*.profile');  // matches user.123.profile, user.alice.profile
// Does NOT match: user.alice.settings.profile

// Multi-token wildcard (>)
final sub2 = nc.subscribe('user.>');  // matches user.123, user.alice.profile, user.alice.settings.profile
// Matches everything under 'user'

// Publish to specific subject
await nc.publish('user.alice.profile', Uint8List.fromList('data'.codeUnits));  // Matched by both sub1 and sub2
await nc.publish('user.alice.settings', Uint8List.fromList('data'.codeUnits));  // Matched by sub2 only
```

---

## Working with Headers (Phase 2+)

**Note**: Phase 1 supports publishing with headers (for JetStream compatibility), but header processing is primarily Phase 2+.

```dart
// Publish with headers (for JetStream)
await nc.publish(
  'orders.new',
  Uint8List.fromList('{"orderId":"123","total":99.99}'.codeUnits),
  headers: {
    'Nats-Msg-Id': 'order-123-001',  // Deduplication ID (Phase 2: JetStream)
    'Content-Type': 'application/json',
  },
);

// Receiving messages with headers
final sub = nc.subscribe('orders.>');
await for (final msg in sub.messages) {
  if (msg.headers != null) {
    final msgId = msg.header('Nats-Msg-Id');
    print('Message ID: $msgId');
  }
}
```

---

## Error Handling

```dart
try {
  final nc = await NatsConnection.connect('nats://localhost:4222');
  
  final sub = nc.subscribe('updates');
  await for (final msg in sub.messages) {
    try {
      // Process message
    } catch (e) {
      print('Error processing message: $e');
    }
  }
  
  await nc.close();
} on SocketException catch (e) {
  print('Connection failed: $e');
  // Handle specific connection error
} catch (e) {
  print('Unexpected error: $e');
}
```

---

## Running on Flutter Web vs Native

**The same code works on both!** Here's how it automatically adapts:

```dart
// This single line works on:
// - Flutter native (iOS, Android): Uses TCP
// - Flutter web: Uses WebSocket
// - Dart CLI: Uses TCP
final nc = await NatsConnection.connect('nats://localhost:4222');
```

**Behind the scenes**:
- **Native**: `nats://` → TCP on port 4222 (`:4222`)
- **Web**: `nats://` → WebSocket on port 9222 (`:9222` or configured websocket_port)

If your web server is on a different host, configure the server accordingly:

```dart
// Web server at example.com port 9222
final nc = await NatsConnection.connect('nats://example.com:9222');
```

---

## Docker Quick Start

For local testing:

```bash
# Start NATS with headers and WebSocket support
docker run -p 4222:4222 -p 9222:9222 -p 8222:8222 nats:latest \
  -js --websocket_port 9222 --websocket_no_tls
```

Then connect with:
```dart
final nc = await NatsConnection.connect('nats://localhost:4222');
```

Verify the server is running:
```bash
curl http://localhost:8222/varz | jq '.headers'  # Should be true
```

---

## Next Steps

- ✅ **Phase 1**: Pub/sub, request/reply, reconnection, authentication (this guide)
- 📋 **Phase 2**: JetStream streams, consumers, pull subscriptions (coming next)
- 📦 **Phase 3**: KeyValue store, production optimizations (coming later)

---

## Full Example: Flutter App

```dart
import 'package:flutter/material.dart';
import 'package:nats_dart/nats_dart.dart';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late NatsConnection _nc;
  String _status = 'Disconnected';
  List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _connectToNats();
  }

  Future<void> _connectToNats() async {
    try {
      _nc = await NatsConnection.connect('nats://localhost:4222');
      
      _nc.status.listen((status) {
        setState(() {
          _status = status.toString();
        });
      });
      
      final sub = _nc.subscribe('chat.>');
      
      await for (final msg in sub.messages) {
        setState(() {
          _messages.add('${msg.subject}: ${String.fromCharCodes(msg.payload)}');
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  void _sendMessage() {
    _nc.publish(
      'chat.general',
      Uint8List.fromList('Hello from Flutter!'.codeUnits),
    );
  }

  @override
  void dispose() {
    _nc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('NATS Chat')),
        body: Column(
          children: [
            Text('Status: $_status'),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(_messages[index]),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _sendMessage,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **Connection refused** | Verify NATS server is running: `docker run -p 4222:4222 nats:latest` |
| **WebSocket connection failed** | Ensure NATS has WebSocket enabled: `--websocket_port 9222 --websocket_no_tls` |
| **Message not received** | Check subscription subject matches publish subject; verify wildcards match correctly |
| **Reconnection not working** | Check `ConnectionStatus` stream; ensure subscriptions are re-subscribed after reconnect (auto-handled) |
| **Auth failing** | Verify credentials with: `nats pub` CLI tool using same server/auth params |

---

**Ready to dive deeper?** See [data-model.md](data-model.md) for architectural details, or [spec.md](spec.md) for technical requirements.
