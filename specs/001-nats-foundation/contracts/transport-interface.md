# Contract: Transport Interface Specification

**Purpose**: Define the abstraction boundary between platform-specific transport (TCP/WebSocket) and platform-agnostic protocol logic  
**Status**: Phase 1 Foundation  

---

## Motivation

The Transport interface is **the only place** where platform-specific code lives. This enforces:

1. **Pure Dart Protocol**: All parser, encoder, connection logic is 100% identical across platforms
2. **Compile-Time Selection**: Conditional imports (`if (dart.library.io)`) enable tree-shaking for small binary size
3. **Testability**: Mock transport implementations enable unit testing without network

---

## Transport Interface (Abstract)

**Dart Definition**:

```dart
/// Platform-agnostic network connection abstraction.
///
/// Implementations: TcpTransport (dart:io), WebSocketTransport (web_socket_channel)
abstract class Transport {
  /// Outgoing stream of bytes from the network.
  ///
  /// Emits Uint8List chunks as data arrives.
  /// Connection errors are emitted as exceptions on this stream.
  Stream<Uint8List> get incoming;

  /// Outgoing error stream.
  ///
  /// Emits connection errors, timeouts, or protocol violations.
  Stream<Object> get errors;

  /// Connection state.
  ///
  /// Returns true if transport is open and ready to send/receive.
  bool get isConnected;

  /// Establish connection to remote server.
  ///
  /// Throws immediately if connection fails (e.g., host unreachable, timeout).
  /// Implementation-specific timeout is enforced (e.g., 10 seconds for TCP).
  Future<void> connect();

  /// Send bytes to the server.
  ///
  /// Throws if transport is not connected or if write fails mid-stream.
  /// Guarantees: Data is written as a complete unit (no fragmentation at this level).
  Future<void> write(Uint8List data);

  /// Close the connection gracefully.
  ///
  /// No further I/O operations are possible after close.
  /// Safe to call multiple times (idempotent).
  Future<void> close();
}
```

---

## Implementations

### TcpTransport (Native: iOS, Android, macOS, Windows, Linux)

**Dependencies**: `dart:io` only (native platforms)

**Location**: `lib/src/transport/tcp_transport.dart`

**Constructor**:
```dart
class TcpTransport extends Transport {
  final String host;
  final int port;
  
  TcpTransport({
    required this.host,
    required this.port,
    Duration connectTimeout = const Duration(seconds: 10),
  });
}
```

**Behavior**:

| Operation | Detail |
|-----------|--------|
| **connect()** | Create TCP socket via `Socket.connect(host, port, timeout: connectTimeout)` |
| **incoming stream** | Read bytes from socket via `socket.listen(onData, onError)` |
| **write()** | Send bytes via `socket.add(data)` |
| **close()** | Close socket via `socket.close()` |
| **errors stream** | Socket errors (SocketException, TimeoutException) |

**Example Execution**:
```dart
// Create and connect
final transport = TcpTransport(host: 'localhost', port: 4222);
await transport.connect();

// Listen for data
transport.incoming.listen((chunk) {
  print('Received: $chunk');
});

// Send data
await transport.write(Uint8List.fromList([1, 2, 3]));

// Close
await transport.close();
```

**Edge Cases**:
- Connection refused → throw `SocketException`
- Timeout during `connect()` → throw `TimeoutException`
- Write on closed socket → throw `SocketException`
- Multiple `connect()` calls → throw `SocketException` (connection already exists)
- Multiple `close()` calls → idempotent (no error)

---

### WebSocketTransport (All Platforms via web_socket_channel)

**Dependencies**: `web_socket_channel` (works on native and web)

**Location**: `lib/src/transport/websocket_transport.dart`

**Constructor**:
```dart
class WebSocketTransport extends Transport {
  final Uri uri;
  
  WebSocketTransport({
    required this.uri,
    Duration connectTimeout = const Duration(seconds: 10),
  });
  // Example: Uri.parse('ws://localhost:9222')
}
```

**Behavior**:

| Operation | Detail |
|-----------|--------|
| **connect()** | Create WebSocket via `WebSocketChannel.connect(uri)` with timeout |
| **incoming stream** | Decode bytes via `channel.stream.listen()` → UTF8 decode → emit Uint8List |
| **write()** | Send via `channel.sink.add(Uint8List as String to bytes)` → UTF8 encoded |
| **close()** | Close via `channel.sink.close()` |
| **errors stream** | WebSocket errors and stream errors |

**Example Execution**:
```dart
// Create and connect
final transport = WebSocketTransport(uri: Uri.parse('ws://localhost:9222'));
await transport.connect();

// Listen for data
transport.incoming.listen((chunk) {
  print('Received: $chunk');
});

// Send binary data
await transport.write(Uint8List.fromList([1, 2, 3]));

// Close
await transport.close();
```

**Encoding Details**:
- NATS protocol is text (commands) + binary (payloads)
- WebSocket carries binary data as UTF-8 encoded strings
- Encoder generates `Uint8List` → must encode to string before WebSocket `sink.add()`
- Parser receives string from `channel.stream` → must decode to `Uint8List` before processing
- **Critical**: Full binary fidelity must be preserved (no UTF-8 validation errors)

**Edge Cases**:
- Connection refused → throw exception
- Timeout during `connect()` → throw `TimeoutException`
- WebSocket upgrade fails → throw `WebSocketChannelException`
- Write on closed channel → exception
- Multiple `connect()` calls → throw (connection exists)
- Multiple `close()` calls → idempotent

---

## Factory Pattern (Runtime Platform Detection)

**Location**: `lib/src/transport/transport_factory.dart`

**Purpose**: Auto-select TCP vs WebSocket at compile-time based on platform

**Implementation**:

```dart
// transport_factory.dart
import 'transport.dart';

// Conditional imports (compile-time)
if (dart.library.io)
  import 'tcp_transport.dart'
else
  import 'websocket_transport.dart';

/// Creates transport based on URL scheme and platform.
///
/// Scheme mapping:
/// - nats://host:port → TCP on native, WebSocket on web
/// - tcp://host:port → TCP (requires native)
/// - ws://host:port → WebSocket
/// - wss://host:port → WebSocket (secure)
Transport createTransport(String url) {
  final uri = Uri.parse(url);
  
  switch (uri.scheme) {
    case 'nats':
      // Auto-select based on platform
      return _createNatsTransport(uri);
    case 'tcp':
      return TcpTransport(host: uri.host, port: uri.port);
    case 'ws':
    case 'wss':
      return WebSocketTransport(uri: uri);
    default:
      throw ArgumentError('Invalid NATS URL: $url');
  }
}

// Platform-specific helper
Transport _createNatsTransport(Uri uri) {
  // On native: convert to TCP
  // On web: convert to WebSocket
  ...
}
```

**URL Scheme Resolution**:

| Scheme | Platform | Result |
|--------|----------|--------|
| `nats://` | Native | TCP `:4222` |
| `nats://` | Web | WebSocket `:9222` |
| `tcp://` | Native | TCP (specified port) |
| `tcp://` | Web | **Error** (not supported) |
| `ws://` | Any | WebSocket |
| `wss://` | Any | WebSocket (secure TLS) |

---

## Contract: Byte Handling

### Stream Semantics

**Incoming stream**:
- Emits `Uint8List` chunks as network data arrives
- Chunks may be any size (not guaranteed to align with NATS messages)
- Example: A single MSG command may arrive in chunks: `[MSG notif]` then `[ications.123 1 \r\n]`
- Parser must handle **stateful buffering** to reassemble multi-chunk messages

**Error handling**:
- Errors emitted on `errors` stream (not as stream exceptions)
- Allows higher-level code to decide: reconnect, fail, or ignore

---

## Contract: State Machine

```
[Initialized] ──connect()──> [Connected] ──close()──> [Closed]
                   ↓              ↑                      ↓
                [Error]           └── reconnect on app logic
                   ↑
              (errors stream)
```

**Invariants**:
- `isConnected == false` initially
- `isConnected == true` after `connect()` succeeds
- `isConnected == false` after `close()` succeeds
- No operations valid if `isConnected == false` (except `connect()` and `close()`)

---

## Error Contract

All operations throw on error; errors are NOT silent:

| Operation | Error Type | Example |
|-----------|-----------|---------|
| `connect()` | `SocketException`, `TimeoutException`, `WebSocketChannelException` | "Connection refused" |
| `write()` | `SocketException`, `WebSocketChannelException` | "Write failed" |
| `close()` | Usually none (idempotent, recovers gracefully) | — |

---

## Testing & Mocking

**Mock Transport** for unit testing:

```dart
class MockTransport extends Transport {
  final _incomingController = StreamController<Uint8List>();
  final _errorsController = StreamController<Object>();
  
  @override
  Stream<Uint8List> get incoming => _incomingController.stream;
  
  @override
  Stream<Object> get errors => _errorsController.stream;
  
  @override
  bool get isConnected => _connected;
  
  @override
  Future<void> connect() async {
    _connected = true;
  }
  
  @override
  Future<void> write(Uint8List data) async {
    // Capture for test inspection
    _lastWrite = data;
  }
  
  @override
  Future<void> close() async {
    _connected = false;
  }
  
  // Test helpers
  void pumpData(Uint8List data) => _incomingController.add(data);
  void pumpError(Object error) => _errorsController.add(error);
}
```

**Usage**:
```dart
test('publish sends PUB command', () async {
  final transport = MockTransport();
  final nc = NatsConnection(transport: transport);
  
  await nc.publish('test', Uint8List.fromList([1, 2, 3]));
  
  expect(transport._lastWrite, contains('PUB test'));
});
```

---

## Implementation Checklist

### TcpTransport
- [ ] Accept host, port, connectTimeout in constructor
- [ ] Implement `connect()` using `Socket.connect()`
- [ ] Implement `incoming` stream (bytes from socket)
- [ ] Implement `errors` stream (socket exceptions)
- [ ] Implement `write()` (socket.add)
- [ ] Implement `close()` (socket.close, idempotent)
- [ ] Handle SocketException and TimeoutException
- [ ] Test with mock server (nc-listen or Docker NATS)

### WebSocketTransport
- [ ] Accept URI in constructor
- [ ] Implement `connect()` using `WebSocketChannel.connect()`
- [ ] Implement `incoming` stream (decode bytes from channel)
- [ ] Implement `errors` stream
- [ ] Implement `write()` (encode bytes to string)
- [ ] Implement `close()` (channel.sink.close)
- [ ] Verify UTF-8 encoding/decoding fidelity
- [ ] Test with Docker NATS + WebSocket support

### Factory
- [ ] Conditional imports for TcpTransport and WebSocketTransport
- [ ] Auto-detect platform (dart:io available)
- [ ] Map `nats://` to TCP or WebSocket based on platform
- [ ] Support explicit `tcp://`, `ws://`, `wss://` schemes
- [ ] Throw descriptive error on invalid scheme

---

**Status**: Ready for implementation  
**Next**: Prepare connection API contract
