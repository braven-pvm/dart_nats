# NatsConnection API Contract

This document describes the public API contract for the `NatsConnection` class.

## Connection

### connect()

Creates and establishes a connection to a NATS server.

```dart
static Future<NatsConnection> connect(
  String url, {
  ConnectOptions? options,
})
```

**Parameters:**
- `url`: NATS server URL in format `nats://host:port` or `ws://host:port`
- `options`: Optional connection configuration (auth, reconnection, timeouts)

**Returns:** `Future<NatsConnection>` - Connected NATS client

**Throws:**
- `SocketException` - Network error or server unreachable
- `TimeoutException` - Connection timeout exceeded
- `StateError` - Authentication failed or protocol error

**Example:**

```dart
final nc = await NatsConnection.connect('nats://localhost:4222');
```

---

## Publishing

### publish()

Publishes a message to a subject.

```dart
Future<void> publish(
  String subject,
  Uint8List data, {
  String? replyTo,
  Map<String, String>? headers,
})
```

**Parameters:**
- `subject`: Target subject (e.g., `updates.user.123`)
- `data`: Message payload as bytes
- `replyTo`: Optional reply subject for request/reply
- `headers`: Optional headers (for JetStream compatibility)

**Throws:**
- `StateError` - Not connected
- `ArgumentError` - Payload exceeds server max_payload limit

**Example:**

```dart
await nc.publish(
  'updates.user.123',
  Uint8List.fromList('User data'.codeUnits),
  headers: {'Nats-Msg-Id': 'msg-001'},
);
```

---

## Subscribing

### subscribe()

Subscribes to a subject pattern.

```dart
Future<Subscription> subscribe(
  String subject, {
  String? queueGroup,
  int? max,
})
```

**Parameters:**
- `subject`: Subject pattern (supports wildcards `*` and `>`)
- `queueGroup`: Optional queue group name for load balancing
- `max`: Optional maximum messages before auto-unsubscribe

**Returns:** `Future<Subscription>` - Subscription with message stream

**Example:**

```dart
final sub = await nc.subscribe('updates.>');
await for (final msg in sub.messages) {
  print('Received: ${String.fromCharCodes(msg.payload)}');
}
```

### unsubscribe()

Unsubscribes from a subject and closes the subscription stream.

```dart
Future<void> unsubscribe(Subscription sub)
```

**Parameters:**
- `sub`: Subscription to unsubscribe from

**Example:**

```dart
await unsubscribe(sub);
```

---

## Request/Reply

### request()

Sends a request and waits for a response.

```dart
Future<NatsMessage> request(
  String subject,
  Uint8List data, {
  Duration timeout = const Duration(seconds: 10),
})
```

**Parameters:**
- `subject`: Request subject
- `data`: Request payload
- `timeout`: Maximum wait time for response

**Returns:** `Future<NatsMessage>` - Response message

**Throws:**
- `TimeoutException` - No response within timeout
- `StateError` - Not connected

**Example:**

```dart
final reply = await nc.request(
  'user.get',
  Uint8List.fromList('123'.codeUnits),
  timeout: Duration(seconds: 5),
);
print('Response: ${String.fromCharCodes(reply.payload)}');
```

---

## Lifecycle

### close()

Closes the connection and releases all resources. Idempotent.

```dart
Future<void> close()
```

**Behavior:**
- Cancels all subscriptions
- Closes transport connection
- Emits `ConnectionStatus.closed`
- Safe to call multiple times

**Example:**

```dart
await nc.close();
```

### drain()

Gracefully shuts down the connection by waiting for pending operations.

```dart
Future<void> drain()
```

**Behavior:**
1. Emits `ConnectionStatus.draining`
2. Sends UNSUB for all active subscriptions
3. Waits briefly for in-flight messages
4. Closes the connection

**Example:**

```dart
await nc.drain();
```

---

## Status Monitoring

### status

Stream of connection status changes.

```dart
Stream<ConnectionStatus> get status
```

**Status Values:**
- `ConnectionStatus.connecting` - Attempting connection
- `ConnectionStatus.connected` - Successfully connected
- `ConnectionStatus.reconnecting` - Reconnecting after disconnect
- `ConnectionStatus.draining` - Draining before close
- `ConnectionStatus.closed` - Connection closed

**Example:**

```dart
nc.status.listen((status) {
  print('Connection status: $status');
});
```

### isConnected

Whether the connection is currently active.

```dart
bool get isConnected
```

---

## JetStream Access

### jetStream()

Gets the JetStream context for this connection.

```dart
JetStreamContext jetStream({
  String? domain,
  Duration timeout = const Duration(seconds: 5),
})
```

**Parameters:**
- `domain`: Optional JetStream domain
- `timeout`: Operation timeout

**Returns:** `JetStreamContext` - JetStream API access

**Throws:**
- `StateError` - JetStream not available on server

**Example:**

```dart
final js = nc.jetStream();
```

---

## See Also

- [JetStream API Contract](jetstream.md)
- [KeyValue API Contract](kv.md)
- [ConnectOptions](../data-model.md#connectoptions)
