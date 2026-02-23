# Phase 2: JetStream

**Status**: Blocked on Phase 1  
**Duration Estimate**: 2-3 weeks  
**Dependencies**: Phase 1 (Core Client with HPUB/HMSG)  
**Milestone**: Full JetStream on all Flutter platforms

---

## Overview

Phase 2 implements JetStream — NATS persistent streaming built on top of core pub/sub. JetStream has **no separate wire protocol**; it's implemented as JSON request/reply on `$JS.API.*` subjects using the HPUB/HMSG commands from Phase 1.

**Key Insight**: JetStream is a protocol layer, not a transport layer. All JetStream logic is platform-agnostic and works identically on TCP and WebSocket.

---

## Scope

### 2.1 JetStreamContext

**Goal**: Entry point for all JetStream operations.

**Deliverables**:
- `JetStreamContext` class with:
  - `StreamManager get streams`
  - `ConsumerManager get consumers`
  - `Future<PubAck> publish(String subject, Uint8List data, {String? msgId, Map<String, String>? headers})`
  - `Future<PullConsumer> consumer(String stream, String name)`
  - `String _api(String path)` — internal helper for `$JS.API.*` subjects
- Factory method on `NatsConnection`:
  - `JetStreamContext jetStream({String? domain, Duration timeout = const Duration(seconds: 5)})`
- Domain support for multi-tenant JetStream (`$JS.<domain>.API.*`)

**Critical Requirements**:
- Must validate `jetstream: true` in server INFO before allowing operations
- Must use HPUB for all publishes (including API requests)
- Must set request timeout on all API calls

**Reference**: Architecture doc § 5.1 (JetStreamContext)

---

### 2.2 StreamManager — CRUD for Streams

**Goal**: Create, update, delete, and query JetStream streams.

**Deliverables**:
- `StreamManager` class with:
  - `Future<StreamInfo> createStream(StreamConfig config)`
  - `Future<StreamInfo> updateStream(String name, StreamConfig config)`
  - `Future<StreamInfo> getStreamInfo(String name)`
  - `Future<List<String>> listStreamNames()`
  - `Future<List<StreamInfo>> listStreams()`
  - `Future<bool> deleteStream(String name)`
  - `Future<void> purgeStream(String name)`
- API subjects:
  - `$JS.API.STREAM.CREATE.<name>`
  - `$JS.API.STREAM.UPDATE.<name>`
  - `$JS.API.STREAM.INFO.<name>`
  - `$JS.API.STREAM.LIST` (paged)
  - `$JS.API.STREAM.NAMES` (paged)
  - `$JS.API.STREAM.DELETE.<name>`
  - `$JS.API.STREAM.PURGE.<name>`

**Critical Requirements**:
- Must handle paginated list responses (offset/limit pattern)
- Must parse `StreamInfo` JSON from server responses
- Must serialize `StreamConfig` to JSON for create/update

**Reference**: Architecture doc § 2.1 (Stream Management), § 2.2 (StreamConfig)

---

### 2.3 StreamConfig & StreamInfo Models

**Goal**: Strongly-typed models for stream configuration and state.

**Deliverables**:
- `StreamConfig` class with fields:
  - `String name`
  - `List<String> subjects`
  - `StreamStorage storage` (enum: file, memory)
  - `RetentionPolicy retention` (enum: limits, interest, workqueue)
  - `int maxConsumers` (-1 = unlimited)
  - `int maxMsgs` (-1 = unlimited)
  - `int maxBytes` (-1 = unlimited)
  - `Duration maxAge` (zero = never expire)
  - `int numReplicas`
  - `DiscardPolicy discard` (enum: old, new)
  - `Duration duplicateWindow`
- `StreamInfo` class with:
  - `StreamConfig config`
  - `StreamState state` (sequences, message counts, timestamps)
- JSON serialization/deserialization methods

**Reference**: Architecture doc § 2.2 (StreamConfig)

---

### 2.4 ConsumerManager — CRUD for Consumers

**Goal**: Create, delete, and query JetStream consumers.

**Deliverables**:
- `ConsumerManager` class with:
  - `Future<ConsumerInfo> createConsumer(String stream, ConsumerConfig config)`
  - `Future<ConsumerInfo> getConsumerInfo(String stream, String name)`
  - `Future<List<String>> listConsumerNames(String stream)`
  - `Future<List<ConsumerInfo>> listConsumers(String stream)`
  - `Future<bool> deleteConsumer(String stream, String name)`
- API subjects:
  - `$JS.API.CONSUMER.CREATE.<stream>` (ephemeral)
  - `$JS.API.CONSUMER.DURABLE.CREATE.<stream>.<name>` (durable)
  - `$JS.API.CONSUMER.INFO.<stream>.<name>`
  - `$JS.API.CONSUMER.LIST.<stream>` (paged)
  - `$JS.API.CONSUMER.NAMES.<stream>` (paged)
  - `$JS.API.CONSUMER.DELETE.<stream>.<name>`

**Critical Requirements**:
- Must support both ephemeral and durable consumers
- Must parse `ConsumerInfo` JSON from server responses
- Must serialize `ConsumerConfig` to JSON for create requests

**Reference**: Architecture doc § 2.1 (Consumer Management), § 2.3 (ConsumerConfig)

---

### 2.5 ConsumerConfig & ConsumerInfo Models

**Goal**: Strongly-typed models for consumer configuration and state.

**Deliverables**:
- `ConsumerConfig` class with fields:
  - `String? durableName` (null = ephemeral)
  - `DeliverPolicy deliverPolicy` (enum: all, new, last, byStartSequence)
  - `AckPolicy ackPolicy` (enum: explicit, all, none)
  - `Duration? ackWait`
  - `int? maxDeliver`
  - `String? filterSubject`
  - `ReplayPolicy replayPolicy` (enum: instant, original)
  - `int? maxAckPending`
  - `Duration? inactiveThreshold`
- `ConsumerInfo` class with:
  - `ConsumerConfig config`
  - `ConsumerState state` (sequences, pending, redelivered)
- JSON serialization/deserialization methods

**Reference**: Architecture doc § 2.3 (ConsumerConfig)

---

### 2.6 JetStream Publish with PubAck

**Goal**: Publish messages to JetStream streams with deduplication and confirmation.

**Deliverables**:
- `Future<PubAck> publish(String subject, Uint8List data, {String? msgId, Map<String, String>? headers})`
- Use HPUB with headers:
  - `Nats-Msg-Id: <msgId>` (if provided)
  - Optional: `Nats-Expected-Stream`, `Nats-Expected-Last-Msg-Id`, etc.
- Create unique inbox for reply-to
- Subscribe to inbox before publishing
- Wait for PubAck JSON response or timeout
- Parse PubAck:
  - `String stream` (which stream accepted the message)
  - `int seq` (stream sequence number)
  - `bool duplicate` (true if same Nats-Msg-Id seen within duplicate_window)

**Critical Requirements**:
- Must use HPUB (PUB without headers will NOT reach JetStream)
- Must subscribe to reply inbox BEFORE publishing to avoid race condition
- Must timeout properly (default 5s)
- Must support deduplication via `Nats-Msg-Id` header

**Reference**: Architecture doc § 2.6 (JetStream Publish Flow)

---

### 2.7 PubAck Model

**Goal**: Parse JetStream publish acknowledgment responses.

**Deliverables**:
- `PubAck` class with:
  - `String stream`
  - `int sequence`
  - `bool duplicate`
- JSON deserialization from server response

**Reference**: Architecture doc § 2.6 (PubAck JSON)

---

### 2.8 PullConsumer — Fetch & Consume

**Goal**: Pull messages from JetStream consumers in batches or continuous streams.

**Deliverables**:
- `PullConsumer` class with:
  - `Future<List<JsMsg>> fetch(int batch, {Duration expires, int? maxBytes, bool noWait = false})`
  - `Stream<JsMsg> consume({int batchSize = 100, Duration fetchExpiry = const Duration(seconds: 5)})`
- Fetch implementation:
  - Publish JSON request to `$JS.API.CONSUMER.MSG.NEXT.<stream>.<consumer>` with unique inbox as reply-to
  - Request payload: `{"batch": N, "expires": nanoseconds, "max_bytes": B, "no_wait": bool}`
  - Subscribe to inbox before publishing request
  - Collect messages until:
    - Batch size reached
    - Status 404 (No Messages)
    - Status 408 (Request Timeout)
    - Timeout duration exceeded
  - Handle flow control (status 100): publish empty message to reply-to immediately
  - Return list of `JsMsg` objects
- Consume implementation:
  - Continuous stream using `async*`
  - Issue `fetch()` in loop
  - Yield messages as they arrive
  - Short delay if empty batch to avoid tight loop

**Critical Requirements**:
- Must handle status codes 100, 404, 408, 409 correctly
- Must reply to flow control requests instantly
- Must convert `expires` to nanoseconds (not microseconds)
- Must unsubscribe from inbox after fetch completes

**Reference**: Architecture doc § 5.2 (PullConsumer)

---

### 2.9 JsMsg — Message Acknowledgment

**Goal**: Wrap JetStream messages with ack/nak/term/inProgress methods.

**Deliverables**:
- `JsMsg` class wrapping `NatsMessage` with:
  - `Uint8List get data` (alias for payload)
  - `String get subject`
  - `Map<String, List<String>>? get headers`
  - `JsMsgInfo get info` (parsed from ack subject in reply-to)
  - `Future<void> ack()` — publish `+ACK` or empty to reply-to
  - `Future<void> nak({Duration? delay})` — publish `-NAK` or `-NAK {"delay":ns}` to reply-to
  - `Future<void> term()` — publish `+TERM` to reply-to
  - `Future<void> inProgress()` — publish `+WPI` to reply-to

**Critical Requirements**:
- Must parse ack subject from `replyTo` field: `$JS.ACK.<stream>.<consumer>.<delivered>.<streamSeq>.<consumerSeq>.<ts>.<pending>`
- Ack methods must use the connection's `publish()` method
- Delay in nak must be converted to nanoseconds JSON

**Reference**: Architecture doc § 5.3 (JsMsg — Ack Model)

---

### 2.10 JsMsgInfo — Ack Subject Parser

**Goal**: Extract metadata from JetStream ack subject.

**Deliverables**:
- `JsMsgInfo` class with:
  - `String stream`
  - `String consumer`
  - `int numDelivered`
  - `int streamSequence`
  - `int consumerSequence`
  - `DateTime timestamp` (parsed from nanoseconds)
  - `int pending`
- Static method: `JsMsgInfo parse(String ackSubject)`
- Parse format: `$JS.ACK.<stream>.<consumer>.<delivered>.<streamSeq>.<consumerSeq>.<ts>.<pending>`

**Reference**: Architecture doc § 5.3 (JsMsgInfo)

---

### 2.11 OrderedConsumer — Sequence Gap Detection

**Goal**: Auto-recreate consumer on sequence gaps (required for KV watch in Phase 3).

**Deliverables**:
- `OrderedConsumer` class with:
  - `Stream<JsMsg> messages({int startSeq = 1})`
- Internal state:
  - `int _expectedSeq` — next expected stream sequence
- Logic:
  - Create ephemeral push consumer with:
    - `ackPolicy: none`
    - `flowControl: true`
    - `idleHeartbeat: 5s`
    - `deliverSubject: <fresh inbox>`
    - `optStartSeq: _expectedSeq`
  - Subscribe to deliver subject
  - For each message:
    - If heartbeat (status 100 Idle): continue (no action)
    - If flow control (status 100 FlowControl): reply with empty publish
    - If `msg.info.streamSequence != _expectedSeq`: **gap detected** → recreate consumer from `_expectedSeq`
    - Else: yield message, increment `_expectedSeq`

**Critical Requirements**:
- Must detect gaps (missing sequences) and recreate consumer
- Must handle flow control replies
- Must use ephemeral consumer (no durable name)
- Consumer config must include `flow_control: true` and `idle_heartbeat: 5000000000` (5s in nanoseconds)

**Reference**: Architecture doc § 5.4 (OrderedConsumer)

---

### 2.12 Flow Control Handling

**Goal**: Respond to server flow control requests to prevent stalls.

**Deliverables**:
- Detect HMSG with status `100 FlowControl Request`
- Immediately publish empty message to `msg.replyTo`
- Log flow control events (optional debug logging)

**Critical Requirements**:
- Must be instant (no delay)
- Must use connection's `publish()` with `Uint8List(0)` payload
- Must be implemented in both `PullConsumer.fetch()` and `OrderedConsumer.messages()`

**Reference**: Architecture doc § 1.5 (HMSG Status Codes), § 5.2, § 5.4

---

## Test Requirements

### Unit Tests
- JSON serialization/deserialization for all models (StreamConfig, ConsumerConfig, PubAck, etc.)
- JsMsgInfo parsing from ack subject string
- Ack subject format validation
- Status code detection in HMSG (100, 404, 408, 409)

### Integration Tests (Docker NATS with JetStream)
- Stream creation, update, info, list, delete
- Consumer creation (ephemeral & durable)
- JetStream publish → PubAck received
- Deduplication: publish same `Nats-Msg-Id` twice → `duplicate: true` in second PubAck
- Pull consumer fetch: batch size limits, status 404 handling
- Pull consumer consume: continuous stream over multiple batches
- Ack/nak/term: verify message redelivery behavior
- Flow control: simulate slow consumer, verify flow control replies sent
- OrderedConsumer: inject sequence gap, verify consumer recreation

### Test Coverage Target
- **80%** for JetStream protocol layer
- **75%** for consumer/producer logic
- **70%** for OrderedConsumer (complex state machine)

---

## Acceptance Criteria

1. ✅ All unit tests pass (JSON models, parsing)
2. ✅ Integration tests pass against Docker NATS with JetStream enabled
3. ✅ Stream CRUD operations work (create, update, info, list, delete)
4. ✅ Consumer CRUD operations work (create ephemeral & durable, info, delete)
5. ✅ Publish to JetStream receives PubAck with correct sequence
6. ✅ Deduplication works via `Nats-Msg-Id` header
7. ✅ Pull consumer fetch returns correct batch sizes
8. ✅ Pull consumer consume streams continuously across multiple fetches
9. ✅ Ack/nak/term methods work (verify redelivery in integration test)
10. ✅ Flow control replies are sent automatically
11. ✅ OrderedConsumer detects gaps and recreates consumer
12. ✅ No platform-specific code (all JetStream logic is Pure Dart)
13. ✅ `dart analyze` shows no warnings
14. ✅ `dart format` applied to all code

---

## Dependencies & Blockers

**External Dependencies**:
- Phase 1 complete (HPUB/HMSG, parser, connection)
- Docker NATS with JetStream enabled (`docker run nats:latest -js`)

**Known Risks**:
- OrderedConsumer sequence gap detection is complex — requires careful state management
- Flow control timing: must be instant to avoid server-side stalls
- Nanosecond time conversions (Dart Duration → nanoseconds for JSON)

---

## Out of Scope (Deferred to Phase 3)

- KeyValue store (built on OrderedConsumer in Phase 3)
- Push consumers (not required for Braven use case)
- Stream message get/delete by sequence
- Consumer idle threshold enforcement (server-side feature)

---

## Reference Implementation

Primary: `nats.deno` (TypeScript)
- `nats-base-client/jetstream.ts` — JetStreamContext
- `nats-base-client/jsm.ts` — StreamManager, ConsumerManager
- `nats-base-client/consumermessages.ts` — PullConsumer fetch/consume
- `nats-base-client/consumer.ts` — OrderedConsumer

Secondary: `nats.go` (canonical server-side reference)

---

## Next Steps After Phase 2

With Phase 2 complete, the package provides:
- ✅ Full JetStream support (streams, consumers, pub/ack)
- ✅ Pull consumer with batch fetch and continuous consume
- ✅ OrderedConsumer with sequence gap detection

**Phase 3** will add KeyValue store and production polish:
- KV bucket management
- KV put/get/delete/watch
- TLS support
- Production examples and documentation
- Publication to pub.dev
