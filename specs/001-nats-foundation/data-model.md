# Data Model: NATS Foundation & Core Client

**Purpose**: Define entities, relationships, and state machines for Phase 1 implementation  
**Phase**: 1 (Design)  
**Status**: Draft

---

## Domain Model Overview

The NATS client domain centers on **connection state management** and **message routing**:

1. **Connection State Machine** (NatsConnection)
2. **Message Routing** (Subscription + SID tracking)
3. **Authentication & Configuration** (ConnectOptions)
4. **Protocol Abstractions** (NatsMessage, Transport)
5. **Unique ID Generation** (Nuid)

---

## Core Entities

### Entity 1: NatsConnection

**Purpose**: Main client connection to NATS server; orchestrates all operations

**Immutability**: Mutable (stateful connection object)  
**Identity**: Single instance per isolate; created via factory `connect()`  
**Lifecycle**: Connect → Info Exchange → Subscribe/Publish → Reconnect (as needed) → Drain/Close

**State Machine**:
```
[Connecting] ──INFO──> [Connected] ──[error]──> [Reconnecting] ──[success]──> [Connected]
                              ↑─────────[close]──> [Closing] ──> [Closed]
                                        ↓
                    (publish/subscribe queued)
```

**Fields**:
- `Uri serverUri` — Server connection endpoint (nats://host:port or ws://...)
- `ConnectOptions options` — Configuration (timeouts, auth, etc)
- `Transport _transport` — Platform-specific connection (injected, testable)
- `NatsParser _parser` — Protocol parser (injected, testable)
- `Nuid _nuid` — Unique ID generator
- `Map<String, Subscription> _subscriptions` — Active subscriptions keyed by SID
- `StreamController<ConnectionStatus> _status` — Status events
- `int _pingCount` — PING/PONG counter
- `DateTime _lastPong` — Last PONG timestamp

**Public Operations**:
- `static Future<NatsConnection> connect(String url, {ConnectOptions? options})` — Factory
- `Future<void> publish(String subject, Uint8List data, {String? replyTo, Map<String, String>? headers})` — Publish
- `Future<NatsMessage> request(String subject, Uint8List data, {Duration timeout})` — Request/reply
- `Subscription subscribe(String subject, {String? queueGroup})` — Subscribe
- `Future<void> unsubscribe(Subscription sub)` — Unsubscribe
- `Stream<ConnectionStatus> get status` — Status stream
- `Future<void> drain()` — Drain (flush + close)
- `Future<void> close()` — Close immediately

**Key Behaviors**:
- **Handshake**: Receive INFO → Send CONNECT → Wait for +OK
- **Keepalive**: Send PING every 2min; respond to server PING with PONG
- **Reconnection**: On transport error → backoff retry → resend CONNECT → replay subscriptions
- **Message Routing**: Route incoming MSG/HMSG to correct subscription via SID

**Validation Rules**:
- Server MUST support `headers: true` in INFO (validated on first connection)
- `max_payload` from INFO enforced on publish (throw error if exceeded)
- `auth_required` in INFO checked against ConnectOptions

**Relationships**:
- 1 ↔ 1 with Transport (composition)
- 1 → 1 with NatsParser (composition)
- 1 → 1 with Nuid (composition)
- 1 → * with Subscription (aggregation)

---

### Entity 2: Subscription

**Purpose**: Active subscription to subjects with message delivery stream

**Immutability**: Mutable (state changes as messages arrive, unsubscribe called)  
**Identity**: Unique SID (base62, 22 chars); created via `connection.subscribe()`  
**Lifecycle**: Created → Receiving → Unsubscribed

**Fields**:
- `String subject` — Subject pattern (supports `*` and `>` wildcards)
- `String? queueGroup` — Optional queue group name
- `String _sid` — Subscription ID (unique 22-char base62)
- `StreamController<NatsMessage> _messages` — Message stream
- `int? _maxMessages` — Optional auto-unsub after N messages
- `int _messageCount` — Messages received so far

**Public Operations**:
- `Stream<NatsMessage> get messages` — Get message stream

**Key Behaviors**:
- **Wildcard Matching**: `FOO.*` matches `FOO.bar`, not `FOO.bar.baz`; `FOO.>` matches both
- **Queue Group**: Multiple subscribers with same queue group share load (round-robin)
- **Auto-Unsub**: If `_maxMessages` set, auto-unsubscribe after Nth message

**Validation Rules**:
- Subject must be valid UTF-8
- Subject cannot be empty
- Queue group (if provided) must be valid UTF-8

**Relationships**:
- * → 1 with NatsConnection (backref for routing)
- 1 → 1 with StreamController (message delivery)

---

### Entity 3: NatsMessage

**Purpose**: Parsed message from server (MSG or HMSG format)

**Immutability**: Immutable (value object; safe to share across threads)  
**Identity**: No identity (ephemeral message)

**Fields**:
- `String subject` — Message subject
- `String sid` — Subscription ID it was delivered to
- `String? replyTo` — Optional reply-to subject (for request/reply)
- `Uint8List payload` — Message body (binary)
- `Map<String, List<String>>? headers` — HMSG headers (multi-value supported)
- `int? statusCode` — Status code from HMSG first line (100, 404, 408, 409, or null for MSG)
- `String? statusDesc` — Status description (e.g., "FlowControl Request")

**Public Operations** (convenience getters):
- `bool get isFlowCtrl` → `statusCode == 100 && statusDesc.contains('Flow')`
- `bool get isHeartbeat` → `statusCode == 100 && statusDesc.contains('Idle')`
- `bool get isNoMsg` → `statusCode == 404`
- `bool get isTimeout` → `statusCode == 408`
- `String? header(String name)` → First value of multi-value header
- `List<String>? headerAll(String name)` → All values of multi-value header

**Validation Rules**:
- Payload can be empty (0 bytes)
- Headers multimap uses case-insensitive keys (normalized on parse)
- Status codes only appear in HMSG (headers present)

**Relationships**:
- No relationships (value object)

---

### Entity 4: Transport

**Purpose**: Platform-specific network connection abstraction

**Immutability**: Mutable (stateful connection)  
**Identity**: Abstract interface (implementations: TcpTransport, WebSocketTransport)  
**Type**: **Interface** (all platform-specific code lives here)

**Abstract Methods**:
- `Stream<Uint8List> get incoming` — Incoming bytes from server
- `Future<void> write(Uint8List data)` — Send bytes to server
- `Future<void> close()` — Disconnect
- `bool get isConnected` — Connection state
- `Stream<Object> get errors` — Connection errors

**Implementations**:

#### TcpTransport (dart:io)
**Platform**: Native (iOS, Android, macOS, Windows, Linux)  
**Use**: TCP socket via `dart:io.Socket`  
**Scheme**: `nats://` → TCP on port 4222

**Fields**:
- `String host`
- `int port`
- `Socket _socket`
- `StreamController<Uint8List> _incoming`
- `StreamController<Object> _errors`

---

#### WebSocketTransport (web_socket_channel)
**Platform**: All (native via dart:io, web via dart:html)  
**Use**: WebSocket via `web_socket_channel`  
**Scheme**: `ws://` or `wss://`

**Fields**:
- `Uri uri`
- `WebSocketChannel _channel`
- `StreamController<Uint8List> _incoming`
- `StreamController<Object> _errors`

---

### Entity 5: ConnectOptions

**Purpose**: Configuration for connection behavior and authentication

**Immutability**: Immutable (configuration object, safe to pass around)  
**Identity**: No identity (configuration)

**Fields**:
- `String? name` — Client name (for monitoring)
- `int maxReconnectAttempts` — Reconnect policy: -1 (infinite), 0 (disabled), N (max attempts)
- `Duration reconnectDelay` — Delay between reconnect attempts (default 2s)
- `Duration pingInterval` — Server keepalive interval (default 2min)
- `int maxPingOut` — Max unresponded PINGs (default 2) before reconnect
- `bool noEcho` — Don't receive own publishes (default false)
- `String inboxPrefix` — Custom inbox prefix (default '_INBOX')
- **Auth Fields** (exactly one, if any):
  - `String? authToken` — Token authentication
  - `String? user` + `String? pass` — Username/password
  - `String? jwt` + `String? nkeyPath` — JWT with NKey signing

**Validation Rules**:
- Exactly zero or one auth method must be set
- If set, all required auth fields must be present (user requires pass, jwt requires nkeyPath)
- Numeric values must be positive (or -1 for infinite)

**Relationships**:
- → NatsConnection (passed to factory)

---

### Entity 6: Nuid

**Purpose**: Thread-safe unique ID generator for inboxes and subscription IDs

**Immutability**: Mutable (internal state evolves as IDs generated)  
**Identity**: Singleton per connection (thread-safe)

**Fields**:
- `String _prefix` — 12-char cryptographic random prefix
- `int _seq` — 10-char sequence (base62, wraps at 62^10)
- `int _inc` — Random increment (prevents collision prediction)

**Public Operations**:
- `String next()` → 22-char base62 unique ID
- `String inbox([String prefix = '_INBOX'])` → `<prefix>.next()`

**Key Behaviors**:
- Prefix randomized initially and when sequence wraps
- Increment randomized per prefix
- Uses `Random.secure()` for cryptographic safety

**Validation Rules**:
- Sequence wraps at `62^10 = 839299365868340224`
- Prefix always 12 characters
- Full ID always 22 characters (no padding)

**Relationships**:
- 1 per NatsConnection

---

### Entity 7: NatsParser

**Purpose**: Stateful byte-buffer parser for NATS protocol commands

**Immutability**: Mutable (internal buffer state)  
**Identity**: One per connection (stateful)

**Key Behaviors**:
- **Streaming**: Accepts bytes via `addBytes(Uint8List)`, emits parsed messages
- **Stateful Parsing**: Handles messages split across multiple network packets
- **Multi-Frame**: Buffers partial messages until complete
- **Protocol Commands**: MSG, HMSG, INFO, PING, PONG, +OK, -ERR

**Output** (emitted as `NatsMessage`):
- MSG messages (no headers)
- HMSG messages (with headers and status codes)
- INFO (server capabilities JSON)
- PING/PONG events
- +OK acknowledgments
- -ERR errors

**Internal State Machine**:
```
[Buffering] ──[CRLF found]──> [Parse Command] ──[complete msg]──> [Emit] ──> [Buffering]
                                    ↓
                            [Extract payload/headers]
```

---

### Entity 8: NatsEncoder

**Purpose**: Generate byte-perfect NATS protocol commands

**Immutability**: Stateless (all methods static)  
**Identity**: No instance (utility class)

**Key Operations**:
- `Uint8List encodeConnect(ConnectOptions, {required bool headersSupported})` — CONNECT command
- `Uint8List encodePub(String subject, Uint8List payload, {String? replyTo})` — PUB command
- `Uint8List encodeHpub(String subject, Uint8List payload, {String? replyTo, Map<String, String>? headers})` — HPUB command with byte counting
- `Uint8List encodeSub(String subject, String sid, {String? queueGroup})` — SUB command
- `Uint8List encodeUnsub(String sid, {int? maxMsgs})` — UNSUB command
- `Uint8List encodePing()` → `PING\r\n`
- `Uint8List encodePong()` → `PONG\r\n`

**Key Behaviors**:
- **Byte-Perfect**: Output matches server expectations exactly (critical for HPUB)
- **HPUB Counting**: Header bytes = `NATS/1.0\r\n` + headers + `\r\n\r\n`
- **Total Bytes**: Header bytes + payload bytes
- **JSON Serialization**: CONNECT payload is JSON with auth fields

---

## State Machines

### NatsConnection Lifecycle

```
                    ┌─────────────────────────────┐
                    │      [Initializing]         │
                    │  (factory creates instance) │
                    └──────────────┬──────────────┘
                                   │ connect()
                    ┌──────────────▼──────────────┐
                    │      [Connecting]           │
                    │  (await transport.connect) │
                    └──────────────┬──────────────┘
                                   │ await INFO
                    ┌──────────────▼──────────────┐
                    │   [SendingConnect]          │
                    │  (send CONNECT, wait +OK)  │
                    └──────────────┬──────────────┘
                                   │ receive +OK
                    ┌──────────────▼──────────────┐
    ┌──────────────>│      [Connected]            │<──────────────┐
    │               │  (ready to pub/sub)         │               │
    │               └──────┬─────────┬──────────┬─┘               │
    │                      │         │          │                 │
    │ [reconnect ok]   error│     close│    drain│                │
    │      ┌────┐       │   │          │        │         [request-reply waits here]
    │      │    │       │   │          │        │
    │      │    │       ▼   ▼          ▼        ▼
    │      │    └──[Reconnecting]   [Closing]  [Draining]
    │      │          ↓ (backoff)        ↓         ↓
    │      │      [max attempts?]   [aborting]  [await flush]
    │      │          ↓ yes            ↓          ↓
    │      └──────[Closed]───────────
    │                         ↑
    └─────────────────────────┘
          [reconnect retry]

Legend:
- [State] ─action──> [NextState]
- Multiple paths indicate decision points
```

### Subscription Lifecycle

```
              ┌─────────────────────────────┐
              │     [Initializing]          │
              │ (allocate SID, create stream)
              └──────────────┬──────────────┘
                             │ send SUB command
              ┌──────────────▼──────────────┐
              │      [Active]               │
              │   (receiving messages)      │
              └──────┬─────────┬────────────┘
                     │         │
           auto-unsub│      unsubscribe()
            (if count=N)      │
                     │         │
              ┌──────▼─────────▼──────────┐
              │     [Unsubscribed]        │
              │  (send UNSUB, cleanup)    │
              └──────────────────────────┘
```

---

## Validation & Constraints

### Subject Name Validation
- ✅ Valid UTF-8
- ✅ Non-empty
- ✅ Contains only: alphanumeric, `.`, `-`, `_`, `*`, `>`
- ❌ Cannot start/end with `.`
- ❌ Cannot have `..` (double dots)

### Payload Constraints
- Minimum: 0 bytes (empty payload allowed)
- Maximum: Server-specified `max_payload` from INFO (enforced on publish)
- Type: Binary (Uint8List) — no encoding assumed

### Connection Constraints
- **Single-Isolate**: One NatsConnection per isolate (Phase 1 limitation)
- **Single-Server**: One server per connection (cluster support Phase 3+)
- **Auth**: At most one auth method

---

## Relationships & Aggregations

### Primary Aggregations

```
NatsConnection
  ├─ 1:1 Transport (composition)
  ├─ 1:1 NatsParser (composition)
  ├─ 1:1 Nuid (composition)
  ├─ 1:* Subscription (aggregation, keyed by SID, mutable)
  └─ 1:* StreamController<ConnectionStatus> (event stream)

Subscription
  ├─ 1:1 StreamController<NatsMessage> (message delivery)
  └─ *:1 NatsConnection (backref)

ConnectOptions
  └─ properties: maxReconnectAttempts, pingInterval, auth fields
```

---

## Summary

Phase 1 entities form a layered architecture:

1. **Transport Layer** (abstract) — TCP/WebSocket implementation isolation
2. **Protocol Layer** (parser, encoder) — Pure Dart byte manipulation
3. **Message Model** (NatsMessage, Nuid) — Immutable message + ID representations
4. **Connection Layer** (NatsConnection, Subscription) — Stateful client management
5. **Configuration Layer** (ConnectOptions) — Immutable options

This design ensures **Pure Dart** protocol logic independent of platform, **SOLID** principles via clear interfaces, and **testability** through dependency injection.

---

**Status**: Ready for implementation planning  
**Next**: Task breakdown via `/speckit.tasks`
