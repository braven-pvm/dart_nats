# Phase 3: KeyValue & Production Ready

**Status**: Blocked on Phase 2  
**Duration Estimate**: 1-2 weeks  
**Dependencies**: Phase 2 (JetStream + OrderedConsumer)  
**Milestone**: Publishable open-source package on pub.dev

---

## Overview

Phase 3 implements the KeyValue store API on top of JetStream and polishes the package for production use. KeyValue is a high-level abstraction built on JetStream streams, using OrderedConsumer for real-time `watch()` functionality.

**Key Insight**: KeyValue has no separate protocol — it's a JetStream stream named `KV_<bucket>` with subjects `$KV.<bucket>.<key>`. Watch uses OrderedConsumer from Phase 2.

---

## Scope

### 3.1 KeyValue — Bucket Management

**Goal**: Create and manage KeyValue buckets (which are JetStream streams underneath).

**Deliverables**:
- `Future<KeyValue> keyValue(String bucket)` method on `JetStreamContext`
- Internal: check if stream `KV_<bucket>` exists via `$JS.API.STREAM.INFO.KV_<bucket>`
- If not exists: create stream with KV-specific config:
  - `name: "KV_<bucket>"`
  - `subjects: ["$KV.<bucket>.>"]`
  - `max_msgs_per_subject: 1` (only latest value per key)
  - `discard: "new"` (reject new if limit reached)
  - `allow_rollup_hdrs: true` (enable KV-Operation: DEL/PURGE)
- `KeyValue` class with bucket name and JetStream context

**Critical Requirements**:
- Must use stream naming convention `KV_<bucket_name>`
- Must configure stream for single-message-per-subject retention
- Must validate bucket name (alphanumeric + underscores only)

**Reference**: Architecture doc § 5.5 (KeyValue API)

---

### 3.2 KeyValue — Put & Get

**Goal**: Store and retrieve key-value pairs.

**Deliverables**:
- `Future<int> put(String key, Uint8List value)` — returns revision (stream sequence)
  - Publish to `$KV.<bucket>.<key>` using JetStream publish
  - Return sequence from PubAck
- `Future<KvEntry?> get(String key)` — returns entry or null if not found
  - Use direct get API: publish request to `$JS.API.DIRECT.GET.KV_<bucket>` with JSON payload `{"last_by_subj": "$KV.<bucket>.<key>"}`
  - Parse response (HMSG with headers + payload)
  - Return null if status 404
  - Construct `KvEntry` from response

**Critical Requirements**:
- Put must use JetStream publish (HPUB with headers)
- Get must handle 404 gracefully (return null, not throw)
- Revision is the JetStream stream sequence number

**Reference**: Architecture doc § 5.5 (KeyValue put/get)

---

### 3.3 KeyValue — Delete & Purge

**Goal**: Delete individual keys or all keys in a bucket.

**Deliverables**:
- `Future<void> delete(String key)`
  - Publish to `$KV.<bucket>.<key>` with:
    - Empty payload (`Uint8List(0)`)
    - Header: `KV-Operation: DEL`
  - This creates a delete marker (tombstone) — visible in watch
- `Future<void> purge(String key)`
  - Publish to `$KV.<bucket>.<key>` with:
    - Empty payload
    - Header: `KV-Operation: PURGE`
    - Header: `Nats-Rollup: sub`
  - This purges all history for this key
- `Future<void> purgeAll()`
  - Use `StreamManager.purgeStream('KV_<bucket>')`
  - Purges entire bucket (all keys)

**Critical Requirements**:
- Delete creates tombstone (shows up in watch with `isDeleted: true`)
- Purge removes history but does not show in watch
- PurgeAll is destructive (confirm with user if exposed in UI)

**Reference**: Architecture doc § 5.5 (KeyValue delete), § 2.1 (STREAM.PURGE)

---

### 3.4 KeyValue — Watch

**Goal**: Real-time stream of updates to a key or all keys.

**Deliverables**:
- `Stream<KvEntry> watch(String key)` — watch single key
  - Create `OrderedConsumer` with `filterSubject: "$KV.<bucket>.<key>"`
  - Convert `JsMsg` to `KvEntry` for each message
- `Stream<KvEntry> watchAll()` — watch all keys in bucket
  - Create `OrderedConsumer` with `filterSubject: "$KV.<bucket>.>"`
  - Convert `JsMsg` to `KvEntry` for each message
- Internal helper: `Stream<KvEntry> _watchSubject(String filter)`

**Critical Requirements**:
- Must use `OrderedConsumer` (not PullConsumer) for real-time updates
- Must handle sequence gaps via OrderedConsumer's auto-recreation
- Must parse operation type from `KV-Operation` header (PUT, DEL, PURGE)
- Must expose delete markers (`isDeleted: true` in KvEntry)

**Reference**: Architecture doc § 5.5 (KeyValue watch)

---

### 3.5 KvEntry Model

**Goal**: Represent a KeyValue entry with metadata.

**Deliverables**:
- `KvEntry` class with:
  - `String bucket`
  - `String key`
  - `Uint8List value`
  - `int revision` (stream sequence)
  - `DateTime created` (parsed from JetStream timestamp header)
  - `KvOp operation` (enum: put, del, purge)
- Convenience getters:
  - `String get valueString` → `utf8.decode(value)`
  - `bool get isDeleted` → `operation != KvOp.put`
- Factory: `KvEntry.fromJsMsg(JsMsg msg, String bucket)`
  - Parse key from subject: `$KV.<bucket>.<key>` → extract `<key>`
  - Parse operation from `KV-Operation` header (default: put)
  - Extract revision from `msg.info.streamSequence`
  - Extract timestamp from `Nats-Time-Stamp` header

**Critical Requirements**:
- Must parse key from subject correctly (handle multi-token keys with dots)
- Must default operation to `put` if header absent
- Must parse timestamp from ISO 8601 format in header

**Reference**: Architecture doc § 5.5 (KvEntry), Appendix A (Server → Client headers)

---

### 3.6 KvOp Enum

**Goal**: Strongly-typed operation types.

**Deliverables**:
- `enum KvOp { put, del, purge }`

---

### 3.7 Integration Tests — KeyValue

**Goal**: Validate KV operations against real NATS with JetStream.

**Test Cases**:
- Bucket creation (verify stream `KV_<bucket>` created with correct config)
- Put → Get round-trip
- Put twice → Get returns second value (single-message-per-subject retention)
- Delete → Get returns null (tombstone not returned by get)
- Delete → Watch sees delete entry with `isDeleted: true`
- Purge key → Watch does not see purge event (history removed)
- WatchAll → receives updates for multiple keys
- Watch → OrderedConsumer detects sequence gap and recreates

**Test Coverage Target**:
- **85%** for KeyValue logic
- **80%** for KvEntry parsing

---

### 3.8 Production Polish — Documentation

**Goal**: Comprehensive README and API documentation.

**Deliverables**:
- Update `README.md` with:
  - Installation instructions
  - Quick start example (connect, pub/sub)
  - JetStream example (stream, pull consumer, ack)
  - KeyValue example (put, get, watch)
  - Platform notes (TCP vs WebSocket)
  - Docker NATS server setup
- API doc comments (`///`) for all public classes and methods
- Example code in `example/` directory:
  - `example/basic.dart` — core pub/sub
  - `example/jetstream_pull.dart` — JetStream pull consumer
  - `example/kv_watch.dart` — KeyValue watch
  - `example/flutter_native_example.dart` — Flutter native app (TCP)
  - `example/flutter_web_example.dart` — Flutter web app (WebSocket)

**Reference**: Architecture doc § 1-10 (for accurate examples)

---

### 3.9 Production Polish — Error Handling

**Goal**: Graceful error handling and logging.

**Deliverables**:
- Wrap all server responses in try/catch with descriptive errors
- Validate API responses (check for `error` field in JSON)
- Throw `NatsException` (custom exception class) with:
  - `String message` (human-readable)
  - `int? code` (JetStream error code if available)
  - `String? description` (server error description)
- Log warnings for:
  - Reconnection attempts
  - Flow control requests
  - OrderedConsumer recreations

**Deliverables**:
- `NatsException` class
- Error handling in all API methods
- Optional: `Logger` instance for debug logging (use `package:logging`)

---

### 3.10 Production Polish — Performance

**Goal**: Optimize for production use.

**Optimizations**:
- Reuse `Nuid` instance across connection (thread-safe)
- Buffer publishes during reconnection (queue up to N messages)
- Batch subscribe/unsubscribe commands if many subscriptions created at once
- Use `BytesBuilder(copy: false)` in parser for zero-copy buffer management
- Profile and optimize hot paths (parser, encoder)

**Metrics** (optional):
- Track publish latency (time to PubAck)
- Track reconnection frequency
- Track message throughput (msgs/sec)

---

### 3.11 Production Polish — TLS Support (Optional)

**Goal**: Support TLS connections for production deployments.

**Deliverables** (if time permits):
- TLS support in `TcpTransport` (`SecureSocket` in dart:io)
- WSS (WebSocket Secure) support in `WebSocketTransport`
- `ConnectOptions` with:
  - `bool tls` (default: false)
  - `String? tlsCertPath` (client cert for mutual TLS)
  - `bool tlsVerify` (default: true, disable for self-signed certs)
- Detect `tls://` or `wss://` scheme and enable TLS automatically

**Critical Requirements**:
- Must validate server certificate (unless `tlsVerify: false`)
- Must support mutual TLS (client cert + server cert)

**Reference**: Architecture doc § 1.2 (INFO `tls_required` field)

---

### 3.12 Publication to pub.dev

**Goal**: Publish package to pub.dev for public use.

**Checklist**:
- [ ] `pubspec.yaml` has correct version, description, homepage
- [ ] `LICENSE` file present (MIT or Apache 2.0)
- [ ] `CHANGELOG.md` populated
- [ ] `README.md` complete with examples
- [ ] All tests pass (`dart test`)
- [ ] No analyzer warnings (`dart analyze`)
- [ ] Code formatted (`dart format`)
- [ ] Documentation score 100% (`dart pub publish --dry-run`)
- [ ] Example code runs successfully
- [ ] CI/CD pipeline configured (GitHub Actions)
- [ ] Run `dart pub publish` (requires Dart/Flutter account)

**Reference**: pub.dev publishing guidelines

---

## Test Requirements

### Unit Tests
- KvEntry parsing from JsMsg
- KvEntry key extraction from subject
- KvEntry timestamp parsing
- KvOp enum conversions

### Integration Tests (Docker NATS with JetStream)
- Bucket creation (stream config validation)
- Put/Get/Delete/Purge operations
- Watch single key (real-time updates)
- WatchAll (multiple keys)
- Delete marker in watch
- OrderedConsumer recreation on gap (inject gap by external stream edit)

### End-to-End Tests
- Flutter native app (TCP) — pub/sub, JetStream, KV
- Flutter web app (WebSocket) — pub/sub, JetStream, KV
- Reconnection during active watch (kill server, verify watch resumes)

### Test Coverage Target
- **85%** overall package coverage
- **90%** for protocol layer (parser, encoder)
- **80%** for JetStream and KV

---

## Acceptance Criteria

1. ✅ All unit and integration tests pass
2. ✅ KeyValue CRUD operations work (put, get, delete, purge)
3. ✅ Watch provides real-time updates for single key and all keys
4. ✅ Delete markers visible in watch with `isDeleted: true`
5. ✅ OrderedConsumer handles sequence gaps correctly
6. ✅ README is complete with installation, examples, and platform notes
7. ✅ API documentation (`///` comments) on all public APIs
8. ✅ Example code runs successfully on Flutter native and web
9. ✅ Error handling is graceful (no uncaught exceptions)
10. ✅ `dart pub publish --dry-run` passes with 100% score
11. ✅ No analyzer warnings (`dart analyze`)
12. ✅ Code formatted (`dart format`)
13. ✅ CHANGELOG.md reflects all changes
14. ✅ Package published to pub.dev (or ready to publish)

---

## Dependencies & Blockers

**External Dependencies**:
- Phase 2 complete (JetStream with OrderedConsumer)
- Docker NATS with JetStream enabled

**Optional Dependencies**:
- `package:logging` for structured logging (if added)
- CI/CD setup (GitHub Actions recommended)

---

## Out of Scope (Post-MVP Enhancements)

- Object store (separate from KeyValue, requires large message support)
- Service API (NATS microservices framework)
- Leafnode connections
- NATS account JWT generation (use NATS CLI for setup)
- Advanced monitoring (metrics, tracing)
- NATS supercluster support (multi-region)

---

## Reference Implementation

Primary: `nats.deno` (TypeScript)
- `nats-base-client/kv.ts` — Full KeyValue implementation
- `nats-base-client/jsbaseclient_api.ts` — Bucket management
- `tests/kv_test.ts` — KV integration tests

---

## Post-Publication Roadmap

After Phase 3 and publication, future enhancements:
1. TLS support (if not included in Phase 3)
2. Object store API
3. Service API (microservices framework)
4. Advanced monitoring and metrics
5. Performance benchmarks vs other NATS clients
6. Community feedback integration

---

## Success Metrics

**Technical**:
- Package published to pub.dev
- 0 critical bugs in first month
- Test coverage ≥ 85%
- Documentation score 100%

**Community**:
- 10+ pub.dev likes in first month
- 50+ package downloads in first week
- GitHub stars ≥ 20 in first month
- At least 1 community contribution (issue or PR)

**Braven Lab Studio Unblocked**:
- Braven test session streaming works on Flutter native and web
- Real-time KV watch provides < 100ms latency for session updates
- Zero message loss during reconnection
