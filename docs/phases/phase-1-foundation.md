# Phase 1: Foundation & Core Client

**Status**: Ready for Spec'ing  
**Duration Estimate**: 2-3 weeks  
**Dependencies**: None  
**Milestone**: All Flutter platforms can pub/sub/request with reconnection

---

## Overview

Phase 1 establishes the foundation for the entire `nats_dart` package. It implements the core NATS protocol without JetStream, focusing on reliable pub/sub, request/reply, and platform abstraction. This phase delivers a working NATS client that can connect from any Flutter platform (native & web) to a NATS server.

**Key Architectural Principle**: Pure Dart protocol layer with platform-specific transport abstraction via conditional imports.

---

## Scope

### 1.1 Protocol Parser

**Goal**: Stateful byte-buffer parser that handles all core NATS protocol commands.

**Deliverables**:
- `NatsParser` class with stateful buffer management
- Parse MSG (messages without headers)
- Parse HMSG (messages with headers including status codes)
- Parse INFO (server capabilities JSON)
- Parse PING/PONG (keepalive)
- Parse +OK/-ERR (acknowledgments and errors)
- Handle partial frames (messages spanning multiple TCP packets)
- Header section parser (NATS/1.0 status line + key:value pairs)
- Extract status codes (100, 404, 408, 409) from HMSG

**Critical Requirements**:
- Must be platform-agnostic (no IO dependencies)
- Must handle multi-frame messages correctly
- Must parse headers as `Map<String, List<String>>` (multi-value support)
- Must extract status code and description from `NATS/1.0 XXX Description` line

**Reference**: Architecture doc § 4 (Protocol Parser)

---

### 1.2 Protocol Encoder

**Goal**: Generate byte-perfect NATS protocol commands.

**Deliverables**:
- `NatsEncoder` class with static methods
- Encode CONNECT (JSON payload with auth fields)
- Encode PUB (subject, optional reply-to, payload)
- Encode HPUB (subject, optional reply-to, headers, payload) with **exact byte counting**
- Encode SUB (subject, optional queue group, subscription ID)
- Encode UNSUB (subscription ID, optional max messages)
- Encode PING/PONG

**Critical Requirements**:
- HPUB header byte count must include `NATS/1.0\r\n`, all headers, and trailing `\r\n\r\n`
- HPUB total byte count = header bytes + payload bytes
- CONNECT JSON must include `headers: true` to enable HPUB/HMSG
- All commands must end with `\r\n`

**Reference**: Architecture doc § 1.4, § 1.3, § 3 encoder examples

---

### 1.3 Transport Abstraction

**Goal**: Platform-agnostic connection interface with compile-time platform selection.

**Deliverables**:
- `Transport` abstract interface with:
  - `Stream<Uint8List> get incoming`
  - `Future<void> write(Uint8List data)`
  - `Future<void> close()`
  - `bool get isConnected`
  - `Stream<Object> get errors`
- `TcpTransport` (dart:io Socket) for native platforms
- `WebSocketTransport` (web_socket_channel) for all platforms
- `transport_factory.dart` with conditional imports:
  - `transport_factory_stub.dart` (default export)
  - `transport_factory_io.dart` (dart:io available)
  - `transport_factory_web.dart` (dart:html available)
- Factory auto-converts `nats://` → `tcp://` or `ws://` based on platform

**Critical Requirements**:
- Use `export 'file.dart' if (dart.library.io) 'io_file.dart'` pattern
- No runtime `kIsWeb` checks — all platform selection at compile time
- WebSocket must work on both native and web platforms
- Factory must coerce `nats://` to `ws://` on web, `tcp://` on native

**Reference**: Architecture doc § 3.2 (Conditional Imports)

---

### 1.4 NUID Generator

**Goal**: Thread-safe unique ID generator for inboxes, subscription IDs, and message IDs.

**Deliverables**:
- `Nuid` class with:
  - `String next()` — generates next unique ID
  - `String inbox([String prefix = '_INBOX'])` — generates inbox subject
- Base62 encoding (0-9A-Za-z)
- 22-character output (12-char prefix + 10-char sequence)
- Cryptographically random prefix using `Random.secure()`
- Prefix randomization when sequence wraps
- Increment value randomized per prefix to prevent collisions

**Critical Requirements**:
- Must be thread-safe (use isolate-local instance or synchronized access)
- Sequence must wrap at `_maxSeq = 839299365868340224` (62^10)
- Port directly from `nats.deno/nats-base-client/nuid.ts`

**Reference**: Architecture doc § 6 (NUID Generator)

---

### 1.5 NatsConnection — Core Client

**Goal**: High-level NATS client API with pub/sub, request/reply, and lifecycle management.

**Deliverables**:
- `NatsConnection` class with:
  - `static Future<NatsConnection> connect(String url, {ConnectOptions? options})`
  - `Future<void> publish(String subject, Uint8List data, {String? replyTo, Map<String, String>? headers})`
  - `Future<NatsMessage> request(String subject, Uint8List data, {Duration timeout})`
  - `Subscription subscribe(String subject, {String? queueGroup})`
  - `Future<void> unsubscribe(Subscription sub)`
  - `Stream<ConnectionStatus> get status`
  - `Future<void> drain()`
  - `Future<void> close()`
- Connection lifecycle management (connecting, connected, reconnecting, closed)
- INFO parsing to extract server capabilities
- CONNECT with `headers: true`, `verbose: false`, auth fields
- PING/PONG keepalive responder
- Error handling for -ERR messages

**Critical Requirements**:
- Must send CONNECT immediately after receiving INFO
- Must respond to PING with PONG automatically
- Must use HPUB when `headers` parameter is provided
- Must validate `headers: true` in server INFO before allowing HPUB

**Reference**: Architecture doc § 3.4 (NatsConnection Public API)

---

### 1.6 Subscription Management

**Goal**: Stream-based subscription API with automatic ID allocation and cleanup.

**Deliverables**:
- `Subscription` class exposing `Stream<NatsMessage> get messages`
- Internal subscription ID (SID) allocation using NUID
- SUB command sent on subscribe()
- UNSUB command sent on unsubscribe()
- Auto-unsub after N messages support
- Queue group support in SUB command

**Critical Requirements**:
- Must maintain internal map of SID → Subscription
- Must route incoming MSG/HMSG to correct subscription by SID
- Must support wildcards (`*`, `>`) in subject patterns
- Must clean up subscription state on unsubscribe

**Reference**: Architecture doc § 3.4, § 1.1 (SUB/UNSUB commands)

---

### 1.7 Request/Reply Pattern

**Goal**: Implement request/reply using unique inbox subscriptions.

**Deliverables**:
- `Future<NatsMessage> request(String subject, Uint8List data, {Duration timeout})`
- Create unique inbox using NUID
- Subscribe to inbox before publishing request
- Publish with inbox as reply-to
- Wait for first response or timeout
- Auto-unsubscribe after receiving reply

**Critical Requirements**:
- Must subscribe BEFORE publishing to avoid race condition
- Must timeout properly using `Stream.timeout()`
- Must unsubscribe even on timeout

**Reference**: Architecture doc § 3.4 (request method)

---

### 1.8 Authentication

**Goal**: Support all NATS authentication modes.

**Deliverables**:
- `ConnectOptions` with auth fields:
  - `authToken` (simple token)
  - `user` + `pass` (username/password)
  - `jwt` + `nkeyPath` (JWT with NKey signing)
  - `nkey` + signed nonce (NKey challenge)
- Parse `auth_required` and `nonce` from INFO
- Sign nonce using NKey seed file (requires NKey crypto library or manual seed parsing)
- Populate CONNECT JSON with appropriate auth fields

**Critical Requirements**:
- Must validate exactly one auth method is set
- Must read NKey seed file from disk (native) or passed as string (web)
- Must support public/private key parsing for NKey auth
- JWT signature verification is server-side (client only signs nonce)

**Reference**: Architecture doc § 7.1, § 7.2 (Authentication)

---

### 1.9 Reconnection & Subscription Replay

**Goal**: Automatic reconnection with transparent subscription restoration.

**Deliverables**:
- `ConnectOptions` with:
  - `maxReconnectAttempts` (default: -1 for infinite)
  - `reconnectDelay` (default: 2 seconds)
- Auto-reconnect on transport error
- Replay all active subscriptions (re-send SUB commands)
- Emit `ConnectionStatus.reconnecting` → `ConnectionStatus.connected` events
- Exponential backoff or fixed delay (start with fixed)
- Fail permanently after max attempts exceeded (unless -1)

**Critical Requirements**:
- Must maintain subscription state across reconnects
- Must not lose queued publishes (buffer during reconnect)
- Must replay subscriptions in original order
- Must handle INFO/CONNECT handshake on each reconnect

**Reference**: Architecture doc § 7.3 (Reconnection & Subscription Replay)

---

### 1.10 ConnectOptions & Configuration

**Goal**: Flexible client configuration.

**Deliverables**:
- `ConnectOptions` class with:
  - `name` (client name for monitoring)
  - `maxReconnectAttempts` (default: -1)
  - `reconnectDelay` (default: 2s)
  - `pingInterval` (default: 2min)
  - `maxPingOut` (default: 2)
  - `noEcho` (don't receive own publishes)
  - `inboxPrefix` (default: '_INBOX')
  - Auth fields (token, user/pass, jwt, nkey)
- Defaults match nats.deno behavior

**Reference**: Architecture doc § 3.5 (ConnectOptions)

---

### 1.11 NatsMessage Model

**Goal**: Unified message representation for MSG and HMSG.

**Deliverables**:
- `NatsMessage` class with:
  - `String subject`
  - `String sid`
  - `String? replyTo`
  - `Uint8List payload`
  - `Map<String, List<String>>? headers`
  - `int? statusCode`
  - `String? statusDesc`
- Convenience getters:
  - `bool get isFlowCtrl` (status 100, "FlowControl")
  - `bool get isHeartbeat` (status 100, "Idle")
  - `bool get isNoMsg` (status 404)
  - `bool get isTimeout` (status 408)
  - `String? header(String name)` (first value)
  - `List<String>? headerAll(String name)` (all values)

**Reference**: Architecture doc § 4.4 (NatsMessage Model)

---

## Test Requirements

### Unit Tests (No Server Required)
- Parser: MSG, HMSG, INFO, PING, +OK, -ERR with pre-recorded bytes
- Parser: Partial frames (split messages across multiple addBytes calls)
- Parser: HMSG status codes (100, 404, 408, 409)
- Parser: Multi-value headers
- Encoder: PUB, HPUB byte-perfect output
- Encoder: HPUB header byte counting (validate against examples)
- Encoder: CONNECT JSON serialization
- NUID: Format validation, uniqueness, sequence wraparound

### Integration Tests (Docker NATS Server)
- TCP transport: connect, write, read, close
- WebSocket transport: connect `ws://`, disconnect
- Core pub/sub: round-trip message delivery
- Request/reply: timeout, successful response
- Queue groups: load balancing across subscribers
- Wildcards: `*` and `>` subscription matching
- Auth: token, user/pass (NKey/JWT if library available)
- Reconnection: kill server → auto-reconnect → subscriptions restored
- PING/PONG: server keepalive handling

### Test Coverage Target
- **80%** for protocol layer (parser, encoder)
- **70%** for connection/subscription logic
- **60%** for platform-specific transport (manual verification on Flutter Web)

---

## Acceptance Criteria

1. ✅ All unit tests pass (parser, encoder, NUID)
2. ✅ Integration tests pass against Docker NATS (TCP & WebSocket)
3. ✅ Flutter native example connects via TCP and does pub/sub
4. ✅ Flutter web example connects via WebSocket and does pub/sub
5. ✅ Reconnection restores subscriptions successfully
6. ✅ Request/reply works with timeout handling
7. ✅ No `dart:io` or `dart:html` imports outside `transport/` directory
8. ✅ `dart analyze` shows no warnings
9. ✅ `dart format` applied to all code

---

## Dependencies & Blockers

**External Dependencies**:
- `web_socket_channel` package (already in pubspec)
- Docker + `nats:latest` image for testing
- Optional: NKey crypto library for JWT/NKey auth (can defer to Phase 2 if unavailable)

**Known Unknowns**:
- NKey seed file parsing (may require manual Ed25519 implementation or external package)
- WebSocket CORS configuration for Flutter Web development (server-side config)

---

## Out of Scope (Deferred to Later Phases)

- JetStream (Phase 2)
- KeyValue store (Phase 3)
- TLS support (Phase 3 or post-MVP)
- Cluster discovery beyond basic `connect_urls`/`ws_connect_urls` (Phase 3)
- Message header compression (not in NATS spec)

---

## Reference Implementation

Primary: `nats.deno` (TypeScript)
- `nats-base-client/parser.ts` — Parser state machine
- `nats-base-client/protocol.ts` — Encoder
- `nats-base-client/nuid.ts` — NUID generator
- `nats-base-client/nats.ts` — NatsConnection implementation
- `nats-ws/src/ws_transport.ts` — WebSocket transport
- `nats-deno/src/tcp.ts` — TCP transport

Secondary: `nats.go` (canonical server-side reference for protocol edge cases)

---

## Next Steps After Phase 1

With Phase 1 complete, the package provides:
- ✅ Full core NATS client (pub/sub, request/reply)
- ✅ Cross-platform support (native TCP, browser WebSocket)
- ✅ Reconnection with subscription replay
- ✅ HPUB/HMSG support (required for JetStream)

**Phase 2** will build JetStream on top of this foundation:
- Stream and consumer management via `$JS.API.*` requests
- Pull consumer `fetch()` and `consume()` using HPUB/HMSG
- Message acknowledgment (ack/nak/term)
- Ordered consumer for KV watch semantics
