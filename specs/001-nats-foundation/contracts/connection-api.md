# Contract: NatsConnection API Specification

**Purpose**: Define the public API surface and behavior of the NATS client connection  
**Status**: Phase 1 Foundation  

---

## Factory Method

```dart
/// Connect to a NATS server.
///
/// Returns a connected NatsConnection ready for pub/sub operations.
///
/// Throws:
/// - SocketException: Network error (host unreachable, etc.)
/// - TimeoutException: Connection timeout
/// - StateError: Invalid server INFO or protocol violation
static Future<NatsConnection> connect(
  String url, {
  ConnectOptions? options,
}) async {
  // Establish transport
  // Exchange INFO/CONNECT handshake
  // Return ready connection
}
```

**Usage**:
```dart
final nc = await NatsConnection.connect('nats://localhost:4222');
final ncAuth = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    user: 'alice',
    pass: 'password',
  ),
);
```

---

## Core Operations

### publish

```dart
/// Publish a message to a subject.
///
/// Args:
/// - subject: Destination subject (required)
/// - data: Message payload in bytes (may be empty)
/// - replyTo: Optional reply-to subject for request/reply patterns
/// - headers: Optional headers (Map<String, String>) for protocol metadata
///
/// Returns: Future completes when message is sent to server
///          (NOT when server delivers to subscribers)
///
/// Throws:
/// - StateError: Connection is not ready (use status stream to monitor)
/// - ArgumentError: Subject is empty or payload exceeds max_payload
/// - SocketException: Write failed
Future<void> publish(
  String subject,
  Uint8List data, {
  String? replyTo,
  Map<String, String>? headers,
}) async {
  // Validate subject and payload size
  // Encode PUB or HPUB command
  // Write to transport
}
```

**Usage**:
```dart
// Simple publish
await nc.publish(
  'user.updated',
  Uint8List.fromList('"128".codeUnits),
);

// With reply-to (for request/reply)
await nc.publish(
  'user.get',
  Uint8List.fromList('{"id":"123"}'.codeUnits),
  replyTo: 'inbox.reply.1',
);

// With headers (for JetStream)
await nc.publish(
  'orders.new',
  Uint8List.fromList('{"orderId":"456"}'.codeUnits),
  headers: {'Nats-Msg-Id': 'order-456-001'},
);
```

---

### subscribe

```dart
/// Subscribe to a subject or subject pattern.
///
/// Returns a Subscription for receiving messages.
/// Subscription continues until explicitly unsubscribed or connection closes.
///
/// Args:
/// - subject: Subject pattern (supports * and > wildcards)
/// - queueGroup: Optional load-balancing queue group name
///
/// Throws:
/// - StateError: Connection is not ready
/// - ArgumentError: Subject is empty or invalid
///
/// Returns: Subscription object with message stream
Subscription subscribe(
  String subject, {
  String? queueGroup,
}) {
  // Allocate unique SID (via NUID)
  // Send SUB command to server
  // Register subscription internally
  // Return Subscription with message stream
}
```

**Usage**:
```dart
// Basic subscribe
final sub = nc.subscribe('notifications.>');
await for (final msg in sub.messages) {
  print('Received: ${msg.subject}');
}

// With queue group (load balanced)
final taskSub = nc.subscribe(
  'tasks.process',
  queueGroup: 'workers',
);
```

---

### unsubscribe

```dart
/// Unsubscribe from a subscription.
///
/// Stops delivery of new messages to this subscription.
/// In-flight messages may still be delivered.
///
/// Args:
/// - subscription: Subscription to cancel
///
/// Throws:
/// - StateError: Connection is not ready
/// - ArgumentError: Subscription not recognized
Future<void> unsubscribe(Subscription subscription) async {
  // Send UNSUB command with subscription SID
  // Remove subscription from internal registry
  // Close message stream
}
```

**Usage**:
```dart
final sub = nc.subscribe('updates.>');
// ... later ...
await nc.unsubscribe(sub);
```

---

### request

```dart
/// Send a request and wait for a reply (request/reply pattern).
///
/// Internally:
/// 1. Creates an inbox subject
/// 2. Subscribes to inbox
/// 3. Publishes request with replyTo=inbox
/// 4. Waits for response on inbox stream
///
/// Args:
/// - subject: Request subject
/// - data: Request payload
/// - timeout: Max time to wait for response (default 10 seconds)
///
/// Returns: Reply message as NatsMessage
///
/// Throws:
/// - TimeoutException: No reply received within timeout
/// - StateError: Connection not ready
/// - SocketException: Network error
Future<NatsMessage> request(
  String subject,
  Uint8List data, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  // Create unique inbox
  // Subscribe to inbox
  // Publish request with replyTo=inbox
  // Wait for response or timeout
  // Auto-clean up subscription after response
}
```

**Usage**:
```dart
try {
  final reply = await nc.request(
    'user.get',
    Uint8List.fromList('{"id":"123"}'.codeUnits),
    timeout: Duration(seconds: 5),
  );
  print('Reply: ${String.fromCharCodes(reply.payload)}');
} on TimeoutException {
  print('No response within 5 seconds');
}
```

---

### drain

```dart
/// Drain and close the connection gracefully.
///
/// Stops accepting new subscriptions but allows existing subscriptions
/// to finish receiving in-flight messages.
/// Completes when all subscriptions have been unsubscribed and all
/// buffered publishes have been sent.
///
/// After drain, connection is closed (status = closed).
///
/// Throws:
/// - StateError: Connection already closed
Future<void> drain() async {
  // Send UNSUB with auto-max for all subscriptions
  // Flush all buffered writes
  // Close connection
}
```

**Usage**:
```dart
// Gracefully shutdown
await nc.drain();
print('All messages processed, connection closed');
```

---

### close

```dart
/// Close the connection immediately.
///
/// Disconnects from server without waiting for in-flight messages.
/// Can be called multiple times (idempotent).
///
/// After close, all subscriptions are invalidated.
/// New pub/sub operations will fail with StateError.
///
/// Throws: None (idempotent)
Future<void> close() async {
  // Send CLOSE command (optional)
  // Close transport
  // Mark connection as closed
}
```

**Usage**:
```dart
await nc.close();
// Connection is now unusable
```

---

## Streams & Status Monitoring

### status

```dart
/// Stream of connection status changes.
///
/// Emits: ConnectionStatus enum values
/// - connecting: Initially connecting to server
/// - connected: Successfully connected and ready for pub/sub
/// - reconnecting: Lost connection, attempting to reconnect
/// - closed: Connection closed by client or fatal error
///
/// Use: Monitor connection state, update UI, trigger cleanup
Stream<ConnectionStatus> get status {
  // Return stream of status events
}
```

**Usage**:
```dart
nc.status.listen((status) {
  switch (status) {
    case ConnectionStatus.connecting:
      print('Connecting...');
    case ConnectionStatus.connected:
      print('Ready to publish/subscribe');
    case ConnectionStatus.reconnecting:
      print('Reconnecting after network loss');
    case ConnectionStatus.closed:
      print('Connection closed');
  }
});
```

---

## Connection State

### isConnected

```dart
/// Whether the connection is ready for pub/sub.
///
/// Returns: true if status is 'connected'
bool get isConnected => _status.latest == ConnectionStatus.connected;
```

**Usage**:
```dart
if (nc.isConnected) {
  await nc.publish('message', data);
}
```

---

## Authentication Options

```dart
class ConnectOptions {
  /// Custom client name (for server monitoring)
  final String? name;

  /// Reconnection policy
  final int maxReconnectAttempts;      // -1 = infinite, 0 = disabled, N = max
  final Duration reconnectDelay;       // delay between attempts

  /// Server keepalive
  final Duration pingInterval;         // default: 2 minutes
  final int maxPingOut;                // default: 2

  /// Message handling
  final bool noEcho;                   // don't receive own publishes
  final String inboxPrefix;            // inbox subject prefix

  /// Authentication (exactly one method, if any)
  final String? authToken;             // token auth
  final String? user;                  // username (requires pass)
  final String? pass;                  // password (requires user)
  final String? jwt;                   // JWT (requires nkeyPath)
  final String? nkeyPath;              // NKey seed path (for JWT signing)
}
```

**Usage Patterns**:

```dart
// No auth
final nc = await NatsConnection.connect('nats://localhost:4222');

// Token auth
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(authToken: 'my-token'),
);

// User/pass
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(user: 'alice', pass: 'password'),
);

// NKey
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(nkeyPath: '/path/to/nkey.nk'),
);

// JWT
final nc = await NatsConnection.connect(
  'nats://localhost:4222',
  options: ConnectOptions(
    jwt: 'eyJhbGc...',
    nkeyPath: '/path/to/nkey.nk',
  ),
);
```

---

## Message Type: NatsMessage

```dart
class NatsMessage {
  /// Subject this message was delivered to
  final String subject;

  /// Reply-to subject (if request/reply)
  final String? replyTo;

  /// Message payload (binary)
  final Uint8List payload;

  /// Message headers (if sent via HPUB)
  final Map<String, List<String>>? headers;

  /// Status code (if HMSG with status line)
  final int? statusCode;

  /// Status description (if HMSG with status line)
  final String? statusDesc;

  // Convenience getters
  bool get isFlowCtrl => statusCode == 100 && statusDesc?.contains('Flow') ?? false;
  bool get isHeartbeat => statusCode == 100 && statusDesc?.contains('Idle') ?? false;
  bool get isNoMsg => statusCode == 404;
  bool get isTimeout => statusCode == 408;

  String? header(String name) => headers?[name.toLowerCase()]?.first;
  List<String>? headerAll(String name) => headers?[name.toLowerCase()];
}
```

---

## Subscription Type

```dart
class Subscription {
  /// Subject pattern this subscription listens to
  final String subject;

  /// Queue group (if load balancing)
  final String? queueGroup;

  /// Stream of received messages
  Stream<NatsMessage> get messages;
}
```

---

## Error Handling

```dart
// All operations throw on error (no silent failures)

try {
  final nc = await NatsConnection.connect('nats://localhost:4222');
  
  await nc.publish('subject', data);
  
  final sub = nc.subscribe('topic.>');
  await for (final msg in sub.messages) {
    // ... process message ...
  }
  
  final reply = await nc.request('service', data, timeout: Duration(seconds: 5));
  
  await nc.drain();
} on SocketException catch (e) {
  print('Network error: $e');
} on TimeoutException catch (e) {
  print('Request timed out: $e');
} on ArgumentError catch (e) {
  print('Invalid argument: $e');
} on StateError catch (e) {
  print('Connection not ready: $e');
}
```

---

## Reconnection Behavior (Automatic)

The connection automatically reconnects on network failure:

```dart
// User code doesn't change
final nc = await NatsConnection.connect('nats://localhost:4222');

// Subscribe before network drops
final sub = nc.subscribe('updates.>');

// If network drops and recovers:
// 1. Connection automatically reconnects (status: reconnecting → connected)
// 2. Subscriptions are automatically replayed (server re-subscribes)
// 3. Message stream continues transparently

await for (final msg in sub.messages) {
  // Works even after network recovery
  print('${msg.subject}: ${String.fromCharCodes(msg.payload)}');
}
```

**Configuration**:
```dart
// Customize reconnection
options: ConnectOptions(
  maxReconnectAttempts: 10,           // Max 10 reconnect attempts
  reconnectDelay: Duration(seconds: 1), // 1 second between attempts
)
```

---

## Implementation Checklist

- [ ] Factory `connect()` with URL parsing and transport creation
- [ ] `publish()` with subject/payload validation and PUB/HPUB encoding
- [ ] `subscribe()` with SID allocation and SUB command
- [ ] `unsubscribe()` with UNSUB command and cleanup
- [ ] `request()` with inbox creation, auto-subscribe/unsubscribe
- [ ] `drain()` with graceful shutdown
- [ ] `close()` with immediate disconnect
- [ ] `status` stream with ConnectionStatus enum
- [ ] Automatic reconnection with configurable backoff
- [ ] Subscription replay on reconnect
- [ ] Message buffering during reconnect
- [ ] PING/PONG keepalive handling
- [ ] Error handling and propagation
- [ ] Handler for server-initiated PING (respond with PONG)

---

**Status**: Ready for implementation  
**Next**: Begin Phase 2 task breakdown via `/speckit.tasks`
