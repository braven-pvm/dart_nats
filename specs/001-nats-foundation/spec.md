# Feature Specification: NATS Foundation & Core Client

**Feature ID**: 001  
**Phase**: 1 of 3  
**Status**: Draft  
**Created**: February 23, 2026  
**Duration Estimate**: 2-3 weeks

---

## Executive Summary

Implement the foundational layer of `nats_dart` — a Pure Dart NATS client that works across all Flutter platforms (native iOS/Android/desktop and web). This phase establishes the core pub/sub messaging primitives, platform-agnostic protocol handling, and reliable connection management with automatic reconnection.

**Business Value**: Enables real-time messaging infrastructure for Flutter applications without platform-specific code, supporting both production deployments (native TCP) and web previews (WebSocket) with identical application code.

**Key Milestone**: All Flutter platforms can connect to NATS servers, publish/subscribe to subjects, and maintain reliable connections with automatic reconnection.

---

## User Scenarios & Testing

### Scenario 1: Flutter Native App Connects via TCP
**As a** Flutter mobile developer  
**I want to** connect my app to a NATS server using TCP  
**So that** I can send and receive real-time messages with minimal latency

**Acceptance Testing**:
1. Developer imports `package:nats_dart`
2. Calls `await NatsConnection.connect('nats://nats.example.com:4222')`
3. Connection succeeds without requiring platform-specific code
4. Can publish messages and receive subscriptions
5. Connection automatically reconnects if network is interrupted

**Expected Outcome**: Connection established via TCP socket, messages flow bidirectionally, subscriptions are preserved across reconnections.

---

### Scenario 2: Flutter Web App Connects via WebSocket
**As a** Flutter web developer  
**I want to** connect to NATS from browser environments  
**So that** web previews and PWAs can use the same messaging infrastructure

**Acceptance Testing**:
1. Same code from Scenario 1: `await NatsConnection.connect('nats://example.com:4222')`
2. Library automatically uses WebSocket transport (scheme converted to `ws://`)
3. No runtime errors or manual platform detection needed
4. Pub/sub works identically to native platforms

**Expected Outcome**: Browser establishes WebSocket connection, all messaging features work without code changes.

---

### Scenario 3: Request/Reply for RPC-Style Communication
**As a** developer building a microservices architecture  
**I want to** make request/reply calls  
**So that** I can implement RPC-style synchronous communication patterns

**Acceptance Testing**:
1. Service A calls `await connection.request('user.get', userId)`
2. Service B subscribed to `user.get` receives request and publishes reply
3. Service A receives reply or timeout after configurable duration
4. No message loss even if multiple replies arrive

**Expected Outcome**: Request completes successfully with reply data, or times out gracefully after specified duration.

---

### Scenario 4: Connection Resilience During Network Interruption
**As a** mobile app developer  
**I want** automatic reconnection when network is unstable  
**So that** users don't experience message loss during brief connectivity issues

**Acceptance Testing**:
1. App connected and subscribed to subjects
2. Network connection lost (simulate: disconnect WiFi, kill NATS server)
3. Library automatically attempts reconnection with exponential backoff
4. When reconnected, all subscriptions are restored automatically
5. Application receives connection status updates (connected → reconnecting → connected)

**Expected Outcome**: Subscriptions restored after reconnection, no manual intervention required, status events emitted for UI updates.

---

### Scenario 5: Authenticated Connection
**As a** production system operator  
**I want to** authenticate with token, username/password, or NKey credentials  
**So that** only authorized clients can access the messaging infrastructure

**Acceptance Testing**:
1. NATS server configured with authentication required
2. Client provides credentials via `ConnectOptions`
3. Connection succeeds with valid credentials
4. Connection rejected with invalid credentials (clear error message)

**Expected Outcome**: Valid credentials grant access, invalid credentials fail fast with actionable error message.

---

## Functional Requirements

### FR-1: Protocol Parser (Platform-Agnostic)
**Priority**: Critical  
**Description**: Implement stateful byte-buffer parser that handles all core NATS protocol commands (MSG, HMSG, INFO, PING, PONG, +OK, -ERR).

**Requirements**:
- FR-1.1: Parse MSG format: `MSG <subject> <sid> [reply] <bytes>\r\n<payload>\r\n`
- FR-1.2: Parse HMSG format with headers: `HMSG <subject> <sid> [reply] <hdr_bytes> <total_bytes>\r\n<headers>\r\n\r\n<payload>\r\n`
- FR-1.3: Parse INFO command with JSON server capabilities
- FR-1.4: Parse PING/PONG keepalive commands
- FR-1.5: Parse +OK acknowledgment and -ERR error messages
- FR-1.6: Handle partial frames (messages split across multiple network packets)
- FR-1.7: Extract headers as `Map<String, List<String>>` supporting multi-value headers
- FR-1.8: Parse status codes from HMSG first line: `NATS/1.0 <code> <description>`
- FR-1.9: No dependencies on `dart:io` or `dart:html` (Pure Dart)

**Acceptance Criteria**:
- Parser correctly identifies all protocol commands
- Handles messages spanning multiple byte chunks
- Extracts status codes 100, 404, 408, 409 from HMSG
- Multi-value headers preserved (e.g., multiple `BREAKFAST: value` entries)

---

### FR-2: Protocol Encoder (Byte-Perfect Output)
**Priority**: Critical  
**Description**: Generate byte-perfect NATS protocol commands with exact byte counting for HPUB.

**Requirements**:
- FR-2.1: Encode CONNECT command with JSON payload including auth fields and `headers: true`
- FR-2.2: Encode PUB command: `PUB <subject> [reply] <bytes>\r\n<payload>\r\n`
- FR-2.3: Encode HPUB command with exact byte counting:
  - Header bytes = length of `NATS/1.0\r\n` + all header lines + trailing `\r\n\r\n`
  - Total bytes = header bytes + payload bytes
- FR-2.4: Encode SUB command: `SUB <subject> [queue] <sid>\r\n`
- FR-2.5: Encode UNSUB command: `UNSUB <sid> [max_msgs]\r\n`
- FR-2.6: Encode PING/PONG commands
- FR-2.7: All commands terminate with `\r\n`

**Acceptance Criteria**:
- HPUB byte counts match server expectations exactly
- CONNECT includes `headers: true` to enable HMSG support
- Generated bytes match reference implementation output

---

### FR-3: Transport Abstraction (Compile-Time Platform Selection)
**Priority**: Critical  
**Description**: Abstract network transport with compile-time platform-specific implementations.

**Requirements**:
- FR-3.1: Define `Transport` interface with:
  - `Stream<Uint8List> get incoming` (receive bytes)
  - `Future<void> write(Uint8List data)` (send bytes)
  - `Future<void> close()` (disconnect)
  - `bool get isConnected` (connection state)
  - `Stream<Object> get errors` (transport errors)
- FR-3.2: Implement `TcpTransport` using `dart:io.Socket` for native platforms
- FR-3.3: Implement `WebSocketTransport` using `web_socket_channel` for all platforms
- FR-3.4: Use conditional imports in `transport_factory.dart`:
  - `if (dart.library.io)` → export TCP factory
  - `if (dart.library.html)` → export WebSocket-only factory
- FR-3.5: Factory auto-converts schemes:
  - Native: `nats://` → TCP on port 4222
  - Web: `nats://` → `ws://` on port 9222 (or configured WebSocket port)
- FR-3.6: No runtime `kIsWeb` checks (compile-time selection only)

**Acceptance Criteria**:
- Native builds exclude WebSocket-specific code
- Web builds exclude TCP-specific code  
- Same connection API works on all platforms
- Transport errors propagate to connection layer

---

### FR-4: NUID Generator (Unique IDs)
**Priority**: Critical  
**Description**: Thread-safe base62 unique ID generator for inboxes and subscription IDs.

**Requirements**:
- FR-4.1: Generate 22-character base62 IDs (0-9A-Za-z)
- FR-4.2: Format: 12-character cryptographic random prefix + 10-character sequence
- FR-4.3: Sequence increments with random step (prevents collision prediction)
- FR-4.4: Prefix randomizes when sequence reaches max value (`62^10`)
- FR-4.5: Use `Random.secure()` for cryptographic randomness
- FR-4.6: Provide `inbox(String prefix)` method for inbox subject generation (default `_INBOX`)
- FR-4.7: Thread-safe for isolate usage

**Acceptance Criteria**:
- Generated IDs are unique across multiple instances
- No collisions in stress tests (1M+ IDs generated)
- Prefix rolls over correctly at sequence limit

---

### FR-5: NatsConnection (Core Client API)
**Priority**: Critical  
**Description**: High-level connection API with pub/sub, request/reply, and lifecycle management.

**Requirements**:
- FR-5.1: Static factory: `Future<NatsConnection> connect(String url, {ConnectOptions? options})`
- FR-5.2: Publish method: `Future<void> publish(String subject, Uint8List data, {String? replyTo, Map<String, String>? headers})`
- FR-5.3: Request method: `Future<NatsMessage> request(String subject, Uint8List data, {Duration timeout})`
- FR-5.4: Subscribe method: `Subscription subscribe(String subject, {String? queueGroup})`
- FR-5.5: Unsubscribe method: `Future<void> unsubscribe(Subscription sub)`
- FR-5.6: Connection status stream: `Stream<ConnectionStatus> get status`
- FR-5.7: Drain method: `Future<void> drain()` (flush pending messages, close gracefully)
- FR-5.8: Close method: `Future<void> close()` (immediate disconnect)
- FR-5.9: Parse INFO from server to extract capabilities (`headers`, `jetstream`, `max_payload`)
- FR-5.10: Send CONNECT with `headers: true`, `verbose: false`, auth fields
- FR-5.11: Automatically respond to PING with PONG
- FR-5.12: Use HPUB when headers are provided, PUB otherwise

**Acceptance Criteria**:
- Connections complete INFO/CONNECT handshake successfully
- Publish and subscribe work for arbitrary subjects
- PING/PONG keepalive handled transparently
- Status stream emits state changes (connecting, connected, reconnecting, closed)

---

### FR-6: Subscription Management
**Priority**: Critical  
**Description**: Stream-based subscription API with automatic ID allocation.

**Requirements**:
- FR-6.1: `Subscription` class exposes `Stream<NatsMessage> get messages`
- FR-6.2: Allocate unique subscription ID (SID) using NUID
- FR-6.3: Send SUB command on subscribe: `SUB <subject> [queueGroup] <sid>\r\n`
- FR-6.4: Route incoming MSG/HMSG to correct subscription by matching SID
- FR-6.5: Auto-unsubscribe support: `UNSUB <sid> <max_msgs>\r\n` (optional)
- FR-6.6: Queue group support (multiple subscribers share load)
- FR-6.7: Wildcard subject patterns (`*` single-token, `>` multi-token)
- FR-6.8: Maintain internal SID → Subscription map
- FR-6.9: Clean up subscription state on unsubscribe

**Acceptance Criteria**:
- Messages delivered only to matching subscriptions
- Wildcards match correctly (`FOO.*` matches `FOO.bar`, not `FOO.bar.baz`)
- Queue groups distribute messages across subscribers
- Auto-unsubscribe triggers after N messages

---

### FR-7: Request/Reply Pattern
**Priority**: High  
**Description**: Synchronous request/reply using unique inbox subscriptions.

**Requirements**:
- FR-7.1: Generate unique inbox subject using NUID (e.g., `_INBOX.abc123`)
- FR-7.2: Subscribe to inbox BEFORE publishing request
- FR-7.3: Publish request with inbox as reply-to subject
- FR-7.4: Wait for first reply message or timeout
- FR-7.5: Auto-unsubscribe after receiving reply (or on timeout)
- FR-7.6: Timeout using `Stream.timeout()` with configurable duration (default 10s)
- FR-7.7: Return `NatsMessage` on success, throw `TimeoutException` on timeout

**Acceptance Criteria**:
- Requests complete successfully when reply received
- Timeout throws exception with clear message
- No subscription leak (auto-cleanup on completion/timeout)
- Race condition avoided (subscribe before publish)

---

### FR-8: Authentication
**Priority**: High  
**Description**: Support multiple NATS authentication modes.

**Requirements**:
- FR-8.1: Token authentication: `ConnectOptions(authToken: 'token')`
- FR-8.2: Username/password: `ConnectOptions(user: 'alice', pass: 'secret')`
- FR-8.3: NKey authentication:
  - Read NKey seed from file or string
  - Sign server nonce from INFO
  - Include signature in CONNECT
- FR-8.4: JWT authentication:
  - Accept JWT string
  - Sign nonce with NKey
  - Include both JWT and signature in CONNECT
- FR-8.5: Validate exactly one auth method provided
- FR-8.6: Parse `auth_required` and `nonce` from INFO
- FR-8.7: Clear error messages on auth failure

**Acceptance Criteria**:
- Token auth connects successfully to token-protected server
- User/pass auth connects successfully to user-protected server
- NKey/JWT auth connects successfully to NKey-protected server
- Invalid credentials fail with actionable error message
- No credentials work with open servers

---

### FR-9: Reconnection & Subscription Replay
**Priority**: High  
**Description**: Automatic reconnection with transparent subscription restoration.

**Requirements**:
- FR-9.1: Detect transport disconnection via errors stream
- FR-9.2: Attempt reconnection with configurable retry count (default: infinite `-1`)
- FR-9.3: Delay between attempts with configurable duration (default: 2s)
- FR-9.4: Emit status events: `reconnecting` → `connected` or `closed`
- FR-9.5: Replay all active subscriptions (re-send SUB commands)
- FR-9.6: Buffer publishes during reconnection (queue for retry)
- FR-9.7: Preserve subscription order during replay
- FR-9.8: Fail permanently after max attempts exceeded (unless infinite)
- FR-9.9: Re-execute INFO/CONNECT handshake on each reconnect

**Acceptance Criteria**:
- Subscriptions restored after reconnection verified
- Status events emitted correctly
- Buffered publishes sent after reconnection
- Reconnection stops after max attempts (if configured)

---

### FR-10: ConnectOptions Configuration
**Priority**: Medium  
**Description**: Flexible client configuration options.

**Requirements**:
- FR-10.1: `name` (string): Client name for monitoring
- FR-10.2: `maxReconnectAttempts` (int): -1 = infinite, 0 = disabled, N = max attempts
- FR-10.3: `reconnectDelay` (Duration): Delay between reconnect attempts (default 2s)
- FR-10.4: `pingInterval` (Duration): Client-side keepalive interval (default 2min)
- FR-10.5: `maxPingOut` (int): Max unresponded PINGs before reconnect (default 2)
- FR-10.6: `noEcho` (bool): Don't receive own publishes (default false)
- FR-10.7: `inboxPrefix` (string): Custom inbox prefix (default `_INBOX`)
- FR-10.8: Auth fields: `authToken`, `user`, `pass`, `jwt`, `nkeyPath`

**Acceptance Criteria**:
- Options applied correctly in CONNECT JSON
- Defaults match nats.deno behavior
- Invalid combinations rejected with clear errors

---

### FR-11: NatsMessage Model
**Priority**: Medium  
**Description**: Unified message representation for MSG and HMSG.

**Requirements**:
- FR-11.1: Fields: `subject`, `sid`, `replyTo`, `payload`, `headers`, `statusCode`, `statusDesc`
- FR-11.2: Convenience getters:
  - `bool get isFlowCtrl` (status 100, description contains "Flow")
  - `bool get isHeartbeat` (status 100, description contains "Idle")
  - `bool get isNoMsg` (status 404)
  - `bool get isTimeout` (status 408)
  - `String? header(String name)` (first value)
  - `List<String>? headerAll(String name)` (all values)
- FR-11.3: Type-safe access to all fields

**Acceptance Criteria**:
- MSG and HMSG both represented as `NatsMessage`
- Status code helpers work correctly
- Header access handles multi-value correctly

---

## Success Criteria

### SC-1: Cross-Platform Compatibility
**Measurement**: Application code runs unchanged on iOS, Android, macOS, Windows, Linux, and Web  
**Target**: 100% code compatibility — no `#if` directives or platform checks in application layer

---

### SC-2: Connection Reliability
**Measurement**: Successful reconnection and subscription restoration after network interruption  
**Target**: 99% subscription recovery rate in integration tests (kill server 100 times, verify 99+ successful reconnections)

---

### SC-3: Message Throughput
**Measurement**: Messages published and delivered per second  
**Target**: 
- Native TCP: ≥ 50,000 msgs/sec on standard hardware
- WebSocket: ≥ 10,000 msgs/sec in Chrome
(Measured with 1KB payload, single publisher/subscriber)

---

### SC-4: Latency
**Measurement**: Round-trip time for request/reply  
**Target**:
- Native TCP: < 5ms median, < 20ms p99 (local network)
- WebSocket: < 15ms median, < 50ms p99 (local network)

---

### SC-5: Test Coverage
**Measurement**: Code coverage percentage  
**Target**:
- Protocol layer (parser, encoder): ≥ 80%
- Connection/subscription logic: ≥ 70%
- Integration tests: All scenarios pass

---

### SC-6: Platform Build Size
**Measurement**: Added application size after including nats_dart  
**Target**:
- Native: < 200KB added to release binary
- Web: < 150KB added to minified bundle (gzip compressed)

---

## Key Entities

### Entity: NatsConnection
**Description**: Main client connection to NATS server  
**Lifecycle**: Created via `connect()`, closed via `close()` or `drain()`  
**Key Operations**: publish, request, subscribe, unsubscribe  
**State**: Connecting → Connected → Reconnecting → Closed

---

### Entity: Subscription
**Description**: Active subscription to subjects with message stream  
**Lifecycle**: Created via `connection.subscribe()`, destroyed via `unsubscribe()`  
**Key Properties**: subject pattern, queue group, subscription ID (SID), message stream

---

### Entity: NatsMessage
**Description**: Received message from server  
**Properties**: subject, payload, headers, reply-to, status code  
**Immutable**: Yes (value object)

---

### Entity: Transport
**Description**: Platform-specific network connection abstraction  
**Implementations**: TcpTransport (native), WebSocketTransport (all platforms)  
**Lifecycle**: Created by factory, closed when connection terminates

---

### Entity: ConnectOptions
**Description**: Configuration for connection behavior and authentication  
**Immutable**: Yes (configuration object)  
**Validation**: Enforces exactly one auth method if auth is used

---

## Assumptions

### A-1: NATS Server Availability
**Assumption**: NATS server version 2.9 or later is available and supports headers (`headers: true` in INFO)  
**Risk**: Older servers may not support HMSG  
**Mitigation**: Validate `headers: true` in INFO, fail fast with clear error if unsupported

---

### A-2: Network Reliability
**Assumption**: Network interruptions are temporary (< 5 minutes) and reconnection will succeed  
**Risk**: Extended outages may exhaust reconnection attempts  
**Mitigation**: Configurable reconnection policy, status events for application monitoring

---

### A-3: UTF-8 Protocol Encoding
**Assumption**: NATS protocol uses UTF-8 for subject names and header keys  
**Risk**: Binary data in subjects may cause parsing errors  
**Mitigation**: Validate subjects are valid UTF-8, document payload as binary (Uint8List)

---

### A-4: Single Isolate Usage
**Assumption**: One NatsConnection per Dart isolate (multi-isolate support not required in Phase 1)  
**Risk**: Applications needing multiple connections may face isolation issues  
**Mitigation**: Document single-isolate limitation, support multiple connections via isolates in future

---

### A-5: WebSocket CORS Configuration
**Assumption**: NATS server WebSocket endpoint is configured with appropriate CORS headers for web clients  
**Risk**: Browser may block WebSocket upgrades  
**Mitigation**: Document required server configuration (`allowed_origins` in nats-server.conf)

---

## Dependencies

### External Dependencies
- **dart:io** (conditional): Native TCP socket support — available in Flutter native
- **dart:html** (conditional): Browser WebSocket support — available in Flutter web
- **web_socket_channel** (package): WebSocket abstraction — already in pubspec.yaml
- **dart:convert** (SDK): JSON encoding/decoding for CONNECT and INFO
- **dart:typed_data** (SDK): Uint8List for binary payload handling
- **dart:async** (SDK): Stream and Future primitives

---

### Development Dependencies
- **test** (package): Unit and integration testing
- **mockito** (package): Mocking transport for unit tests
- **Docker** + **nats:latest**: Integration test environment

---

### Infrastructure Dependencies
- **NATS Server 2.9+**: Running with headers support enabled
- **Docker environment**: For CI/CD integration tests
- **GitHub Actions**: CI pipeline for multi-platform testing

---

## Out of Scope

The following are explicitly deferred to later phases:

### Deferred to Phase 2 (JetStream)
- JetStream stream and consumer management
- JetStream publish with acknowledgment (PubAck)
- Pull consumers and message acknowledgment
- Flow control handling for JetStream

---

### Deferred to Phase 3 (Production Polish)
- KeyValue store API
- TLS/SSL encrypted connections
- Mutual TLS authentication
- Advanced connection pooling
- Metrics and monitoring instrumentation

---

### Post-MVP Enhancements
- Object store API
- Service API (microservices framework)
- Leafnode connections
- Cluster topology discovery
- NATS account JWT generation
- Distributed tracing integration

---

## Technical Constraints

### TC-1: Pure Dart Protocol Layer
**Constraint**: All protocol parsing and encoding must be Pure Dart (no FFI, no platform channels)  
**Rationale**: Ensures code portability and consistent behavior across platforms  
**Impact**: Some performance trade-offs vs native crypto libraries for auth

---

### TC-2: Conditional Imports Only
**Constraint**: Platform selection must use conditional imports, not runtime checks  
**Rationale**: Enables tree-shaking and optimal binary size  
**Impact**: More complex build configuration, careful export management

---

### TC-3: Backward Compatibility
**Constraint**: API must remain stable within Phase 1 (no breaking changes)  
**Rationale**: Enables iterative testing and integration  
**Impact**: Design APIs carefully upfront, use extensible patterns

---

### TC-4: NATS Protocol Compliance
**Constraint**: Must implement NATS protocol spec exactly (byte-for-byte correctness)  
**Rationale**: Interoperability with official NATS servers and clients  
**Impact**: Extensive protocol testing required, reference implementation comparison

---

## Risk Analysis

### Risk 1: NKey Cryptography Complexity
**Probability**: Medium  
**Impact**: High (blocks JWT authentication)  
**Mitigation**: Start with token/user-pass auth, evaluate Ed25519 libraries, defer NKey if complex

---

### Risk 2: WebSocket Platform Differences
**Probability**: Low  
**Impact**: Medium (affects Flutter web deployment)  
**Mitigation**: Use established `web_socket_channel` package, test on multiple browsers

---

### Risk 3: Reconnection Edge Cases
**Probability**: Medium  
**Impact**: High (affects production reliability)  
**Mitigation**: Extensive integration testing with server kill scenarios, chaos engineering

---

### Risk 4: Parser Performance
**Probability**: Low  
**Impact**: Medium (affects throughput)  
**Mitigation**: Profile hot paths, use zero-copy buffers (`BytesBuilder(copy: false)`), optimize incrementally

---

## Testing Strategy

### Unit Tests (No Server)
- Parser: Pre-recorded byte sequences for MSG, HMSG, INFO, PING, +OK, -ERR
- Parser: Partial frame scenarios (split messages)
- Parser: HMSG status code extraction
- Encoder: Byte output validation vs expected strings
- Encoder: HPUB byte counting verification
- NUID: Uniqueness, format, sequence wraparound

---

### Integration Tests (Docker NATS)
- TCP transport: Connect, disconnect, read, write
- WebSocket transport: Connect via `ws://`, message exchange
- Pub/sub: Round-trip message delivery
- Request/reply: Timeout and successful reply
- Queue groups: Load distribution verification
- Wildcards: Subject matching correctness
- Auth: Token, user/pass (NKey if implemented)
- Reconnection: Kill server, verify auto-reconnect and subscription replay

---

### Platform Tests
- Flutter native (iOS simulator): TCP connection, pub/sub
- Flutter native (Android emulator): TCP connection, pub/sub
- Flutter web (Chrome): WebSocket connection, pub/sub
- Automated in CI/CD pipeline

---

### Performance Tests
- Throughput: 10K, 50K, 100K msgs/sec
- Latency: Request/reply round-trip timing (p50, p95, p99)
- Memory: Monitor heap usage under sustained load
- Reconnection: Time to restore 1000 subscriptions

---

## Reference Implementation

**Primary**: `nats.deno` (TypeScript)
- `nats-base-client/parser.ts` — Protocol parser state machine
- `nats-base-client/protocol.ts` — Protocol encoder
- `nats-base-client/nuid.ts` — NUID generator algorithm
- `nats-base-client/nats.ts` — NatsConnection implementation
- `nats-ws/src/ws_transport.ts` — WebSocket transport
- `nats-deno/src/tcp.ts` — TCP transport (Deno-specific, adapt for Dart)

**Secondary**: `nats.go` (Go)
- Use for protocol edge cases and server-side perspective

---

## Architecture References

- **Full Specification**: `docs/nats_dart_architecture_reference.md` — Complete technical details
- **Phase Document**: `docs/phases/phase-1-foundation.md` — Phase 1 implementation guide
- **NATS Protocol Spec**: docs.nats.io/reference/reference-protocols/nats-protocol
- **ADR-4 NATS Headers**: github.com/nats-io/nats-architecture-and-design/blob/main/adr/ADR-4.md

---

## Implementation Notes

### Development Sequence
1. **Week 1**: Parser + Encoder + NUID (Pure Dart, heavily unit tested)
2. **Week 2**: Transport abstraction + NatsConnection + Subscription management
3. **Week 3**: Authentication + Reconnection + Integration tests + Polish

---

### Code Organization
```
lib/src/
├── transport/           # Platform-specific (only place for dart:io/dart:html)
│   ├── transport.dart
│   ├── transport_factory.dart
│   ├── tcp_transport.dart
│   └── websocket_transport.dart
├── protocol/            # Pure Dart (100% portable)
│   ├── parser.dart
│   ├── encoder.dart
│   ├── message.dart
│   └── nuid.dart
├── client/              # Pure Dart (uses transport abstraction)
│   ├── connection.dart
│   ├── subscription.dart
│   └── options.dart
```

---

### Quality Gates
- ✅ All unit tests pass
- ✅ Integration tests pass (TCP + WebSocket)
- ✅ `dart analyze` shows 0 warnings
- ✅ `dart format` applied
- ✅ Example apps run on native and web
- ✅ Code coverage ≥ targets (80% protocol, 70% connection)

---

## Success Metrics

**Phase 1 Complete When**:
1. ✅ Flutter native example connects via TCP and does pub/sub successfully
2. ✅ Flutter web example connects via WebSocket and does pub/sub successfully
3. ✅ Request/reply works with timeout handling
4. ✅ Reconnection restores subscriptions (verified in integration test)
5. ✅ Authentication works (at minimum: token, user/pass)
6. ✅ All acceptance criteria met
7. ✅ No platform-specific code outside `transport/` directory
8. ✅ Ready for Phase 2 (JetStream) development

---

## Questions & Clarifications

**[This section will be populated during spec review if clarifications are needed]**

---

**Spec Version**: 1.0  
**Last Updated**: February 23, 2026  
**Next Review**: Upon implementation start

**Feature Branch**: `[###-feature-name]`  
**Created**: [DATE]  
**Status**: Draft  
**Input**: User description: "$ARGUMENTS"

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.
  
  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - [Brief Title] (Priority: P1)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently - e.g., "Can be fully tested by [specific action] and delivers [specific value]"]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]
2. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 3 - [Brief Title] (Priority: P3)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

[Add more user stories as needed, each with an assigned priority]

### Edge Cases

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right edge cases.
-->

- What happens when [boundary condition]?
- How does system handle [error scenario]?

## Requirements *(mandatory)*

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right functional requirements.
-->

### Functional Requirements

- **FR-001**: System MUST [specific capability, e.g., "allow users to create accounts"]
- **FR-002**: System MUST [specific capability, e.g., "validate email addresses"]  
- **FR-003**: Users MUST be able to [key interaction, e.g., "reset their password"]
- **FR-004**: System MUST [data requirement, e.g., "persist user preferences"]
- **FR-005**: System MUST [behavior, e.g., "log all security events"]

*Example of marking unclear requirements:*

- **FR-006**: System MUST authenticate users via [NEEDS CLARIFICATION: auth method not specified - email/password, SSO, OAuth?]
- **FR-007**: System MUST retain user data for [NEEDS CLARIFICATION: retention period not specified]

### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [What it represents, key attributes without implementation]
- **[Entity 2]**: [What it represents, relationships to other entities]

## Success Criteria *(mandatory)*

<!--
  ACTION REQUIRED: Define measurable success criteria.
  These must be technology-agnostic and measurable.
-->

### Measurable Outcomes

- **SC-001**: [Measurable metric, e.g., "Users can complete account creation in under 2 minutes"]
- **SC-002**: [Measurable metric, e.g., "System handles 1000 concurrent users without degradation"]
- **SC-003**: [User satisfaction metric, e.g., "90% of users successfully complete primary task on first attempt"]
- **SC-004**: [Business metric, e.g., "Reduce support tickets related to [X] by 50%"]
