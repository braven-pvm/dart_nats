# Contract: NATS Protocol Wire Specification

**Purpose**: Normalize protocol expectations for parser and encoder implementations  
**Reference**: [NATS Protocol Spec](https://docs.nats.io/reference/reference-protocols/nats-protocol)  
**Status**: Phase 1 Foundation

---

## Protocol Format Overview

All protocol communication is **plain ASCII text** (except binary message payloads) with CRLF (`\r\n`) line endings.

```
<COMMAND> <ARGS>\r\n[PAYLOAD]\r\n
```

---

## Server → Client Commands

### INFO

**Format**:
```
INFO <JSON>\r\n
```

**JSON Fields**:
```json
{
  "server_id": "NDWZ...",
  "version": "2.9.0",
  "proto": 1,
  "go": "go1.19.5",
  "host": "0.0.0.0",
  "port": 4222,
  "headers": true,
  "max_payload": 1048576,
  "tls_available": false,
  "auth_required": false,
  "connect_urls": ["nats://localhost:4222"],
  "cluster": "nats-1",
  "jetstream": true,
  "nonce": "abc123xyz"
}
```

**Timing**: Sent **immediately** upon client connection (before any handshake)

**Validation**:
- ✅ `headers` MUST be `true` (enforced in Phase 1)
- ✅ `max_payload` parsed and enforced by client
- ℹ️ `nonce` present only if auth_required and client must sign it

---

### MSG

**Format** (no headers):
```
MSG <subject> <sid> <reply-to> <bytes>\r\n<payload>\r\n
```

**Example**:
```
MSG notifications.123 1 inbox.sub.1 13
Hello, world!
```

**Fields**:
- `<subject>`: Message subject (e.g., `notifications.123`)
- `<sid>`: Subscription ID (allocated by client via SUB command)
- `<reply-to>`: Reply-to subject (`_EMPTY_` or empty if no reply)
- `<bytes>`: Payload size in bytes

**Parsing Rules**:
- Header line ends with `\r\n`
- Payload is exactly `<bytes>` bytes of binary data
- Message ends with `\r\n` after payload

---

### HMSG

**Format** (with headers):
```
HMSG <subject> <sid> [reply-to] <header-bytes> <total-bytes>\r\n<headers>\r\n\r\n<payload>\r\n
```

**Example**:
```
HMSG orders.created 2 inbox.reply.1 78 100
NATS/1.0
Nats-Msg-Id: order-123
Content-Type: application/json

{"order_id":"123","total":99.99}
```

**Fields**:
- `<subject>`, `<sid>`, `<reply-to>`: Same as MSG
- `<header-bytes>`: Bytes from `NATS/1.0\r\n` to final `\r\n` before empty line
- `<total-bytes>`: `<header-bytes> + payload bytes`

**Header Format**:
```
NATS/1.0\r\n
<header-name>: <value>\r\n
<header-name>: <value>\r\n
\r\n
<payload>
```

**Parsing Rules**:
- First line is always `NATS/1.0`
- Headers are `Header-Name: value` pairs (case-insensitive key, case-sensitive value)
- Multi-value headers: Client may receive multiple `Header-Name` entries
- Empty line separates headers from payload
- First header line following empty line is payload start

**Status Code Line** (first header value, space-separated):
```
NATS/1.0 <code> <description>\r\n
```

**Status Codes**:
- `100 Idle Heartbeat` — Flow control / keepalive
- `100 Flow Control Request` — JetStream flow control
- `101 Idle HeartBeat` — Typo variant (accept both)
- `404 No Messages` — No messages available (pull consumer)
- `408 Request Timeout` — Pull request timed out
- `409 Message Size Exceeds MaxBytes` — Pull response too large
- `503 Service Unavailable` — Temporary service issue

---

### PING & PONG

**Format**:
```
PING\r\n
PONG\r\n
```

**Behavior**:
- Server sends **PING** every `pingInterval` (client configured, default 2 minutes)
- Client **MUST** respond with **PONG**
- If client misses `maxPingOut` PINGs without PONG, server closes connection
- Client may send PING; server responds with PONG (useful for latency measurement)

---

### +OK & -ERR

**Format**:
```
+OK\r\n
-ERR '<error-message>'\r\n
```

**Timing**:
- `+OK` after client sends CONNECT command (if no auth errors)
- `-ERR` on protocol violations or auth errors

**Example Errors**:
```
-ERR 'Authentication Required'
-ERR 'Invalid Protocol'
-ERR 'Payload size is 5M, max_payload is 1M'
```

---

## Client → Server Commands

### CONNECT

**Format**:
```
CONNECT <JSON>\r\n
```

**JSON Fields**:
```json
{
  "name": "my-client",
  "lang": "dart",
  "version": "1.0.0",
  "proto": 1,
  "verbose": false,
  "pedantic": false,
  "tls_required": false,
  "headers": true,
  "no_responders": false,
  "auth_token": "token",
  "jwt": "eyJh...",
  "sig": "sig-hex",
  "nkey": "public-key",
  "user": "alice",
  "pass": "password",
  "echo": true
}
```

**Timing**: Sent **immediately** after receiving INFO

**Fields**:
- `name`: Client name (optional, for monitoring)
- `lang`: Language identifier (always `dart` for nats_dart)
- `version`: Library version (e.g., `1.0.0`)
- `proto`: Protocol version (always `1`)
- `headers`: MUST be `true` (Phase 1+)
- Auth fields (exactly one):
  - `auth_token`: Token authentication
  - `user` + `pass`: Basic auth
  - `jwt` + `sig`: JWT auth (sig is hex-encoded signature)
  - `nkey`: Public NKey (for nonce signing)

---

### PUB

**Format**:
```
PUB <subject> <reply-to> <bytes>\r\n<payload>\r\n
```

**Example**:
```
PUB user.updated  5
{"id":1}
```

**Fields**:
- `<subject>`: Destination subject
- `<reply-to>`: Reply-to subject (optional, omit if no reply expected) — use `_EMPTY_` if present but empty
- `<bytes>`: Exact payload size

**Validation**:
- Payload size cannot exceed `max_payload` from INFO
- Subject must be valid (no empty string)

---

### HPUB

**Format**:
```
HPUB <subject> [reply-to] <header-bytes> <total-bytes>\r\n<headers>\r\n\r\n<payload>\r\n
```

**Example**:
```
HPUB orders.created  100 150
NATS/1.0
Nats-Msg-Id: order-123

{"id":"123"}
```

**Byte Counting** (CRITICAL FOR CORRECTNESS):
```
header-bytes = len("NATS/1.0\r\n") + len(headers) + len("\r\n\r\n")
             = 10 + len(headers) + 4
total-bytes  = header-bytes + len(payload)
```

**Example Calculation**:
```
Headers: "NATS/1.0\r\nNats-Msg-Id: order-123\r\n"
       = 10 + 27 = 37
Final:   "NATS/1.0\r\nNats-Msg-Id: order-123\r\n\r\n"
       = 37 + 4 = 41 (header-bytes)
```

**Validation**:
- `header-bytes` and `total-bytes` must be **exact**
- Off-by-one errors cause parser misalignment and data corruption
- Test with reference implementation (nats.deno)

---

### SUB

**Format**:
```
SUB <subject> [queue-group] <sid>\r\n
```

**Example**:
```
SUB notifications.> sub-1
SUB tasks.process workers task-sub-2
```

**Fields**:
- `<subject>`: Subject pattern (supports `*` and `>` wildcards)
- `[queue-group]`: Optional queue group for load balancing
- `<sid>`: Subscription ID (client-allocated, typically NUID)

**Wildcard Semantics**:
- `*`: Match single token (e.g., `FOO.*.BAR` matches `FOO.abc.BAR` but not `FOO.a.b.BAR`)
- `>`: Match zero or more tokens (e.g., `FOO.>` matches `FOO`, `FOO.abc`, `FOO.a.b.c`)

---

### UNSUB

**Format**:
```
UNSUB <sid> [max-msgs]\r\n
```

**Example**:
```
UNSUB sub-1
UNSUB sub-2 100
```

**Fields**:
- `<sid>`: Subscription ID to unsubscribe
- `[max-msgs]`: Optional maximum messages before auto-unsubscribe (for drain behavior)

**Behavior**:
- With `max-msgs`: Deliver up to N more messages, then auto-unsub
- Without: Unsubscribe immediately (may drop in-flight messages)

---

## Implementation Checklist

### Parser

- [ ] Parse INFO command and extract JSON
- [ ] Parse MSG command (4-field, no headers)
- [ ] Parse HMSG command (5-field, with headers and status code)
- [ ] Parse PING and PONG
- [ ] Parse +OK response
- [ ] Parse -ERR response with error message
- [ ] Handle partial frames (message split across packets)
- [ ] Handle binary payloads (non-UTF8 safe)
- [ ] Validate `<bytes>` count matches actual payload
- [ ] Extract multi-value headers
- [ ] Normalize header keys to case-insensitive lookup
- [ ] Emit parsed NatsMessage with convenience getters (isFlowCtrl, isHeartbeat, etc.)

### Encoder

- [ ] Generate CONNECT with proper JSON serialization
- [ ] Generate PUB with correct byte count
- [ ] Generate HPUB with **exact** header-bytes and total-bytes calculation
- [ ] Generate SUB with optional queue group
- [ ] Generate UNSUB with optional max-msgs
- [ ] Generate PING and PONG
- [ ] Test byte counts against reference implementation

### Edge Cases

- [ ] Handle message split across multiple TCP packets (stateful buffering)
- [ ] Handle 0-byte payloads (empty messages allowed)
- [ ] Handle `max_payload` exceeded (throw error on publish)
- [ ] Handle malformed HMSG (missing empty line separator)
- [ ] Handle unknown status codes (pass through, don't fail)
- [ ] Handle very large payloads (streaming, not buffering entire message)

---

## Reference Implementations

- [nats.deno](https://github.com/nats-io/nats.deno/blob/main/nats-base-client/parser.ts) — Reference parser
- [nats.py](https://github.com/nats-io/nats.py) — Python variant
- [NATS Spec](https://docs.nats.io/reference/reference-protocols/nats-protocol) — Official spec

---

**Status**: Ready for implementation phase  
**Next**: Transport interface contract
