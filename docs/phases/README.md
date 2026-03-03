# nats_dart Implementation Phases — Overview

**Project**: nats_dart — Native Dart/Flutter NATS Client  
**Date**: February 23, 2026  
**Document Type**: Implementation Planning  

---

## Purpose

This document provides a high-level overview of the 3-phase implementation plan for `nats_dart`. The full architecture reference has been decomposed into discrete, spec-ready phases that can be implemented sequentially.

Each phase:
- Has clear scope and deliverables
- Builds on the previous phase
- Has specific acceptance criteria
- Includes comprehensive test requirements
- References the architecture document for technical details

---

## Phase Structure

| Phase | Focus | Duration | Dependencies | Milestone |
|-------|-------|----------|--------------|-----------|
| **Phase 1** | Foundation & Core Client | 2-3 weeks | None | All Flutter platforms can pub/sub/request |
| **Phase 2** | JetStream | 2-3 weeks | Phase 1 | Full JetStream on all platforms |
| **Phase 3** | KeyValue & Production | 1-2 weeks | Phase 2 | Publishable package on pub.dev |

**Total Estimated Duration**: 5-8 weeks

---

## Phase 1: Foundation & Core Client

**File**: [phase-1-foundation.md](./phase-1-foundation.md)

**Overview**: Implement the Pure Dart NATS protocol layer with platform-specific transport abstraction.

### Key Deliverables

1. **Protocol Parser** (§1.1)
   - Stateful byte-buffer parser for MSG, HMSG, INFO, PING, +OK, -ERR
   - Header section parser with status code extraction
   - Handle partial frames and multi-value headers

2. **Protocol Encoder** (§1.2)
   - CONNECT, PUB, HPUB, SUB, UNSUB, PING/PONG commands
   - Byte-perfect HPUB with exact byte counting
   - JSON serialization for CONNECT

3. **Transport Abstraction** (§1.3)
   - Abstract `Transport` interface
   - `TcpTransport` (dart:io) for native platforms
   - `WebSocketTransport` (web_socket_channel) for all platforms
   - Conditional imports based on `dart.library.io` / `dart.library.html`

4. **NUID Generator** (§1.4)
   - Base62 unique ID generator
   - Inbox subject generation
   - Thread-safe with sequence wraparound

5. **NatsConnection** (§1.5)
   - Core pub/sub API
   - Request/reply pattern
   - Connection lifecycle management
   - PING/PONG keepalive

6. **Subscription Management** (§1.6)
   - Stream-based subscription API
   - SID allocation and routing
   - Wildcard support (`*`, `>`)
   - Queue groups

7. **Authentication** (§1.8)
   - Token, user/pass, NKey, JWT support
   - Nonce signing for challenge-response

8. **Reconnection** (§1.9)
   - Automatic reconnection with exponential backoff
   - Subscription replay
   - Connection status stream

### Success Criteria
- ✅ All platforms (native + web) can connect via appropriate transport
- ✅ Pub/sub and request/reply work correctly
- ✅ Reconnection restores subscriptions automatically
- ✅ No platform-specific code outside `transport/` directory

---

## Phase 2: JetStream

**File**: [phase-2-jetstream.md](./phase-2-jetstream.md)

**Overview**: Implement JetStream persistent streaming on top of core NATS protocol.

### Key Deliverables

1. **JetStreamContext** (§2.1)
   - Entry point for JetStream operations
   - Domain support for multi-tenant deployments
   - API subject helper (`$JS.API.*`)

2. **StreamManager** (§2.2-2.3)
   - Stream CRUD operations
   - `StreamConfig` and `StreamInfo` models
   - Paginated list support

3. **ConsumerManager** (§2.4-2.5)
   - Consumer CRUD operations
   - Ephemeral and durable consumers
   - `ConsumerConfig` and `ConsumerInfo` models

4. **JetStream Publish** (§2.6-2.7)
   - Publish with PubAck
   - Deduplication via `Nats-Msg-Id` header
   - `PubAck` model with duplicate detection

5. **PullConsumer** (§2.8)
   - Batch fetch with timeout
   - Continuous consume stream
   - Status code handling (404, 408, 409)

6. **JsMsg & Acknowledgment** (§2.9-2.10)
   - Ack/nak/term/inProgress methods
   - Ack subject parsing
   - `JsMsgInfo` metadata extraction

7. **OrderedConsumer** (§2.11)
   - Sequence gap detection
   - Auto-recreation on gaps
   - Flow control handling

8. **Flow Control** (§2.12)
   - Automatic flow control reply
   - Status 100 detection and response

### Success Criteria
- ✅ Stream and consumer management work
- ✅ Publish receives PubAck with deduplication
- ✅ Pull consumer fetch and consume streams work
- ✅ Message acknowledgment (ack/nak/term) verified
- ✅ OrderedConsumer detects gaps and recreates correctly
- ✅ Flow control replies sent automatically

---

## Phase 3: KeyValue & Production Ready

**File**: [phase-3-keyvalue-production.md](./phase-3-keyvalue-production.md)

**Overview**: Implement KeyValue store and polish package for pub.dev publication.

### Key Deliverables

1. **KeyValue API** (§3.1-3.2)
   - Bucket management (create/get)
   - Put and get operations
   - Direct get API for low latency

2. **KeyValue Operations** (§3.3)
   - Delete (tombstone marker)
   - Purge (remove history)
   - PurgeAll (clear bucket)

3. **KeyValue Watch** (§3.4)
   - Real-time updates via OrderedConsumer
   - Watch single key
   - Watch all keys in bucket

4. **KvEntry Model** (§3.5-3.6)
   - Entry metadata (revision, timestamp, operation)
   - Delete marker detection
   - String value convenience getter

5. **Documentation** (§3.8)
   - Complete README with examples
   - API documentation (`///` comments)
   - Example apps (Flutter native + web)

6. **Error Handling** (§3.9)
   - Graceful error handling
   - `NatsException` class
   - Debug logging (optional)

7. **Performance** (§3.10)
   - Parser optimization
   - Publish buffering during reconnection
   - Batch operations

8. **TLS Support** (§3.11 — Optional)
   - TLS/WSS connections
   - Client certificate support

9. **Publication** (§3.12)
   - pub.dev publication checklist
   - CI/CD pipeline
   - CHANGELOG and LICENSE

### Success Criteria
- ✅ KeyValue put/get/delete/watch work correctly
- ✅ Watch provides real-time updates
- ✅ Delete markers visible in watch
- ✅ README complete with examples
- ✅ Example apps run on native and web
- ✅ `dart pub publish --dry-run` passes
- ✅ Package published to pub.dev

---

## Architectural Principles (All Phases)

### Pure Dart First
- Protocol logic is 100% Pure Dart
- Platform differences only in `transport/` implementation
- No runtime platform checks (compile-time only)

### Test-Driven Development
- Tests written BEFORE implementation
- Unit tests for protocol layer (no server)
- Integration tests against Docker NATS
- Minimum 80% coverage target

### SOLID Principles
- **Single Responsibility**: Each class has one reason to change
- **Open/Closed**: Extend via interfaces, not modification
- **Liskov Substitution**: All implementations honor contracts
- **Interface Segregation**: No forced dependencies
- **Dependency Inversion**: Depend on abstractions

---

## Reference Documents

- **Architecture Reference**: `docs/nats_dart_architecture_reference.md` — Complete technical specification
- **Constitution**: `.github/copilot-instructions.md` — Project principles and patterns
- **Phase Details**:
  - Phase 1: `docs/phases/phase-1-foundation.md`
  - Phase 2: `docs/phases/phase-2-jetstream.md`
  - Phase 3: `docs/phases/phase-3-keyvalue-production.md`

---

## Getting Started with a Phase

### Workflow for Each Phase

1. **Read Phase Document**
   - Understand scope and deliverables
   - Review acceptance criteria
   - Check dependencies (previous phases complete?)

2. **Review Architecture Reference**
   - Study relevant sections referenced in phase doc
   - Review protocol specifications
   - Check reference implementations (nats.deno)

3. **Set Up Test Environment**
   - Start Docker NATS server (see Architecture doc §8)
   - Configure WebSocket port for Flutter Web testing
   - Verify JetStream enabled (Phase 2+)

4. **Write Tests First (TDD)**
   - Create test skeletons (`test.skip()`)
   - Define expected behavior
   - Run tests (should fail initially)

5. **Implement Feature**
   - Follow SOLID principles
   - Keep platform-specific code in `transport/` only
   - Document as you go (`///` comments)

6. **Verify Acceptance Criteria**
   - All tests pass
   - No analyzer warnings
   - Code formatted
   - Manual testing on target platforms

7. **Update Documentation**
   - Update CHANGELOG.md
   - Add examples if needed
   - Update README (Phase 3)

---

## Tools & Dependencies

### Development
- **Dart SDK**: ≥3.0.0
- **Flutter SDK**: ≥3.10.0 (for example apps)
- **Docker**: For NATS server testing
- **VS Code** or **IntelliJ IDEA**: Recommended IDEs

### Packages
- **Production**:
  - `web_socket_channel` — WebSocket transport
- **Development**:
  - `test` — Unit and integration testing
  - `mockito` — Mocking for unit tests
  - `lints` — Dart linting rules

### External Services
- **Docker NATS**: `docker run nats:latest -js --websocket_port 9222 --websocket_no_tls`
- **demo.nats.io**: Public NATS server (core only, no JetStream)

---

## Risk Management

### Phase 1 Risks
- **NKey authentication**: May require custom Ed25519 implementation
  - **Mitigation**: Start with token/user-pass auth, defer NKey if complex
- **WebSocket CORS**: Browser security may block connections
  - **Mitigation**: Configure NATS server `allowed_origins` correctly

### Phase 2 Risks
- **OrderedConsumer complexity**: Sequence gap detection is intricate
  - **Mitigation**: Study nats.deno implementation carefully; extensive testing
- **Flow control timing**: Must reply instantly to avoid stalls
  - **Mitigation**: Profile flow control path; ensure no blocking operations

### Phase 3 Risks
- **KeyValue edge cases**: Delete markers, purge semantics can be subtle
  - **Mitigation**: Replicate nats.deno KV tests exactly
- **Publication blockers**: pub.dev may reject for policy violations
  - **Mitigation**: Run `dart pub publish --dry-run` early and often

---

## Success Metrics

### Phase Completion
- [ ] Phase 1: All acceptance criteria met
- [ ] Phase 2: All acceptance criteria met
- [ ] Phase 3: Package published to pub.dev

### Technical Quality
- Test coverage ≥ 80%
- Zero analyzer warnings
- Documentation score 100%
- Example code runs on native and web

### Community (Post-Publication)
- 50+ downloads in first week
- 10+ pub.dev likes in first month
- At least 1 community contribution

---

## Next Steps

1. **Review this overview** with the team
2. **Read Phase 1 document** in detail
3. **Set up development environment** (Dart SDK, Docker NATS)
4. **Begin Phase 1 implementation** using TDD workflow
5. **Update architecture reference** as implementation reveals new details

---

**Questions?** Refer to:
- Architecture reference for technical details
- Constitution for coding principles
- Phase documents for specific deliverables
- nats.deno source code for reference implementation
