# Tasks: NATS Foundation & Core Client

**Input**: Design documents from `/specs/001-nats-foundation/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/

**Tests**: This project follows TDD - tests are included for all components (as mandated by constitution.md).

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user scenario this task belongs to (US1-US5)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, directory structure, and test framework setup

- [ ] T001 Verify lib/src directory structure exists (lib/src/transport/, lib/src/protocol/, lib/src/client/, lib/src/kv/, lib/src/jetstream/)
- [ ] T002 Verify test/ directory structure exists (test/unit/, test/integration/)
- [ ] T003 Create placeholder files for Phase 1 exports (lib/nats_dart.dart exports)
- [ ] T004 [P] Create test/unit directory placeholders for parser, encoder, nuid, transport tests
- [ ] T005 [P] Create test/integration directory placeholders for connection, pub/sub, auth tests
- [ ] T006 Verify pubspec.yaml includes web_socket_channel dependency

---

## Phase 2: Foundational Layer (Data Models & ID Generation)

**Purpose**: Core value objects and utilities that ALL subsequent functionality depends on

**⚠️ CRITICAL**: No connection or protocol work can begin until this phase is complete

- [ ] T007 [P] Create NatsMessage model in lib/src/protocol/message.dart (subject, sid, replyTo, payload, headers, statusCode, statusDesc fields)
- [ ] T008 [P] Add NatsMessage convenience getters in lib/src/protocol/message.dart (isFlowCtrl, isHeartbeat, isNoMsg, isTimeout getters)
- [ ] T009 [P] Add NatsMessage header accessor methods in lib/src/protocol/message.dart (header() returns first value, headerAll() returns all values)
- [ ] T010 Create Nuid class in lib/src/protocol/nuid.dart (22-char base62 ID generation, 12-char prefix + 10-char sequence)
- [ ] T011 Implement Nuid.next() method in lib/src/protocol/nuid.dart (generate 22-char base62 ID)
- [ ] T012 Implement Nuid.inbox() method in lib/src/protocol/nuid.dart (generate inbox subject with custom prefix)
- [ ] T013 [P] Create ConnectOptions model in lib/src/client/options.dart (name, maxReconnectAttempts, reconnectDelay, pingInterval, maxPingOut, noEcho, inboxPrefix, auth fields)
- [ ] T014 [P] Create ConnectionStatus enum in lib/src/client/options.dart (connecting, connected, reconnecting, closed)
- [ ] T015 [P] Create Subscription class stub in lib/src/client/subscription.dart (subject, queueGroup, messages stream, _sid field)

**Checkpoint**: Foundation ready - data models complete, protocol parsing and transport can now begin

---

## Phase 3: Protocol Layer (Parsing & Encoding)

**Purpose**: Handle NATS wire protocol (byte-perfect encoding, stateful parsing)

**User Scenario**: This infrastructure enables US1-US5 (all scenarios require protocol encoding/decoding)

- [ ] T016 [P] Create NatsParser class stub in lib/src/protocol/parser.dart ( incoming stream, _buffer field, messages output stream)
- [ ] T017 [P] Create parser unit test file test/unit/parser_test.dart (import message.dart, nats protocol test data)
- [ ] T018 Implement parser MSG command parsing in lib/src/protocol/parser.dart (extract subject, sid, replyTo, bytes, payload)
- [ ] T019 Add parser MSG test case in test/unit/parser_test.dart (test parse "MSG subject 1 5\r\nHello\r\n")
- [ ] T020 Implement parser partial frame handling in lib/src/protocol/parser.dart (buffer incomplete messages across multiple packets)
- [ ] T021 Add parser partial frame test in test/unit/parser_test.dart (test MSG split across 2 chunks)
- [ ] T022 Implement parser HMSG command parsing in lib/src/protocol/parser.dart (extract headers with NATS/1.0 prefix, headerBytes, totalBytes, payload)
- [ ] T023 Add parser HMSG test case in test/unit/parser_test.dart (test parse HMSG with headers and payload)
- [ ] T024 Implement parser INFO command parsing in lib/src/protocol/parser.dart (extract JSON server capabilities: headers, max_payload, auth_required, nonce)
- [ ] T025 Add parser INFO test in test/unit/parser_test.dart (test parse "INFO {\"headers\":true}\r\n")
- [ ] T026 Implement parser PING/PONG handling in lib/src/protocol/parser.dart (emit PING and PONG events)
- [ ] T027 Add parser PING/PONG test in test/unit/parser_test.dart (test parse "PING\r\n" and "PONG\r\n")
- [ ] T028 Implement parser +OK and -ERR handling in lib/src/protocol/parser.dart (emit +OK acknowledgement and -ERR error)
- [ ] T029 Add parser +OK/-ERR test in test/unit/parser_test.dart (test parse "+OK\r\n" and "-ERR 'error'\r\n")
- [ ] T030 Implement parser status code extraction in lib/src/protocol/parser.dart (extract codes 100, 404, 408, 409 from HMSG first line)
- [ ] T031 Add parser status code test in test/unit/parser_test.dart (test parse HMSG with status codes)
- [ ] T032 Implement parser multi-value header extraction in lib/src/protocol/parser.dart (return Map<String, List<String>> for headers)
- [ ] T033 Add parser multi-value header test in test/unit/parser_test.dart (test parse HMSG with duplicate header keys)
- [ ] T034 Implement parser state machine in lib/src/protocol/parser.dart (stateful buffering between addBytes() calls)
- [ ] T035 [P] Create unit test for parser state machine in test/unit/parser_test.dart (test that addBytes() called twice produces same message as single call)
- [ ] T036 [P] Create NatsEncoder class stub in lib/src/protocol/encoder.dart (static methods for CONNECT, PUB, HPUB, SUB, UNSUB, PING/PONG)
- [ ] T037 [P] Create encoder unit test file test/unit/encoder_test.dart (test byte-perfect command generation)
- [ ] T038 Implement encodeConnect() method in lib/src/protocol/encoder.dart (generate CONNECT JSON with headers: true, verbose: false, auth fields)
- [ ] T039 Add encodeConnect test in test/unit/encoder_test.dart (test CONNECT command with token auth)
- [ ] T040 Implement encodePub() method in lib/src/protocol/encoder.dart (generate PUB <subject> [replyTo] <bytes>\r\n<payload>\r\n)
- [ ] T041 Add encodePub test in test/unit/encoder_test.dart (test PUB command with 0-byte payload)
- [ ] T042 Implement encodeHpub() method in lib/src/protocol/encoder.dart (generate HPUB with exact byte counting: headerBytes + payloadBytes)
- [ ] T043 Add encodeHpub byte counting test in test/unit/encoder_test.dart (critical: test that headerBytes = 10 + headers + 4, validate against reference)
- [ ] T044 Implement encodeSub() method in lib/src/protocol/encoder.dart (generate SUB <subject> [queueGroup] <sid>\r\n)
- [ ] T045 Add encodeSub test in test/unit/encoder_test.dart (test SUB with queueGroup and without)
- [ ] T046 Implement encodeUnsub() method in lib/src/protocol/encoder.dart (generate UNSUB <sid> [maxMsgs]\r\n)
- [ ] T047 Add encodeUnsub test in test/unit/encoder_test.dart (test UNSUB with maxMsgs auto-unsub)
- [ ] T048 Implement encodePing() and encodePong() in lib/src/protocol/encoder.dart (generate PING\r\n and PONG\r\n)
- [ ] T049 Add encoder PING/PONG test in test/unit/encoder_test.dart (test ping() emits "PING\r\n", pong() emits "PONG\r\n")

**Checkpoint**: Protocol layer complete - parser and encoder ready for connection integration

---

## Phase 4: Transport Abstraction

**Purpose**: Platform-specific network transport (native TCP vs web WebSocket)

**User Scenario**: US1 (Native TCP) and US2 (Web WebSocket) require transport implementations

- [ ] T050 [P] Create Transport interface in lib/src/transport/transport.dart (incoming stream, write, close, isConnected, errors stream)
- [ ] T051 [P] Create transport mock for unit tests in lib/src/transport/mock_transport.dart (implements Transport, pumpData/pumpError helpers)
- [ ] T052 [P] Create TcpTransport class stub in lib/src/transport/tcp_transport.dart (constructor with host, port, connectTimeout)
- [ ] T053 Implement TcpTransport.connect() in lib/src/transport/tcp_transport.dart (use dart:io Socket.connect())
- [ ] T054 Implement TcpTransport.incoming stream in lib/src/transport/tcp_transport.dart (read bytes from socket, emit as Uint8List)
- [ ] T055 Implement TcpTransport.write() in lib/src/transport/tcp_transport.dart (write bytes to socket via socket.add())
- [ ] T056 Implement TcpTransport.close() in lib/src/transport/tcp_transport.dart (close socket, idempotent)
- [ ] T057 Implement TcpTransport.errors stream in lib/src/transport/tcp_transport.dart (emit SocketException and TimeoutException)
- [ ] T058 Create TcpTransport integration test stub in test/integration/tcp_transport_test.dart (requires Docker NATS)
- [ ] T059 [P] Create WebSocketTransport class stub in lib/src/transport/websocket_transport.dart (constructor with URI, connectTimeout)
- [ ] T060 Implement WebSocketTransport.connect() in lib/src/transport/websocket_transport.dart (use web_socket_channel WebSocketChannel.connect())
- [ ] T061 Implement WebSocketTransport.incoming stream in lib/src/transport/websocket_transport.dart (decode WebSocket string to Uint8List)
- [ ] T062 Implement WebSocketTransport.write() in lib/src/transport/websocket_transport.dart (encode Uint8List to string, add to channel.sink)
- [ ] T063 Implement WebSocketTransport.close() in lib/src/transport/websocket_transport.dart (close channel.sink, idempotent)
- [ ] T064 Implement WebSocketTransport.errors stream in lib/src/transport/websocket_transport.dart (emit WebSocketChannelException)
- [ ] T065 Create WebSocketTransport integration test stub in test/integration/websocket_transport_test.dart (requires Docker NATS with WebSocket)
- [ ] T066 Create transport_factory.dart in lib/src/transport/transport_factory.dart (export Transport interface based on platform)
- [ ] T067 Implement compile-time conditional imports in lib/src/transport/transport_factory.dart (if dart.library.io import TcpTransport, if dart.library.html import WebSocketTransport)
- [ ] T068 Implement createTransport() method in lib/src/transport/transport_factory.dart (auto-convert nats:// to TCP or WebSocket based on platform)
- [ ] T069 Add transport factory unit test in test/unit/transport_factory_test.dart (test URI scheme mapping for native and web)
- [ ] T070 Update lib/src/transport/transport_factory_io.dart (native-only export, implements createTransport() with TCP logic)
- [ ] T071 Update lib/src/transport/transport_factory_web.dart (web-only export, implements createTransport() with WebSocket logic)
- [ ] T072 Update lib/src/transport/transport_factory_stub.dart (stub export for pub.dev compatibility)

**Checkpoint**: Transport layer complete - platform abstraction ready for connection management

---

## Phase 5: Connection Layer - Basic

**Purpose**: NatsConnection class with core pub/sub functionality

**User Scenario**: US1 (Native app connects and publishes/subscribes) and US2 (Web app connects)

- [ ] T073 [P] Create NatsConnection class stub in lib/src/client/connection.dart (constructor with Transport, parser, encoder, nuid injection)
- [ ] T074 [P] Create connection integration test file test/integration/connection_test.dart (setup Docker NATS fixture)
- [ ] T075 Implement NatsConnection.connect() factory method in lib/src/client/connection.dart (call createTransport(), establish connection)
- [ ] T076 Add connect() integration test in test/integration/connection_test.dart (test connection succeeds with nats://localhost:4222)
- [ ] T077 Implement NatsConnection INFO/CONNECT handshake in lib/src/client/connection.dart (receive INFO from parser, send CONNECT via encoder, wait for +OK)
- [ ] T078 Add handshake integration test in test/integration/connection_test.dart (verify handshake completes, status stream emits connected)
- [ ] T079 Implement NatsConnection.publish() method in lib/src/client/connection.dart (validate subject/payload, call encoder.encodePub() or encodeHpub(), write to transport)
- [ ] T080 Add publish() integration test in test/integration/connection_test.dart (test publish succeeds, subscriber receives message)
- [ ] T081 Implement NatsConnection.subscribe() method in lib/src/client/connection.dart (generate SID via nuid, call encoder.encodeSub(), register subscription in _subscriptions map, create Subscription object)
- [ ] T082 Add subscribe() integration test in test/integration/connection_test.dart (test subscription receives published messages)
- [ ] T083 Implement Subscription class in lib/src/client/subscription.dart (StreamController<NatsMessage> for messages, expose get messages stream)
- [ ] T084 Add subscribe() message routing in lib/src/client/connection.dart (parser messages → route to subscription by SID match)
- [ ] T085 Implement NatsConnection.unlink() method in lib/src/client/connection.dart (call encoder.encodeUnsub(), remove subscription from _subscriptions, close subscription stream)
- [ ] T086 Add unsubscribe() integration test in test/integration/connection_test.dart (test unsubscribe stops message delivery)
- [ ] T087 [P] Implement NatsConnection.status stream in lib/src/client/connection.dart (StreamController emitting ConnectionStatus enum values)
- [ ] T088 Add status stream integration test in test/integration/connection_test.dart (test status emits connecting→connected sequence)
- [ ] T089 [P] Implement NatsConnection.isConnected getter in lib/src/client/connection.dart (return true if status latest is connected)
- [ ] T090 [P] Add isConnected unit test in test/unit/connection_test.dart (test getter returns correct boolean)
- [ ] T091 Implement Nuid uniqueness test in test/unit/nuid_test.dart (stress test: generate 10,000 IDs, verify none collide)

**Checkpoint**: Basic connection layer working - can connect, publish, subscribe, unsubscribe

---

## Phase 6: Connection Layer - Request/Reply

**Purpose**: Request/reply pattern for RPC-style synchronous communication

**User Scenario**: US3 (Request/Reply for RPC-Style Communication)

- [ ] T092 [P] Create request/reply integration test file test/integration/request_reply_test.dart (setup service subscriber)
- [ ] T093 Implement NatsConnection.request() method in lib/src/client/connection.dart (generate inbox via nuid.inbox(), subscribe to inbox, publish with replyTo, wait for first message, auto-unsubscribe)
- [ ] T094 Add request() success integration test in test/integration/request_reply_test.dart (test request receives reply from service)
- [ ] T095 Implement request() timeout handling in lib/src/client/connection.dart (use Stream.timeout() with default 10s, throw TimeoutException)
- [ ] T096 Add request() timeout integration test in test/integration/request_reply_test.dart (test timeout throws exception after 1 second)
- [ ] T097 Implement request() subscription cleanup in lib/src/client/connection.dart (auto-unsubscribe inbox after reply received or timeout, prevent leaks)
- [ ] T098 Add request() cleanup unit test in test/unit/connection_test.dart (verify no subscription leak after request completes or times out)
- [ ] T099 Implement request() race condition prevention in lib/src/client/connection.dart (subscribe BEFORE publishing to ensure reply-to subject exists)

**Checkpoint**: Request/reply working - synchronous RPC calls with timeout and auto-cleanup

---

## Phase 7: Connection Layer - Message Routing & Features

**Purpose**: Subscription routing, queue groups, wildcards, and advanced message handling

**User Scenario**: US1, US2, US3 (all require robust subscription and message routing)

- [ ] T100 [P] Implement wildcard subscription matching in lib/src/client/connection.dart (match FOO.* to single token, FOO.> to multi+)
- [ ] T101 Add wildcard matching unit test in test/unit/connection_test.dart (test FOO.* matches FOO.bar but not FOO.bar.baz, test FOO.> matches both)
- [ ] T102 Implement queue group handling in Subscription subscribe in lib/src/client/connection.dart (pass queueGroup to encoder.encodeSub())
- [ ] T103 Add queue group integration test in test/integration/connection_test.dart (test two subscribers with same queueGroup share load)
- [ ] T104 Implement Subscription auto-unsub maxMsgs in lib/src/client/subscription.dart (track _messageCount, close stream after _maxMessages reached)
- [ ] T105 Add auto-unsub integration test in test/integration/connection_test.dart (test unsubscribe after N messages)
- [ ] T106 Implement NatsMessage header parsing in lib/src/protocol/message.dart (populate headers field from parser-provided Map<String, List<String>>)
- [ ] T107 Add header access unit test in test/unit/message_test.dart (test header() and headerAll() methods)
- [ ] T108 Implement NatsMessage status code getters in lib/src/protocol/message.dart (isFlowCtrl, isHeartbeat, isNoMsg, isTimeout implementations)
- [ ] T109 Add status code getter unit test in test/unit/message_test.dart (test getters return correct boolean for each status code)
- [ ] T110 [P] Implement parser NatsMessage instantiation in lib/src/protocol/parser.dart (create NatsMessage objects from parsed MSG/HMSG commands)
- [ ] T111 [P] Add parser NatsMessage unit test in test/unit/parser_test.dart (verify parser emits NatsMessage for all command types)

**Checkpoint**: Message routing complete - wildcards, queue groups, headers, status codes working

---

## Phase 8: Connection Layer - Reconnection & Resilience

**Purpose**: Automatic reconnection with subscription replay

**User Scenario**: US4 (Connection Resilience During Network Interruption)

- [ ] T112 [P] Create reconnection integration test file test/integration/reconnection_test.dart (simulate server kill/restart)
- [ ] T113 Implement NatsConnection reconnection detection in lib/src/client/connection.dart (listen to transport.errors stream, on error emit status=reconnecting)
- [ ] T114 Implement reconnection exponential backoff in lib/src/client/connection.dart (wait reconnectDelay seconds, attempt reconnect up to maxReconnectAttempts)
- [ ] T115 Add reconnection backoff integration test in test/integration/reconnection_test.dart (test reconnection delays by 2s, 4s, 8s then gives up after 3 attempts if maxReconnectAttempts=3)
- [ ] T116 Implement subscription replay on reconnect in lib/src/client/connection.dart (re-send SUB commands for all active subscriptions from _subscriptions map)
- [ ] T117 Add subscription replay integration test in test/integration/reconnection_test.dart (test subscriptions preserved after kill server → restart)
- [ ] T118 Implement publish buffering during reconnect in lib/src/client/connection.dart (queue publish calls in buffer while reconnecting)
- [ ] T119 Implement buffered publish flush after reconnect in lib/src/client/connection.dart (after CONNECT succeeds, send all queued publishes)
- [ ] T120 Add buffered publish integration test in test/integration/reconnection_test.dart (test publishes during reconnect sent after recovery)
- [ ] T121 Implement maxReconnectAttempts enforcement in lib/src/client/connection.dart (after max attempts, emit status=closed, stop reconnection attempts)
- [ ] T122 Add reconnection max attempts test in test/integration/reconnection_test.dart (test reconnection stops after max attempts, status=closed)
- [ ] T123 Implement reconnection status events in lib/src/client/connection.dart (emit ConnectionStatus.reconnecting on error, ConnectionStatus.connected on successful reconnect, ConnectionStatus.closed on max attempts)
- [ ] T124 Add status event integration test in test/integration/reconnection_test.dart (test status events: connected→reconnecting→connected→closed)

**Checkpoint**: Reconnection complete - automatic recovery with subscription replay and buffered publishes

---

## Phase 9: Connection Layer - PING/PONG Keepalive

**Purpose**: Server and client keepalive to detect dead connections

**User Scenario**: US4 (resilience includes PING/PONG detection)

- [ ] T125 [P] Implement server PING response in lib/src/client/connection.dart (listen to parser for PING events, auto-respond with PONG via encoder.encodePong())
- [ ] T126 Add server PING response unit test in test/unit/connection_test.dart (test that server PING triggers PONG write)
- [ ] T127 Implement client PING keepalive timer in lib/src/client/connection.dart (Timer that sends PING every pingInterval from ConnectOptions)
- [ ] T128 Implement maxPingOut detection in lib/src/client/connection.dart (track sent PINGS, trigger reconnection if maxPingOut missed without PONG)
- [ ] T129 Add client PING keepalive integration test in test/integration/reconnection_test.dart (test client PING sent every 2min, reconnection triggered after 2 missed PONGs)

**Checkpoint**: Keepalive complete - server and client PING/PONG working

---

## Phase 10: Authentication

**Purpose**: Support token, user/pass, NKey, and JWT authentication modes

**User Scenario**: US5 (Authenticated Connection)

- [ ] T130 [P] Create authentication integration test file test/integration/auth_test.dart (setup NATS server with --auth, --user, --pass, --token)
- [ ] T131 ConnectOptions validation for auth methods in lib/src/client/options.dart (enforce exactly zero or one auth method, throw ArgumentError if multiple)
- [ ] T132 Add auth validation unit test in test/unit/options_test.dart (test that token + user together throws error)
- [ ] T133 Implement token authentication in NatsConnection.connect() in lib/src/client/connection.dart (include authToken in CONNECT JSON)
- [ ] T134 Add token auth integration test in test/integration/auth_test.dart (test connect with authToken succeeds)
- [ ] T135 Implement user/pass authentication in NatsConnection.connect() in lib/src/client/connection.dart (include user and pass in CONNECT JSON)
- [ ] T136 Add user/pass auth integration test in test/integration/auth_test.dart (test connect with user:alice, pass:secret succeeds)
- [ ] T137 Implement NKey authentication stub in lib/src/client/connection.dart (placeholder: read nkeyPath, sign nonce - defer full crypto if complex)
- [ ] T138 Add NKey auth integration test stub in test/integration/auth_test.dart (skip test for now if crypto library required)
- [ ] T139 Implement JWT authentication stub in lib/src/client/connection.dart (placeholder: include jwt + sig in CONNECT - defer full crypto if complex)
- [ ] T140 Add JWT auth integration test stub in test/integration/auth_test.dart (skip test for now if crypto library required)
- [ ] T141 Implement INFO.auth_required validation in NatsConnection handshake in lib/src/client/connection.dart (check INFO for auth_required, enforce credentials provided)
- [ ] T142 Add INFO auth_required test in test/integration/auth_test.dart (test connect fails without credentials when auth_required=true in INFO)
- [ ] T143 Implement INFO nonce parsing for NKey in NatsConnection handshake in lib/src/client/connection.dart (extract nonce from INFO for NKey signature)
- [ ] T144 Add INFO nonce parsing unit test in test/unit/connection_test.dart (test nonce extracted from INFO JSON successfully)

**Checkpoint**: Authentication working - token, user/pass implemented, NKey/JWT stubbed if crypto complex

---

## Phase 11: Connection Layer - Lifecycle & Configuration

**Purpose**: Drain, close, and remaining ConnectOptions configuration

**User Scenario**: US1, US2, US4 (proper cleanup and connection management)

- [ ] T145 [P] Implement NatsConnection.close() method in lib/src/client/connection.dart (close transport, mark status=closed, close all subscription streams, clear _subscriptions)
- [ ] T146 Add close() integration test in test/integration/connection_test.dart (test connection close stops message delivery, status=closed)
- [ ] T147 [P] Implement NatsConnection.drain() method in lib/src/client/connection.dart (unsubscribe all with auto-max, flush buffered writes, then close)
- [ ] T148 Add drain() integration test in test/integration/connection_test.dart (test drain processes in-flight messages then closes connection)
- [ ] T149 [P] Apply ConnectOptions fields to CONNECT in NatsConnection.connect() in lib/src/client/connection.dart (name, noEcho, inboxPrefix, maxReconnectAttempts, reconnectDelay, pingInterval, maxPingOut)
- [ ] T150 Add ConnectOptions unit test in test/unit/options_test.dart (test all fields serialize to CONNECT JSON correctly)
- [ ] T151 Implement max_payload validation in NatsConnection.publish() in lib/src/client/connection.dart (check INFO max_payload, throw ArgumentError if payload size exceeds)
- [ ] T152 Add max_payload validation unit test in test/unit/connection_test.dart (test publish throws when payload exceeds server max_payload)

**Checkpoint**: Connection lifecycle complete - drain, close, configuration all working

---

## Phase 12: Polish & Cross-Cutting Improvements

**Purpose**: Documentation, error messages, performance, and final polish

- [ ] T153 [P] Update quickstart.md code examples after implementation (verify all examples actually work)
- [ ] T154 [P] Update contracts/ documents to match implemented API signatures
- [ ] T155 [P] Update data-model.md to reflect any state machine changes during implementation
- [ ] T156 [P] Add doc comments to all public APIs in lib/src/ (NatsConnection, Subscription, ConnectOptions, NatsMessage)
- [ ] T157 [P] Add inline code comments in lib/src/protocol/parser.dart explaining state machine logic and partial frame handling
- [ ] T158 [P] Add inline code comments in lib/src/protocol/encoder.dart explaining byte counting for HPUB
- [ ] T159 Review and improve error messages in parser.dart (make parse errors actionable)
- [ ] T160 Review and improve error messages in connection.dart (make connection and auth errors clear)
- [ ] T161 Run performance test for throughput in test/integration/performance_test.dart (publish 10,000 1KB messages, measure msgs/sec, target ≥50,000 TCP, ≥10,000 WebSocket)
- [ ] T162 Run performance test for latency in test/integration/performance_test.dart (request/reply 1,000 times, measure median/p99 latency, target <5ms p50 TCP)
- [ ] T163 Run chaos engineering test in test/integration/chaos_test.dart (kill server 100 times, verify 99% successful reconnections)
- [ ] T164 Run all unit tests and verify coverage ≥80% for protocol layer (parse, encode, message)
- [ ] T165 Run all integration tests and verify coverage ≥70% for connection layer
- [ ] T166 Run dart format on lib/ and test/ directories
- [ ] T167 Run dart analyze on lib/ and test/ directories (fix all linting errors)
- [ ] T168 Verify Pure Dart compliance (no dart:io or dart:html imports in lib/src/protocol/ and lib/src/client/)
- [ ] T169 Verify conditional imports only in lib/src/transport/transport_factory.dart
- [ ] T170 Create Flutter native example in example/flutter_native_example.dart (connect, publish, subscribe)
- [ ] T171 Create Flutter web example in example/flutter_web_example.dart (same code as native, works on web)
- [ ] T172 Verify quickstart.md Flutter example compiles and runs
- [ ] T173 Verify quickstart.md Docker quick-start works (test with real Docker NATS)
- [ ] T174 Verify branch 001-nats-foundation has clean git status (no uncommitted changes)
- [ ] T175 Commit design documents with message: "chore: commit Phase 1 design artifacts (data-model, contracts, quickstart)"
- [ ] T176 Commit implementation with message: "feat: implement Phase 1 foundation (parser, encoder, transport, connection, auth, reconnection)"

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: No dependencies - can start immediately after Setup
- **Protocol Layer (Phase 3)**: Depends on Foundational (data models) - requires T007-T015
- **Transport Abstraction (Phase 4)**: Depends on no earlier phases (parallel with Phase 3) - can start after Setup
- **Connection Basic (Phase 5)**: Depends on Protocol Layer (T016-T049) and Transport (T050-T072)
- **Request/Reply (Phase 6)**: Depends on Connection Basic (T073-T091)
- **Message Routing (Phase 7)**: Depends on Connection Basic (T073-T091) - parallel with Phase 6
- **Reconnection (Phase 8)**: Depends on Message Routing (T100-T111)
- **Keepalive (Phase 9)**: Depends on Connection Basic (T073-T091) - depends on Reconnection (T112-T124) for status management
- **Authentication (Phase 10)**: Depends on Connection Basic (T073-T091) - parallel with Phases 6-9
- **Lifecycle (Phase 11)**: Depends on all previous phases (T073-T144)
- **Polish (Phase 12)**: Depends on all implementation complete (T001-T152)

### User Scenario Dependencies

- **US1 (Native App Connect)**: Requires Protocol (Phase 3), Transport (Phase 4), Connection Basic (Phase 5)
- **US2 (Web App Connect)**: Same as US1 (platform abstraction ensures code unchanged)
- **US3 (Request/Reply)**: Requires Connection Basic (Phase 5) + Request/Reply implementation (Phase 6)
- **US4 (Reconnection Resilience)**: Requires Message Routing (Phase 7) + Reconnection (Phase 8) + Keepalive (Phase 9)
- **US5 (Authentication)**: Requires Lifecycle (Phase 11) + Authentication (Phase 10)

### Critical Path

The critical path for MVP (User Stories 1-2: basic pub/sub):

```
Phase 1 (T001-T006)
  ↓
Phase 2 (T007-T015)
  ↓
Phase 3 (T016-T049) ──┐
Parallel with                ↓
Phase 4 (T050-T072)    Phase 5 (T073-T091) ← MVP reachable here
```

**MVP (US1 + US2)**: First 91 tasks (T001-T091) enable connect, publish, subscribe on native and web

---

## Parallel Opportunities

### Within Each Phase

**Phase 1 (Setup)**: T004, T005, T006 can run in parallel (different directories)
**Phase 2 (Foundational)**: T007, T008, T009 can run in parallel (different methods in same file)
**Phase 3 (Protocol)**: T017, T035, T037 can run in parallel (test file creation)
**Phase 4 (Transport)**: T051, T059, T069 can run in parallel (mock, WebSocket, factory tests)
**Phase 5 (Connection)**: T074, T087, T089, T091 can run in parallel (tests and unit tests)
**Phase 6 (Request/Reply)**: T092 can run in parallel with T093 (test while implementing)
**Phase 7 (Routing)**: T100, T110 can run in parallel (wildcard matching and NatsMessage creation)
**Phase 8 (Reconnection)**: T112 can run in parallel with T113 (test setup while implementing)
**Phase 9 (Keepalive)**: T125, T135, T145, T147, T149, T151 can run in parallel (unit tests and implementation)
**Phase 10 (Auth)**: T130 can run in parallel with T131 (test setup while implementing)
**Phase 11 (Lifecycle)**: T145, T147, T149, T151 can run in parallel (independent methods)
**Phase 12 (Polish)**: 153-155 (docs), 161-163 (tests), 166-167 (format/analyze) all parallelizable

### Cross-Phase Parallelism

**Phase 3 + Phase 4**: Protocol parsing/encoding and transport implementation can run simultaneously (T016-T111 parallel with T050-T072) if team capacity allows
**Phase 6 + Phase 7**: Request/reply and message routing can run simultaneously (T092-T099 parallel with T100-T111)
**Phase 10 + Phase 11**: Authentication and lifecycle can run simultaneously (T130-T144 parallel with T145-T152)

---

## Parallel Example: Connection Basic (Phase 5)

```bash
# Terminal 1: Implement publish() method
vim lib/src/client/connection.dart  # Work on T079

# Terminal 2: Create integration test
vim test/integration/connection_test.dart  # Work on T074-076

# Terminal 3: Create unit tests
vim test/unit/connection_test.dart  # Work on T090

# Terminal 4: Implement status stream (can merge later)
vim lib/src/client/connection.dart  # Work on T087
```

---

## Complexity Tracking

### Low Complexity Tasks (1-2 hours each)
- T007-T009 (NatsMessage fields)
- T010-T012 (Nuid implementation)
- T040-T041, T044-T049 (encoder simple methods)
- T083 (Subscription stub)
- T100-T101 (wildcard matching)
- T145, T147 (lifecycle)

### Medium Complexity Tasks (2-4 hours each)
- T018-T034 (parser state machine - partial frames, HMSG)
- T050-T072 (transport implementations)
- T073-T091 (connection basic pub/sub)
- T093-T099 (request/reply)
- T116-T120 (subscription replay, buffered publishes)

### High Complexity Tasks (4-8+ hours each)
- T020 (parser partial frame state machine - highest risk)
- T042 (HPUB byte counting - critical, test against reference)
- T113-T124 (reconnection state machine - high risk, many edge cases)
- T137-T140 (NKey/JWT crypto - may require external library)
- T163 (chaos engineering test - complex, needs Docker and server kill simulation)

---

## Risk Tasks (Require Extra Care)

- **T020 (Parser Partial Frames)**: State machine must handle arbitrary chunk boundaries. Test with every possible split point in MSG/HMSG.
- **T042 (HPUB Byte Counting)**: Off-by-one errors cause parser corruption. Validate against nats.deno reference.
- **T113-T124 (Reconnection)**: Complex state machine (connecting→reconnecting→connected). Requires chaos engineering tests (kill server 100+ times).
- **T137-T140 (NKey/JWT)**: Crypto implementation may require external library (e.g., `pointycastle`). Evaluate complexity early. May need to defer NKey/JWT if too complex (accept as Phase 3 risk).

---

## Independent Test Criteria per Phase

**Phase 1**: Directory structure exists
**Phase 2**: All data model unit tests pass (nuid uniqueness, message getters)
**Phase 3**: Parser and encoder unit tests pass, byte counting validated against reference
**Phase 4**: Transport integration tests pass (TCP connects to Docker NATS, WebSocket connects)
**Phase 5**: Connect, publish, subscribe integration test passes (end-to-end pub/sub)
**Phase 6**: Request/reply integration test passes (request receives reply, timeout works)
**Phase 7**: Wildcard and queue group integration tests pass
**Phase 8**: Reconnection integration test passes (subscriptions restored after server kill)
**Phase 9**: PING/PONG keepalive integration test passes
**Phase 10**: Token and user/pass integration tests pass
**Phase 11**: Drain and close integration tests pass
**Phase 12**: All performance tests pass, coverage thresholds met

---

## MVP Scope

**Recommended MVP**: T001-T091 (Phases 1-5)

**What MVP Delivers**:
- ✅ Connect to NATS server (native TCP and web WebSocket)
- ✅ Publish and subscribe to subjects
- ✅ Basic message routing
- ✅ Connection status monitoring
- ✅ Basic connection lifecycle (close)

**What MVP Does NOT Include**:
- ❌ Request/reply (Phase 6)
- ❌ Wildcards and queue groups (Phase 7)
- ❌ Automatic reconnection (Phase 8)
- ❌ PING/PONG keepalive (Phase 9)
- ❌ Authentication (Phase 10)
- ❌ Graceful drain (Phase 11)

**User Stories Supported by MVP**:
- ✅ US1 (Native App Connect): Full support
- ✅ US2 (Web App Connect): Full support
- ❌ US3 (Request/Reply): Not yet (Phase 6)
- ❌ US4 (Reconnection): Not yet (Phase 8)
- ❌ US5 (Authentication): Not yet (Phase 10)

**MVP to Full Completion**: Add Phases 6-11 for all 5 user scenarios

---

## Implementation Strategy

### Incremental Delivery

1. **Week 1**: Complete Phases 1-3 (Setup, Foundational, Protocol Layer) - Parser and encoder ready
2. **Week 2**: Complete Phase 4 (Transport) - Platform abstraction ready
3. **Week 2-3**: Complete Phase 5 (Connection Basic) - MVP achieved (basic pub/sub working)
4. **Week 3**: Complete Phases 6-7 (Request/Reply, Routing) - US1-US3 full support
5. **Week 3-4**: Complete Phases 8-9 (Reconnection, Keepalive) - US4 full support
6. **Week 4**: Complete Phases 10-11 (Authentication, Lifecycle) - US5 + production features
7. **Week 4-5**: Complete Phase 12 (Polish) - Performance tests, docs, formatting

### Risk Mitigation

- **Start with high-risk parser (T020, T042)**: Get state machine right before adding complexity
- **Parallelize transport and connection**: If team size ≥2, work on T050-T072 and T073-T091 simultaneously
- **Defer NKey/JWT if blocking**: Create stub implementations (T137, T139) and skip tests if crypto library evaluation takes too long. Revisit in Phase 3.

---

## Task Format Validation

Format Checklist:
- ✅ All tasks start with `- [ ]` (checkbox)
- ✅ All tasks have sequential IDs (T001-T176)
- ✅ Parallel tasks marked with `[P]`
- ✅ User scenarios labeled as `[US1]` through `[US5]`
- ✅ All descriptions include exact file paths
- ✅ Tasks organized by phase (12 total phases)
- ✅ Dependencies documented
- ✅ Parallel execution opportunities identified
- ✅ MVP scope clearly defined

**Total Task Count**: 176 tasks
**Tasks With [P] Marker**: ~45 tasks (parallelizable)
**Estimated Effort**: 4-5 weeks (assuming 1 developer, 35-40 hours/week)

---

**Status**: Ready for implementation
**Next**: Begin T001 in Phase 1 (verify directory structure), or start parallel tasks in Phase 2 (data models)
