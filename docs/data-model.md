# Data Model & State Machines

This document describes the data models, state machines, and lifecycle flows in nats_dart.

## Parser State Machine

The `NatsParser` is a stateful byte-buffer parser that handles incoming NATS protocol messages.

### States & Transitions

```
┌─────────────────────────────────────────────┐
│           IDLE (waiting for CRLF)            │
└─────────────────────────────────────────────┘
                      │
                      │ CRLF found
                      ▼
         ┌────────────────────────┐
         │ Parse control line     │
         │ Extract operation (OP) │
         └────────────────────────┘
                      │
        ┌─────────────┼─────────────────┐
        │             │                 │
   OP=MSG/HMSG   OP=INFO/PING/etc   OP=unknown
        │             │                 │
        ▼             ▼                 ▼
┌───────────────┐ ┌────────┐      ┌────────┐
│ Parse payload │ │  Emit  │      │  Skip  │
│ (wait bytes)  │ │ message│      │  line  │
└───────────────┘ └────────┘      └────────┘
        │
        │ Payload complete
        ▼
   Emit message
   Advance buffer
        │
        ▼
    Return to IDLE
```

### Buffer Management

The parser maintains a growing byte buffer (`BytesBuilder`) that accumulates incoming data:

1. **addBytes()**: Appends new bytes to buffer
2. **_tryParse()**: Attempts to parse complete messages
3. **_findCRLF()**: Locates first `\r\n` marker
4. **_advance()**: Removes processed bytes from buffer

### Partial Frame Handling

Messages span multiple frames and may arrive in chunks:

```
Frame 1: "MSG subject 1 5\r\nHel"
Frame 2: "lo\r\n"
         └───┘─ Combined into complete message
```

The parser:
- Collects bytes until complete message is available
- Does NOT parse incomplete messages (returns early)
- Maintains buffer across `addBytes()` calls

### MSG/HMSG Parsing Flow

```
1. Parse control line: MSG <subject> <sid> [reply] <bytes>
2. Calculate required buffer size:
   - ctrlLen = controlLine.length + 2 (for \r\n)
   - requiredLen = ctrlLen + totalBytes + 2 (for trailing \r\n)
3. If buffer.length < requiredLen → return false (wait)
4. Extract payload from buffer[ctrlLen : ctrlLen + totalBytes]
5. For HMSG: parse header section first
   - Header bytes: buffer[ctrlLen : ctrlLen + hdrBytes]
   - Payload: buffer[ctrlLen + hdrBytes : ctrlLen + totalBytes]
6. Emit NatsMessage
7. Advance buffer by requiredLen
8. Return true (consumed)
```

---

## Connection Lifecycle States

The `NatsConnection` manages client lifecycle through several states.

### State Diagram

```
         connect()
            │
            ▼
    ┌──────────────┐
    │ CONNECTING   │ ←─────────────────┐
    └──────────────┘                   │
            │                          │
            │ INFO received            │ Connection lost
            │ CONNECT sent             │ or error
            ▼                          │
    ┌──────────────┐                   │
    │  CONNECTED   │ ──────────────────┘
    └──────────────┘
            │
            │ drain() called
            ▼
    ┌──────────────┐
    │  DRAINING    │
    └──────────────┘
            │
            │ in-flight complete
            ▼
    ┌──────────────┐
    │    CLOSED    │
    └──────────────┘
```

### ConnectionStatus Enum

```dart
enum ConnectionStatus {
  connecting,    // Initial connection attempt
  connected,     // Successfully connected
  reconnecting,  // Lost connection, attempting reconnect
  draining,      // Graceful shutdown in progress
  closed,        // Connection terminated
}
```

### State Transitions

| From | To | Trigger |
|------|----|---------| 
| - | `connecting` | `connect()` called |
| `connecting` | `connected` | CONNECT acknowledged |
| `connecting` | `closed` | Connection error |
| `connected` | `reconnecting` | Transport error / PING timeout |
| `connected` | `draining` | `drain()` called |
| `connected` | `closed` | `close()` called |
| `reconnecting` | `connected` | Reconnection successful |
| `reconnecting` | `closed` | Max attempts reached |
| `draining` | `closed` | Drain complete |

---

## Reconnection Algorithm

The client automatically reconnects with exponential backoff.

### Flow

```
┌─────────────────────────────────────────┐
│  Transport error detected               │
│  (disconnect, PING timeout, etc.)      │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Set _isReconnecting = true             │
│  Emit ConnectionStatus.reconnecting     │
└─────────────────────────────────────────┘
              │
              ▼
    ┌────────────────────┐
    │  Attempt Loop      │◄─────┐
    └────────────────────┘      │
              │                  │
              │ Wait (delay)     │
              ▼                  │
    ┌────────────────────┐      │
    │  Create transport  │      │
    │  Connect to server │      │
    └────────────────────┘      │
              │                  │
        ┌─────┴─────┐            │
        │           │            │
    Success        Failure       │
        │           │            │
        │           ▼            │
        │   ┌──────────────┐     │
        │   │ Increment    │     │
        │   │ attempts     │     │
        │   │ Double delay │     │
        │   └──────────────┘     │
        │           │            │
        │           └────────────┘
        │           (if attempts < max)
        │
        ▼
┌─────────────────────────────────────────┐
│  Wait for INFO                          │
│  (timeout: 3 seconds)                   │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Send CONNECT with auth                 │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Replay subscriptions (send SUB cmds)   │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  Flush buffered publishes               │
│  Set _isConnected = true                │
│  Set _isReconnecting = false            │
│  Emit ConnectionStatus.connected        │
└─────────────────────────────────────────┘
```

### Exponential Backoff

```dart
Duration delay = options.reconnectDelay;  // Default: 2s

// Each failed attempt doubles the delay:
delay = Duration(milliseconds: delay.inMilliseconds * 2);

// 2s → 4s → 8s → 16s → 32s → ...
```

### Subscription Replay

After successful reconnection, all active subscriptions are re-subscribed:

```dart
for (final sub in _subscriptions.values) {
  if (sub.isActive) {
    await _transport.write(NatsEncoder.sub(sub.subject, sub.sid));
  }
}
```

---

## Message Flow

### Publish Flow

```
Client                Server
   │                    │
   │ PUB/HPUB subject   │
   │───────────────────>│
   │                    │ (routes to subscribers)
   │                    │
   │      MSG/HMSG      │
   │<───────────────────│
   │                    │
```

### Request/Reply Flow

```
Client (Requester)    Server              Client (Responder)
   │                    │                     │
   │  PUB with replyTo  │                     │
   │───────────────────>│                     │
   │                    │  MSG with replyTo   │
   │                    │────────────────────>│
   │                    │                     │
   │                    │    PUB to replyTo   │
   │                    │<────────────────────│
   │  MSG (response)    │                     │
   │<───────────────────│                     │
   │                    │                     │
```

---

## Authentication Flow

### Token/Auth

```
1. Server sends INFO (auth_required: true)
2. Client sends CONNECT { "auth_token": "..." }
3. Server validates or sends -ERR
```

### User/Password

```
1. Server sends INFO (auth_required: true)
2. Client sends CONNECT { "user": "...", "pass": "..." }
3. Server validates or sends -ERR
```

### JWT + NKey (Challenge/Response)

```
1. Server sends INFO { "auth_required": true, "nonce": "random" }
2. Client signs nonce with NKey private seed
3. Client sends CONNECT { "jwt": "...", "nkey": "...", "sig": "..." }
4. Server verifies signature against JWT public key
```

---

## Keep-Alive (PING/PONG)

The client sends periodic PING messages to detect connection loss.

```
┌──────────────────────────────────────┐
│  Timer: every options.pingInterval    │
│  (default: 2 minutes)                │
└──────────────────────────────────────┘
              │
              ▼
    ┌─────────────────┐
    │ _pendingPings++ │
    │ Send PING       │
    └─────────────────┘
              │
        ┌─────┴─────┐
        │           │
    PONG received  Timeout
        │           │
        ▼           ▼
   Reset counter  Check pendingPings
                      │
                ┌─────┴─────┐
                │           │
            < maxPings   >= maxPings
                │           │
                ▼           ▼
              Continue    Trigger reconnect
```

---

## Data Structures

### NatsMessage

```dart
class NatsMessage {
  final String subject;              // Message subject
  final String sid;                  // Subscription ID
  final String? replyTo;             // Reply subject
  final Uint8List payload;          // Message data
  final Map<String, List<String>>? headers;  // NATS headers
  final int? statusCode;             // HMSG status code
  final String? statusDesc;          // HMSG status description
  final MessageType type;            // msg, hmsg, info, etc.
}
```

### Subscription

```dart
class Subscription {
  final String sid;              // Unique subscription ID
  final String subject;          // Subscribed subject pattern
  final String? queueGroup;      // Queue group (if any)
  final Stream<NatsMessage> messages;  // Message stream
  bool get isActive;             // Is subscription active
}
```

### ConnectOptions

```dart
class ConnectOptions {
  final String? name;               // Client name
  final int maxReconnectAttempts;   // -1 = infinite
  final Duration reconnectDelay;    // Delay between attempts
  final Duration pingInterval;      // PING frequency
  final int maxPingOut;             // Max unanswered PINGs
  final bool noEcho;                // Don't receive own messages
  final String inboxPrefix;         // Inbox subject prefix
  
  // Authentication (set one)
  final String? authToken;
  final String? user;
  final String? pass;
  final String? jwt;
  final String? nkeyPath;
}
```

---

## See Also

- [Quick Start Guide](quickstart.md)
- [API Contracts](contracts/)
- [Architecture Reference](nats_dart_architecture_reference.md)
