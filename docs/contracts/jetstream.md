# JetStream API Contract

This document describes the public API contract for JetStream operations.

## JetStreamContext

Entry point for all JetStream operations.

### Access

```dart
JetStreamContext jetStream({
  String? domain,
  Duration timeout = const Duration(seconds: 5),
})
```

### Publish to Stream

Publish a message to a JetStream stream with optional deduplication.

```dart
Future<PubAck> publish(
  String subject,
  Uint8List data, {
  String? msgId,
  Map<String, String>? headers,
})
```

**Parameters:**
- `subject`: Subject within a stream's configured subjects
- `data`: Message payload
- `msgId`: Optional deduplication ID (Nats-Msg-Id header)
- `headers`: Optional additional headers

**Returns:** `Future<PubAck>` - Publish acknowledgment

**PubAck Fields:**
```dart
class PubAck {
  final String stream;      // Stream name
  final int sequence;        // Sequence number
  final bool duplicate;      // Whether duplicate detected
}
```

**Example:**

```dart
final js = nc.jetStream();

// Publish with deduplication
final ack = await js.publish(
  'TESTS.session_1',
  Uint8List.fromList('{"power":285}'.codeUnits),
  msgId: 'session-1-001',
);

print('Stored in ${ack.stream} at sequence ${ack.sequence}');
if (ack.duplicate) {
  print('Duplicate message detected');
}
```

---

## Stream Management (Phase 2)

### Create Stream

```dart
Future<StreamInfo> createStream(StreamConfig config)
```

**Parameters:**
- `config`: Stream configuration

**Returns:** `Future<StreamInfo>` - Created stream info

### Get Stream Info

```dart
Future<StreamInfo> streamInfo(String name)
```

**Parameters:**
- `name`: Stream name

**Returns:** `Future<StreamInfo>` - Stream configuration and state

### List Streams

```dart
Future<List<String>> streamNames()
```

**Returns:** `Future<List<String>>` - List of stream names

### Delete Stream

```dart
Future<void> deleteStream(String name)
```

**Parameters:**
- `name`: Stream name to delete

---

## Consumer Management (Phase 2)

### Create Consumer

```dart
Future<ConsumerInfo> createConsumer(
  String stream,
  ConsumerConfig config,
)
```

**Parameters:**
- `stream`: Stream name
- `config`: Consumer configuration

**Returns:** `Future<ConsumerInfo>` - Created consumer info

### Get Consumer

```dart
Future<PullConsumer> consumer(
  String stream,
  String name,
)
```

**Parameters:**
- `stream`: Stream name
- `name`: Consumer name (durable) or generated (ephemeral)

**Returns:** `Future<PullConsumer>` - Pull consumer instance

### Delete Consumer

```dart
Future<void> deleteConsumer(String stream, String name)
```

**Parameters:**
- `stream`: Stream name
- `name`: Consumer name

---

## Pull Consumer (Phase 2)

### Fetch Batch

```dart
Future<List<JsMsg>> fetch(
  int max, {
  Duration expires = const Duration(seconds: 5),
  int? maxBytes,
  bool noWait = false,
})
```

**Parameters:**
- `max`: Maximum messages to fetch
- `expires`: How long to wait for messages
- `maxBytes`: Optional maximum total bytes
- `noWait`: Return immediately if no messages

**Returns:** `Future<List<JsMsg>>` - List of messages

**Example:**

```dart
final consumer = await js.consumer('MY_STREAM', 'my-consumer');

final messages = await consumer.fetch(
  10,
  expires: Duration(seconds: 2),
);

for (final msg in messages) {
  print('Subject: ${msg.subject}');
  print('Data: ${String.fromCharCodes(msg.data)}');
  await msg.ack();
}
```

### Continuous Consume

```dart
Stream<JsMsg> consume({
  int batchSize = 100,
  Duration fetchExpiry = const Duration(seconds: 5),
})
```

**Parameters:**
- `batchSize`: Messages per fetch request
- `fetchExpiry`: Expiry per batch

**Returns:** `Stream<JsMsg>` - Continuous message stream

**Example:**

```dart
await for (final msg in consumer.consume(batchSize: 50)) {
  await processMessage(msg);
  await msg.ack();
}
```

---

## JsMsg (Phase 2)

JetStream message with acknowledgment support.

### Acknowledgment Methods

```dart
class JsMsg {
  // Acknowledge successful processing
  Future<void> ack();
  
  // Negative acknowledgment (redeliver later)
  Future<void> nak({Duration? delay});
  
  // In-progress (reset ack timer)
  Future<void> inProgress();
  
  // Terminate (never redeliver)
  Future<void> term();
}
```

**Example:**

```dart
for (final msg in messages) {
  try {
    await processMessage(msg);
    await msg.ack();
  } catch (e) {
    // Redeliver after 5 seconds
    await msg.nak(delay: Duration(seconds: 5));
  }
}
```

---

## keyValue()

Access KeyValue store for this JetStream account.

```dart
Future<KeyValue> keyValue(String bucket)
```

**Parameters:**
- `bucket`: Bucket name

**Returns:** `Future<KeyValue>` - KeyValue API

See [KeyValue API Contract](kv.md) for details.

---

## Configuration

### StreamConfig (Phase 2)

```dart
class StreamConfig {
  final String name;
  final List<String> subjects;
  final String storage;      // 'file' or 'memory'
  final String retention;    // 'limits', 'interest', 'workqueue'
  final int maxMsgs;
  final int maxBytes;
  final Duration maxAge;
  final Duration duplicateWindow;
}
```

### ConsumerConfig (Phase 2)

```dart
class ConsumerConfig {
  final String? durableName;
  final String deliverPolicy;  // 'all', 'new', 'last', 'by_start_sequence'
  final String ackPolicy;      // 'none', 'all', 'explicit'
  final Duration ackWait;
  final int maxDeliver;
  final String? filterSubject;
  final int maxAckPending;
}
```

---

## See Also

- [NatsConnection API Contract](connection.md)
- [KeyValue API Contract](kv.md)
- [NATS JetStream Documentation](https://docs.nats.io/nats-concepts/jetstream)
