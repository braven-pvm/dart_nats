# Architecture Reference → Phase Mapping

**Purpose**: Maps sections of the architecture reference document to implementation phases for easy navigation during development.

---

## Quick Reference

| Architecture Section | Phase | Phase Section | Priority |
|---------------------|-------|---------------|----------|
| § 1 — NATS Wire Protocol Reference | Phase 1 | § 1.1 (Parser), § 1.2 (Encoder) | Critical |
| § 2 — JetStream Protocol Reference | Phase 2 | § 2.1-2.12 | Critical |
| § 3 — Package Architecture | Phase 1 | § 1.3 (Transport), § 1.5 (Connection) | Critical |
| § 4 — Protocol Parser | Phase 1 | § 1.1 | Critical |
| § 5 — JetStream & KV Implementation | Phase 2, 3 | § 2.8-2.11, § 3.1-3.5 | Critical |
| § 6 — NUID Generator | Phase 1 | § 1.4 | Critical |
| § 7 — Authentication & Reconnection | Phase 1 | § 1.8, § 1.9 | High |
| § 8 — Server Configuration | All | Test setup | Reference |
| § 9 — Build Plan & Test Strategy | All | Test requirements | Reference |
| § 10 — Reference Sources | All | — | Reference |

---

## Architecture § 1: NATS Wire Protocol Reference

### Implementation Locations

| Subsection | Phase | Implementation |
|-----------|-------|----------------|
| § 1.1 Protocol Command Summary | Phase 1 | Parser (§ 1.1), Encoder (§ 1.2) |
| § 1.2 INFO Fields | Phase 1 | NatsConnection (§ 1.5) — INFO parsing |
| § 1.3 CONNECT Fields | Phase 1 | Encoder (§ 1.2), Authentication (§ 1.8) |
| § 1.4 HPUB Format | Phase 1 | Encoder (§ 1.2) — byte counting |
| § 1.5 HMSG Format | Phase 1 | Parser (§ 1.1) — header parsing |
| § 1.6 Subject Naming | Phase 1 | Subscription (§ 1.6) — wildcard support |

**Critical Details**:
- HPUB byte counting must be exact (header bytes include `NATS/1.0\r\n` + headers + `\r\n\r\n`)
- HMSG status codes (100, 404, 408, 409) parsed in Phase 1, used in Phase 2
- `headers: true` in CONNECT is **required** for JetStream (validate in Phase 1)

---

## Architecture § 2: JetStream Protocol Reference

### Implementation Locations

| Subsection | Phase | Implementation |
|-----------|-------|----------------|
| § 2.1 JetStream API Subjects | Phase 2 | JetStreamContext (§ 2.1), Managers (§ 2.2, 2.4) |
| § 2.2 StreamConfig | Phase 2 | StreamManager (§ 2.2-2.3) |
| § 2.3 ConsumerConfig | Phase 2 | ConsumerManager (§ 2.4-2.5) |
| § 2.4 Pull Fetch Request | Phase 2 | PullConsumer (§ 2.8) |
| § 2.5 Ack Subjects & Types | Phase 2 | JsMsg (§ 2.9-2.10) |
| § 2.6 JetStream Publish Flow | Phase 2 | JetStream Publish (§ 2.6-2.7) |

**Critical Details**:
- All JetStream APIs use HPUB (from Phase 1)
- Pull fetch request times are in **nanoseconds** (not microseconds)
- Flow control (status 100) must be replied to instantly (no delay)

---

## Architecture § 3: Package Architecture

### Implementation Locations

| Subsection | Phase | Implementation |
|-----------|-------|----------------|
| § 3.1 Directory Structure | All | File organization |
| § 3.2 Transport Abstraction | Phase 1 | Transport (§ 1.3) |
| § 3.3 Abstract Transport Interface | Phase 1 | Transport (§ 1.3) |
| § 3.4 NatsConnection Public API | Phase 1 | NatsConnection (§ 1.5) |
| § 3.5 ConnectOptions | Phase 1 | ConnectOptions (§ 1.10) |

**Critical Details**:
- Conditional imports in `transport_factory.dart` (compile-time platform selection)
- No `dart:io` or `dart:html` imports outside `transport/` directory

---

## Architecture § 4: Protocol Parser

### Implementation

**Phase 1 § 1.1 — Protocol Parser**

All code examples in architecture § 4 map directly to Phase 1 parser implementation:
- § 4.1 Parser State Machine → `NatsParser` class
- § 4.2 MSG/HMSG Parsing → `_parseMsgOrHmsg()` method
- § 4.3 Header Section Parser → `_parseHeaderSection()` method
- § 4.4 NatsMessage Model → `NatsMessage` class (§ 1.11)

**Critical Details**:
- Parser must be stateful (handle partial frames)
- Header section ends with `\r\n\r\n` (blank line)
- Status code in first line: `NATS/1.0 <code> <description>`

---

## Architecture § 5: JetStream & KV Implementation

### Implementation Locations

| Subsection | Phase | Implementation |
|-----------|-------|----------------|
| § 5.1 JetStreamContext | Phase 2 | JetStreamContext (§ 2.1) |
| § 5.2 PullConsumer | Phase 2 | PullConsumer (§ 2.8) |
| § 5.3 JsMsg — Ack Model | Phase 2 | JsMsg (§ 2.9-2.10) |
| § 5.4 OrderedConsumer | Phase 2 | OrderedConsumer (§ 2.11) |
| § 5.5 KeyValue API | Phase 3 | KeyValue (§ 3.1-3.5) |

**Critical Details**:
- OrderedConsumer is foundational for KV watch (Phase 3 depends on Phase 2 implementation)
- KeyValue bucket is a JetStream stream named `KV_<bucket>`
- Watch uses OrderedConsumer with filter subject

---

## Architecture § 6: NUID Generator

### Implementation

**Phase 1 § 1.4 — NUID Generator**

Code in architecture § 6 can be ported directly to Dart:
- Base62 alphabet: `0-9A-Za-z`
- 22-character output (12-char prefix + 10-char sequence)
- Sequence wraps at `_maxSeq = 839299365868340224` (62^10)

**Critical Details**:
- Must use `Random.secure()` for cryptographic randomness
- Thread-safe (use isolate-local instance)
- Port from `nats.deno/nats-base-client/nuid.ts`

---

## Architecture § 7: Authentication & Reconnection

### Implementation Locations

| Subsection | Phase | Implementation |
|-----------|-------|----------------|
| § 7.1 Authentication Modes | Phase 1 | Authentication (§ 1.8) |
| § 7.2 JWT + NKey Handshake | Phase 1 | Authentication (§ 1.8) |
| § 7.3 Reconnection & Replay | Phase 1 | Reconnection (§ 1.9) |

**Critical Details**:
- NKey signing may require external library (Ed25519)
- Reconnection must replay subscriptions in original order
- JetStream pull consumers need new fetch requests after reconnect (not automatic)

---

## Architecture § 8: Server Configuration

### Usage Across Phases

**Phase 1**: Docker NATS for integration tests (core pub/sub)
**Phase 2**: Docker NATS with `-js` flag (JetStream enabled)
**Phase 3**: Same as Phase 2 (KV uses JetStream)

**Quick Start**:
```bash
docker run -p 4222:4222 -p 9222:9222 -p 8222:8222 nats:latest \
  -js --websocket_port 9222 --websocket_no_tls
```

**Verify JetStream**:
```bash
curl http://localhost:8222/varz | jq '.jetstream'
```

---

## Architecture § 9: Build Plan & Test Strategy

### Phase Alignment

Architecture § 9.1 defines 3 phases — these align with the phase documents:
- **Architecture Phase 1** → `docs/phases/phase-1-foundation.md`
- **Architecture Phase 2** → `docs/phases/phase-2-jetstream.md`
- **Architecture Phase 3** → `docs/phases/phase-3-keyvalue-production.md`

**MVP Scope** (Architecture § 9.2) is covered by:
- Phase 1: Parser, encoder, transport, auth
- Phase 2: JetStream publish, pull consumer, ack
- Phase 3: KeyValue put, get, watch

**Test Matrix** (Architecture § 9.3) is distributed across all phases:
- Phase 1 tests: Parser, encoder, transport, reconnection
- Phase 2 tests: JetStream API, pull consumer, flow control
- Phase 3 tests: KeyValue CRUD, watch, end-to-end

---

## Architecture § 10: Reference Sources

### Usage by Phase

**Phase 1**:
- NATS Client Protocol Spec (Wire protocol commands)
- ADR-4: NATS Headers (HPUB/HMSG format)
- nats.deno parser.ts, core.ts, nuid.ts

**Phase 2**:
- JetStream Wire API Reference ($JS.API.* subjects)
- JetStream Consumers (Pull vs push, ordered consumers)
- nats.deno jetstream.ts, consumermessages.ts, consumer.ts

**Phase 3**:
- NATS KV Concepts (Bucket design, operations)
- nats.deno kv.ts

---

## Development Workflow

### Using This Mapping During Implementation

1. **Starting a Phase**:
   - Read phase document (e.g., `phase-1-foundation.md`)
   - Identify architecture sections via this mapping
   - Review architecture details for those sections

2. **Implementing a Feature**:
   - Find feature in phase document (e.g., "Protocol Parser")
   - Use this mapping to locate architecture reference (e.g., "§ 4")
   - Study architecture examples and pseudocode
   - Port to Dart following phase requirements

3. **Writing Tests**:
   - Phase document lists test requirements
   - Architecture § 9.3 (Test Matrix) provides edge cases
   - nats.deno tests provide additional scenarios

4. **Handling Ambiguity**:
   - Check architecture reference for clarification
   - Consult reference sources (§ 10)
   - Study nats.deno implementation
   - Ask in NATS Slack (#clients channel)

---

## Common Questions

### Q: Where do I find HPUB byte counting details?
**A**: Architecture § 1.4 (HPUB — Publishing with Headers)  
**Implemented in**: Phase 1 § 1.2 (Protocol Encoder)

### Q: How does OrderedConsumer work?
**A**: Architecture § 5.4 (OrderedConsumer)  
**Implemented in**: Phase 2 § 2.11 (OrderedConsumer)

### Q: What's the format of ack subjects?
**A**: Architecture § 2.5 (Ack Subjects & Ack Types)  
**Implemented in**: Phase 2 § 2.10 (JsMsgInfo — Ack Subject Parser)

### Q: How do I set up Docker NATS with JetStream?
**A**: Architecture § 8.1 (Docker Quick Start)  
**Used in**: All phases (test environment)

### Q: What's the difference between PullConsumer and OrderedConsumer?
**A**: Architecture § 5.2 vs § 5.4  
**Pull**: Batch fetch, manual ack (Phase 2 § 2.8)  
**Ordered**: Continuous stream, auto-recreation on gaps, no ack (Phase 2 § 2.11)

### Q: How does KeyValue relate to JetStream?
**A**: Architecture § 5.5 (KeyValue API)  
**KV bucket** = JetStream stream named `KV_<bucket>`  
**KV watch** = OrderedConsumer on `$KV.<bucket>.*`  
**Implemented in**: Phase 3 § 3.1-3.5

---

## Edge Cases & Gotchas

### HPUB Byte Counting (Phase 1)
**Issue**: Off-by-one errors in header byte count  
**Solution**: Header bytes include the trailing `\r\n\r\n`  
**Reference**: Architecture § 1.4 examples

### HMSG Status Codes (Phase 1 & 2)
**Issue**: Flow control not replied to → server stalls  
**Solution**: Detect status 100 + "Flow" in description → instant reply  
**Reference**: Architecture § 1.5 (HMSG Status Codes table)

### JetStream Times (Phase 2)
**Issue**: Using microseconds instead of nanoseconds  
**Solution**: All JetStream times are **nanoseconds** (Duration.inNanoseconds)  
**Reference**: Architecture § 2.3, § 2.4

### OrderedConsumer Sequence Gaps (Phase 2)
**Issue**: Missing messages not detected  
**Solution**: Track `_expectedSeq`, compare to `msg.info.streamSequence`  
**Reference**: Architecture § 5.4 (OrderedConsumer logic)

### KeyValue Delete vs Purge (Phase 3)
**Issue**: Delete doesn't remove entry  
**Solution**: Delete creates tombstone (visible in watch); Purge removes history  
**Reference**: Architecture § 5.5, Phase 3 § 3.3

---

## Summary

This mapping document helps navigate between:
- **Phase documents** (what to implement)
- **Architecture reference** (how to implement)
- **Reference implementations** (examples to study)

Use it as a quick reference during development to find the right details at the right time.
