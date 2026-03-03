# KeyValue API Contract

This document describes the public API contract for the KeyValue store.

## KeyValue

Distributed key-value store built on JetStream.

### Access

```dart
final js = nc.jetStream();
final kv = await js.keyValue('my-bucket');
```

---

## Operations

### put()

Store a value for a key.

```dart
Future<int> put(String key, Uint8List value)
```

**Parameters:**
- `key`: Key name
- `value`: Value as bytes

**Returns:** `Future<int>` - Revision number (stream sequence)

**Example:**

```dart
final revision = await kv.put(
  'session:123',
  Uint8List.fromList('{"user":"alice"}'.codeUnits),
);
print('Stored at revision $revision');
```

### get()

Retrieve a value for a key.

```dart
Future<KvEntry?> get(String key)
```

**Parameters:**
- `key`: Key name

**Returns:** `Future<KvEntry?>` - Entry or null if not found

**Example:**

```dart
final entry = await kv.get('session:123');
if (entry != null) {
  print('Value: ${String.fromCharCodes(entry.value)}');
  print('Revision: ${entry.revision}');
} else {
  print('Key not found');
}
```

### delete()

Delete a key (creates a tombstone marker).

```dart
Future<void> delete(String key)
```

**Parameters:**
- `key`: Key to delete

**Example:**

```dart
await kv.delete('session:123');
```

### watch()

Watch a specific key for changes.

```dart
Stream<KvEntry> watch(String key)
```

**Parameters:**
- `key`: Key to watch

**Returns:** `Stream<KvEntry>` - Stream of changes

**Example:**

```dart
kv.watch('session:123').listen((entry) {
  if (entry.isDeleted) {
    print('Key deleted');
  } else {
    print('Updated: ${String.fromCharCodes(entry.value)}');
  }
});
```

### watchAll()

Watch all keys in the bucket.

```dart
Stream<KvEntry> watchAll()
```

**Returns:** `Stream<KvEntry>` - Stream of all changes

**Example:**

```dart
kv.watchAll().listen((entry) {
  print('Key ${entry.key} changed at revision ${entry.revision}');
});
```

---

## KvEntry

Entry in a KeyValue bucket.

```dart
class KvEntry {
  final String bucket;       // Bucket name
  final String key;          // Key name
  final Uint8List value;     // Value bytes
  final int revision;        // JetStream stream sequence
  final DateTime created;    // Creation timestamp
  final KvOp operation;      // Operation type

  String get valueString;    // UTF-8 decoded value
  bool get isDeleted;        // True if operation is del or purge
}
```

### KvOp Enum

```dart
enum KvOp {
  put,    // Key set
  del,    // Key deleted
  purge,  // Key purged
}
```

---

## Usage Examples

### Basic CRUD

```dart
// Put
await kv.put('config:theme', Uint8List.fromList('dark'.codeUnits));

// Get
final entry = await kv.get('config:theme');
print('Theme: ${entry?.valueString}');

// Delete
await kv.delete('config:theme');

// Verify deletion
final deleted = await kv.get('config:theme');
print('Deleted: ${deleted?.isDeleted}');
```

### Watching Changes

```dart
// Watch single key
kv.watch('user:alice').listen((entry) {
  print('User updated: ${entry.valueString}');
});

// Watch all users
kv.watchAll().listen((entry) {
  if (entry.key.startsWith('user:')) {
    print('User change: ${entry.key}');
  }
});
```

### Session Management

```dart
// Create session
await kv.put(
  'session:${sessionId}',
  Uint8List.fromList(jsonEncode(sessionData).codeUnits),
);

// Update session (new revision)
await kv.put(
  'session:${sessionId}',
  Uint8List.fromList(jsonEncode(updatedData).codeUnits),
);

// Delete on logout
await kv.delete('session:${sessionId}');
```

---

## Bucket Configuration (Phase 3)

Buckets are created via JetStream stream configuration:

```dart
// Bucket creation (API planned)
await js.keyValue('my-bucket');  // Auto-creates if not exists
```

Underlying stream: `KV_<bucket>`

---

## See Also

- [JetStream API Contract](jetstream.md)
- [NatsConnection API Contract](connection.md)
- [NATS KeyValue Documentation](https://docs.nats.io/nats-concepts/jetstream/key-value-store)
