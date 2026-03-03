# Implementation Plan: NATS Foundation & Core Client

**Branch**: `001-nats-foundation` | **Date**: February 23, 2026 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/001-nats-foundation/spec.md`

---

## Summary

Implement the foundational layer of `nats_dart` — a Pure Dart NATS client supporting pub/sub, request/reply, and automatic reconnection across all Flutter platforms (native iOS/Android/desktop + web). 

**Technical Approach**: 
- **Protocol Layer**: Pure Dart stateful parser + encoder (no platform dependencies) for NATS wire protocol (MSG, HMSG, INFO, PING, +OK, -ERR)
- **Platform Abstraction**: `Transport` interface with compile-time conditional imports — `TcpTransport` for native (dart:io), `WebSocketTransport` for all platforms (web_socket_channel)
- **Core API**: `NatsConnection` (pub/sub, request/reply), `Subscription` (message streams), `ConnectOptions` (auth + configuration)
- **Reliability**: Automatic reconnection with exponential backoff + transparent subscription replay + PING/PONG keepalive

**Key Milestone**: All Flutter platforms can connect, publish/subscribe, and maintain reliable connections with automatic recovery.

---

## Technical Context

**Language/Version**: Dart 3.11+ / Flutter 3.10+  
**Primary Dependencies**: `web_socket_channel` (WebSocket abstraction), `dart:io` (TCP, native only), `dart:html` (web APIs, web only)  
**Storage**: N/A (client library — state in memory)  
**Testing**: `test` package + `mockito` for mocks + Docker NATS server (integration)  
**Target Platform**: Flutter native (iOS/Android/macOS/Windows/Linux) + Flutter Web (Chrome/Firefox/Safari)  
**Project Type**: Dart library (pub.dev packag)  
**Performance Goals**:
  - Throughput: ≥50,000 msgs/sec (TCP), ≥10,000 msgs/sec (WebSocket)
  - Latency: <5ms p50, <20ms p99 (TCP); <15ms p50, <50ms p99 (WebSocket)
  - Reconnection: <1s to restore subscriptions (100ms baseline)
**Constraints**:
  - <200KB added to native binary (release build)
  - <150KB added to web bundle (gzipped)
  - Pure Dart only (no FFI, no platform channels)
  - Compile-time platform selection (no runtime kIsWeb checks)
  - 99% subscription recovery after network interruption
**Scale/Scope**: Single-isolate, single-server architecture (Phase 1); cluster support Phase 3+

---

## Constitution Check

*GATE: Must pass Pure Dart, TDD, and SOLID principles. Re-check after Phase 1 design.*

### I. Pure Dart Principle — ✅ **COMPLIANT**

**Gate**: All protocol logic must be Pure Dart; platform differences isolated to `transport/` only.

**Status**: 
- ✅ Parser, encoder, NUID, connection logic: **100% Pure Dart** (no dart:io, no dart:html)
- ✅ Transport abstraction: All platform code isolated in `lib/src/transport/` directory
- ✅ Conditional imports: Used **only** in `transport_factory.dart` with `if (dart.library.io)` / `if (dart.library.html)` patterns
- ✅ No runtime kIsWeb checks in protocol/connection layer

**Justification**: Phase 1 design enforces strict separation — protocol is identical across platforms, only TCP vs WebSocket differs.

---

### II. Test-Driven Design (TDD) — ✅ **COMPLIANT**

**Gate**: Tests must exist before implementation. Minimum coverage: 80% protocol, 70% connection logic, 60% platform.

**Approach**:
- ✅ Unit tests for parser/encoder (pre-recorded byte sequences, no server needed)
- ✅ Unit tests for NUID (uniqueness, format, rollover)
- ✅ Integration tests for transport (Docker NATS: TCP + WebSocket)
- ✅ Integration tests for pub/sub, request/reply, reconnection
- ✅ Platform tests (Flutter native iOS/Android simulators, Flutter Web Chrome)
- ✅ Performance tests (throughput, latency, memory)

**Justification**: Parser/encoder are critical — exact byte matching with spec required. TDD ensures correctness.

---

### III. SOLID Principles — ✅ **COMPLIANT**

**S — Single Responsibility**:
- ✅ `NatsParser`: Parse only (no auth, no connection management)
- ✅ `NatsEncoder`: Encode only (no validation)
- ✅ `NatsConnection`: Orchestration only (delegates to parser, encoder, transport)
- ✅ `Subscription`: Message routing only (no pub/sub logic)

**O — Open/Closed**:
- ✅ `Transport` interface: extensible to new implementations (no modification needed)
- ✅ `ConnectOptions` for auth: supports token, user/pass, NKey, JWT without changing connection code

**L — Liskov Substitution**:
- ✅ `TcpTransport` and `WebSocketTransport` fully substitute for `Transport` interface
- ✅ Connection code works with any Transport implementation

**I — Interface Segregation**:
- ✅ `Subscription` exposes only `Stream<NatsMessage> get messages` (minimal interface)
- ✅ `Transport` exposes only required methods (incoming, write, close, isConnected, errors)

**D — Dependency Inversion**:
- ✅ `NatsConnection` depends on `Transport` interface (not concrete TcpTransport)
- ✅ Auth logic injected via `ConnectOptions` (not hardcoded)

**Justification**: Architecture enforces SOLID boundaries — easy to test, extend, refactor.

---

## Project Structure

### Documentation (this feature)

```text
specs/001-nats-foundation/
├── spec.md              # Feature specification ✅ COMPLETE
├── plan.md              # This file (Phase 1: Design Planning)
├── research.md          # Phase 0: Research on ambiguities (SKIPPED - no ambiguities found)
├── data-model.md        # Phase 1: Entity models and contracts
├── quickstart.md        # Phase 1: Developer quick-start guide
├── contracts/           # Phase 1: Interface contracts (API, transport)
│   ├── nats-protocol.md
│   ├── transport-interface.md
│   └── connection-api.md
├── checklists/          # Quality assurance
│   └── requirements.md   # Requirements validation ✅ PASS
└── tasks.md             # Phase 2: Task breakdown (created via /speckit.tasks)
```

### Source Code Structure

```text
lib/
├── nats_dart.dart                          # Public API barrel export
└── src/
    ├── transport/                          # Platform-specific (ONLY place for dart:io/html)
    │   ├── transport.dart                  # Abstract Transport interface
    │   ├── transport_factory.dart          # Conditional import selector
    │   ├── transport_factory_stub.dart     # Default export (non-platform)
    │   ├── transport_factory_io.dart       # dart:io — TCP + optional WS
    │   ├── transport_factory_web.dart      # dart:html — WS only
    │   ├── tcp_transport.dart              # TcpTransport implementation
    │   └── websocket_transport.dart        # WebSocketTransport implementation
    │
    ├── protocol/                           # Pure Dart (100% portable)
    │   ├── parser.dart                     # NatsParser — stateful byte-buffer parser
    │   ├── encoder.dart                    # NatsEncoder — protocol command encoder
    │   ├── message.dart                    # NatsMessage — parsed message model
    │   └── nuid.dart                       # Nuid — unique ID generator
    │
    └── client/                             # Pure Dart (uses transport abstraction)
        ├── connection.dart                 # NatsConnection — main client class
        ├── subscription.dart               # Subscription — active subscriptions
        └── options.dart                    # ConnectOptions — configuration

test/
├── unit/                                   # No server required
│   ├── parser_test.dart                    # MSG, HMSG, INFO, PING, +OK, -ERR parsing
│   ├── encoder_test.dart                   # HPUB/PUB/SUB/CONNECT encoding
│   ├── nuid_test.dart                      # Uniqueness, format, rollover
│   └── message_test.dart                   # NatsMessage model
│
└── integration/                            # Docker NATS required
    ├── tcp_transport_test.dart             # Native TCP socket behavior
    ├── websocket_transport_test.dart       # WebSocket connections
    ├── connection_test.dart                # Full pub/sub lifecycle
    ├── request_reply_test.dart             # Request/reply pattern
    ├── reconnection_test.dart              # Auto-reconnect + subscription replay
    ├── auth_test.dart                      # Authentication modes (token, user/pass, NKey, JWT)
    └── platform_test.dart                  # Flutter native & web specific tests

example/
├── basic.dart                              # Simple pub/sub example
├── flutter_native_example.dart             # Flutter native example (TCP)
└── flutter_web_example.dart                # Flutter web example (WebSocket)
```

**Structure Decision**: Single Dart library package with platform abstraction via conditional imports. Pure Dart protocol layer; platform differences isolated to `transport/` only. This approach minimizes code duplication, ensures protocol consistency, and enables same application code on all platforms.

---

## Implementation Phases

### Phase 0: Research (SKIPPED)
**Status**: Skipped — No ambiguities found in specification review  
**Output**: None required

**Rationale**: Spec passed clarification gate (no NEEDS CLARIFICATION markers, all requirements clear). No unknowns blocking design.

---

### Phase 1: Design & Data Models (THIS PHASE)

**Duration**: 1 week  
**Deliverables**:
1. **data-model.md** — Entity definitions (NatsConnection, Subscription, NatsMessage, Transport, ConnectOptions)
2. **quickstart.md** — Developer quick-start with code examples
3. **contracts/** — Interface specifications:
   - `nats-protocol.md` — Wire protocol format (reference)
   - `transport-interface.md` — Transport contract for implementations
   - `connection-api.md` — Public NatsConnection API surface
4. **Agent context update** — Update copilot agent with Phase 1 technologies

**Outputs**: Design documents for Phase 2 task breakdown

---

### Phase 2: Task Breakdown (NEXT PHASE)
**Trigger**: `/speckit.tasks` command after Phase 1 design complete  
**Duration**: 1-2 hours  
**Output**: `tasks.md` — Granular implementation tasks organized by subsystem

**Task Categories** (estimated):
- **Protocol Layer** (FR-1, FR-2): Parser + Encoder (high complexity, high testing effort)
- **Transport Abstraction** (FR-3): Transport interface + TCP + WebSocket (medium-high complexity)
- **Core Client** (FR-5, FR-6, FR-7): NatsConnection + subscriptions + request/reply (high complexity)
- **NUID Generator** (FR-4): ID generator (low-medium complexity, well-spec'd)
- **Authentication** (FR-8): Auth modes implementation (medium complexity)
- **Reconnection** (FR-9): Auto-reconnect + subscription replay (high complexity, high risk)
- **Configuration** (FR-10, FR-11): ConnectOptions + NatsMessage (low complexity)
- **Testing Infrastructure** (Unit, Integration, Platform): Docker setup, test harnesses

---

## Complexity Tracking

**Justification of Design Decisions**:

### Decision 1: Pure Dart Protocol with Platform-Specific Transport
**Why**: NATS wire protocol is deterministic and portable. Transport is the only platform-dependent concern.
**Benefit**: 100% code reuse across platforms; identical test suites on all platforms; smaller binary (tree-shaking removes unused transport)
**Trade-off**: Cannot use platform-native cryptography libraries (for NKey auth) — must implement or use Dart port
**Accepted**: Yes — worth the trade-off for code reuse

### Decision 2: Conditional Imports (Compile-Time) vs Runtime kIsWeb
**Why**: Compile-time selection enables tree-shaking; runtime checks bloat all builds
**Benefit**: Smaller binary size (Phase 1 constraint: <200KB), optimal for each platform
**Trade-off**: More complex build configuration, requires careful export management
**Accepted**: Yes — aligns with Phase 1 size constraints

### Decision 3: Stateful Parser vs Event-Based
**Why**: Messages can span multiple network packets; stateful parsing handles this naturally
**Benefit**: Simpler to understand and test; direct port from nats.deno (proven reference)
**Trade-off**: Parser maintains internal buffer state (careful mutability management needed)
**Accepted**: Yes — proven approach with clear test paths

### Decision 4: Auto-Reconnect + Subscription Replay (Not Manual)
**Why**: Rebuilding subscriptions after reconnect is error-prone; app shouldn't manage it
**Benefit**: Reliable UX; reduces application code complexity; matches user expectation from mobile apps
**Trade-off**: Higher framework complexity (connection state machine, subscription tracking)
**Risk**: High (edge cases in reconnection logic)
**Accepted**: Yes — user scenarios require transparent reconnection

### Decision 5: Single-Isolate Architecture (Phase 1)
**Why**: Multi-isolate support adds significant complexity; Phase 1 is MVP
**Benefit**: Simpler architecture, easier testing, meets Braven use case
**Trade-off**: Applications needing multiple connections must use multiple isolates (documented limitation)
**Accepted**: Yes — deferred to Phase 3 if needed

---

## Quality Gates & Checkpoints

| Gate | Status | Owner | Check |
|------|--------|-------|-------|
| Pure Dart Principle | ✅ PASS | Design | No dart:io/html outside transport/ |
| TDD Strategy | ✅ PASS | QA | Test matrix covers all FR, SC |
| SOLID Architecture | ✅ PASS | Architecture | Interfaces cohesive, responsibilities clear |
| Scope Boundaries | ✅ PASS | PM | JetStream/KV/TLS clearly deferred |
| Dependency Clarity | ✅ PASS | Tech Lead | All external deps identified, Docker setup documented |
| Platform Strategy | ✅ PASS | Platform | TCP/WebSocket approach validated for target platforms |
| Performance Targets | ✅ PASS | Perf | Metrics quantified (50K TCP, 10K WS, <5ms latency) |

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| **HPUB Byte Counting** | Medium | High | Extensive reference comparison tests, byte dump utilities |
| **Reconnection Edge Cases** | High | High | Chaos engineering with server kill/restart scenarios, subscription state machine tests |
| **WebSocket Platform Differences** | Low | Medium | Use established `web_socket_channel` package, test on multiple browsers |
| **Parser Performance** | Low | Medium | Profile hot paths, use `BytesBuilder(copy: false)`, optimize incrementally |
| **NKey Cryptography** | Medium | High | Start with token/user-pass auth; evaluate Ed25519 libraries; defer NKey if complex |

---

## Next Steps

1. **Phase 1 Design** (this week):
   - Create `data-model.md` (entity definitions with state machines)
   - Create `quickstart.md` (developer guide with code examples)
   - Create `contracts/` (interface specifications)
   - Review and validate against spec

2. **Agent Context Update**:
   - Run `.specify/scripts/powershell/update-agent-context.ps1 -AgentType copilot`
   - Add Dart 3.11, Flutter 3.10, web_socket_channel to agent context

3. **Phase 2 Task Breakdown**:
   - Run `/speckit.tasks` to generate `tasks.md`
   - Organize tasks by subsystem and dependency graph
   - Assign effort estimates and risk levels

4. **Begin Implementation**:
   - Create test skeleton files (`test.skip()` stubs)
   - Implement parser (highest risk, critical path)
   - Implement encoder in parallel
   - Integration testing from week 2 onward

---

**Plan Status**: ✅ **READY FOR DESIGN PHASE**

All gates passed. Constitution alignment verified. Technical context clear. Ready to proceed with Phase 1 design documents.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
