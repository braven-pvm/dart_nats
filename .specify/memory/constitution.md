<!--
Sync Impact Report - Constitution Update
============================================
Version: 0.0.0 → 1.0.0 (MAJOR: Initial constitution ratification)

Changes:
- ✅ NEW: Pure Dart principle - platform abstraction through Transport interface
- ✅ NEW: Test-Driven Design (TDD) principle - tests before implementation
- ✅ NEW: SOLID Principles - comprehensive architectural guidelines
- ✅ NEW: Code Organization & Implementation section
- ✅ NEW: Quality & Development Workflow section
- ✅ NEW: Governance rules with ADRs and dependency philosophy

Templates Status:
- ✅ plan-template.md: Constitution Check section aligns with 3 core principles
- ✅ spec-template.md: Requirements structure supports TDD/testing requirements
- ✅ tasks-template.md: Phase organization supports test-first workflow

Follow-up Actions:
- None - all placeholders filled, all templates validated

Rationale for v1.0.0:
Initial constitution ratification based on existing copilot-instructions.md.
This establishes the foundational governance framework for nats_dart development.
============================================
-->

# nats_dart Constitution

**Applies To**: All development in the `nats_dart` package

## Core Principles

### I. Pure Dart (NON-NEGOTIABLE)

**Every line of code MUST be valid Dart.** Platform-specific logic is isolated exclusively to transport implementations.

- Platform differences handled **exclusively** via conditional imports in `transport_factory.dart`
- All protocol logic, parsing, JetStream, and KV APIs are **100% identical** across all platforms
- Protocol code tested without native dependencies (use stubs, not platform code)
- The `Transport` interface is the **only** abstraction boundary for platform differences
- No imports of `dart:io` outside of `transport/` directory
- Conditional imports (`if (dart.library.io)` / `if (dart.library.html)`) **only** in `transport_factory.dart`

**Rationale**: Maximum portability across Dart platforms (VM, Flutter, Web). Protocol correctness is platform-independent.

### II. Test-Driven Design (TDD) (NON-NEGOTIABLE)

**Tests exist BEFORE implementation.** All public APIs are testable and tested.

- Add test skeletons with `test.skip()` **before** writing implementation
- Every public method has at least one test
- Parser, encoder, NUID generator, and protocol logic are unit-tested in isolation
- Integration tests exercise real server connections (Docker NATS recommended)
- Minimum coverage targets:
  - Core protocol: **80%**
  - Platform-specific code: **60%**
- Red-Green-Refactor cycle strictly enforced

**Rationale**: Prevents regressions, ensures API ergonomics are considered up-front, and documents expected behavior through tests.

### III. SOLID Principles (NON-NEGOTIABLE)

Architecture follows SOLID principles to ensure maintainability and extensibility:

#### S — Single Responsibility
Each class has one reason to change. Example: `NatsParser` only parses; auth logic lives elsewhere.

#### O — Open/Closed
Extend via interfaces/subclassing, not modification. Example: `Transport` interface with `TcpTransport` and `WebSocketTransport` implementations.

#### L — Liskov Substitution
Implementations honor their interface contracts. Any `Transport` implementation must be substitutable without breaking `NatsConnection`.

#### I — Interface Segregation
Interfaces are minimal. No client forced to depend on methods it doesn't use. Example: `Subscription` interface only exposes `Stream<NatsMessage> get messages`.

#### D — Dependency Inversion
Depend on abstractions, not concretions. Example: `NatsConnection` accepts `Transport` interface, not `TcpTransport` directly.

**Rationale**: SOLID principles create clear boundaries, enable testing, and make the codebase resistant to coupling and fragility.

## Code Organization & Implementation

### Directory Structure

All code follows this strictly enforced layout:

```
lib/src/
├── transport/           # I/O abstraction (TCP, WebSocket)
│   ├── transport.dart           # Abstract interface
│   ├── transport_factory.dart   # Conditional import selector
│   ├── tcp_transport.dart       # dart:io implementation
│   └── websocket_transport.dart # web_socket_channel implementation
├── protocol/            # Wire protocol (codec, parsing)
│   ├── parser.dart      # Stateful MSG/HMSG/INFO parser
│   ├── encoder.dart     # HPUB/PUB/SUB/CONNECT encoder
│   ├── message.dart     # Protocol message model
│   └── nuid.dart        # Unique ID generator
├── client/              # High-level NATS API
│   ├── connection.dart  # NatsConnection (pub/sub, request/reply)
│   ├── subscription.dart
│   └── options.dart     # ConnectOptions & enums
├── jetstream/           # JetStream-specific APIs
│   ├── jetstream.dart
│   ├── stream_manager.dart
│   ├── consumer_manager.dart
│   ├── pull_consumer.dart
│   └── js_msg.dart
└── kv/                  # KeyValue store layer
    ├── kv.dart
    └── kv_entry.dart
```

### Implementation Guidelines

#### Protocol Layer (`lib/src/protocol/`)
- Parser MUST be **stateful** (handle multi-frame messages)
- Encoder output MUST be **byte-perfect** (exact byte counts for headers)
- Both MUST be **platform-agnostic** (no IO dependencies)
- Reference: [NATS Protocol Spec](https://docs.nats.io/reference/reference-protocols/nats-protocol)

#### Transport Layer (`lib/src/transport/`)
- **Only location** where `dart:io` and `web_socket_channel` may be imported
- All implementations MUST satisfy `Transport` interface contract
- TCP and WebSocket MUST have identical error handling contracts
- No protocol parsing in transports (parser is independent)

#### Connection & Auth (`lib/src/client/`)
- Reconnection logic with automatic subscription replay
- Auth methods decoupled from connection logic
- NUID generator injected (testable)
- Parser injected (testable, can be mocked)

#### JetStream & KeyValue (`lib/src/jetstream/`, `lib/src/kv/`)
- Built on pub/sub primitives (composition, not inheritance)
- PullConsumer: batch fetching, stream consumption
- OrderedConsumer: auto-recreation on sequence gaps
- KeyValue: idempotent put/get, watch for push updates

### Code Style & Formatting

#### Naming Conventions
- Classes: `PascalCase` (e.g., `NatsConnection`)
- Methods/variables: `camelCase`
- Constants: `camelCase` (Dart convention)
- Private members: prefix with `_`

#### Import Order
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nats_dart/src/...';

import '../other_module/file.dart';
```

#### Error Handling
- Never silently fail
- Throw with descriptive messages: `throw StateError('Connection closed')`
- Let caller decide error handling strategy (don't catch and ignore)
- Log errors appropriately, don't swallow them

#### Documentation
- Public APIs MUST have doc comments (`///`)
- Complex logic requires inline comments explaining **why**, not **what**
- Include usage examples in doc comments for non-obvious methods

## Quality & Development Workflow

### Test Requirements

#### Unit Tests (MUST exist before implementation)
- Parser tests: MSG, HMSG, INFO, PING, +OK, -ERR, status codes
- Encoder tests: PUB, HPUB, SUB, UNSUB, CONNECT
- NUID uniqueness and format validation
- Transport interface contracts (no platform-specific tests)
- All tests MUST be platform-agnostic

#### Integration Tests (run against Docker NATS)
- Connection lifecycle: connect, disconnect, reconnect
- Pub/sub and request/reply patterns
- Queue groups and wildcard subscriptions
- Authentication modes: token, user/pass, JWT, NKey
- JetStream: streams, consumers, pull fetch, ordered consumers
- KeyValue: put, get, delete, watch operations
- Error handling and edge cases

### Pre-Commit Quality Gates

Before pushing, ALL of the following MUST pass:

```bash
dart pub get
dart format lib test example     # Auto-format code
dart analyze lib test example    # Zero warnings/errors
dart test test/unit              # All unit tests pass (no skipped tests)
dart test test/integration       # If NATS server available
```

### Test Coverage

```bash
dart test --coverage=coverage
```

### Pull Request Checklist

All PRs MUST satisfy:

- [ ] Code is Pure Dart (no platform logic outside `transport/`)
- [ ] Tests exist BEFORE implementation
- [ ] All tests pass (`dart test`)
- [ ] No linter warnings (`dart analyze`)
- [ ] Code is formatted (`dart format`)
- [ ] SOLID principles respected (S, O, L, I, D)
- [ ] Public APIs documented with `///` doc comments
- [ ] No breaking changes without team discussion
- [ ] Commit message follows convention: `<type>(<scope>): <description>`
- [ ] Git history is clean (squash commits if needed)

### Commit Message Format

- **Format**: `<type>(<scope>): <description>`
- **Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
- **Example**: `feat(jetstream): implement pull consumer fetch()`

## Governance

### Architecture Decision Records (ADRs)

Significant design decisions (new module, major redesign, protocol changes) MUST be documented in `docs/adr/`:

**Format**:
```markdown
# ADR-NNN: [Decision Title]

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-XXX]

## Context
[Why this decision is needed, constraints, background]

## Decision
[What we decided to do and how]

## Consequences
[Positive and negative outcomes, trade-offs]
```

**Example**: See ADR-001 (Conditional Transport Imports) in copilot-instructions.md

### Dependency Philosophy

**Minimal and vetted dependencies only:**

- `web_socket_channel`: Required for Flutter Web WebSocket support
- Dev dependencies: `lints`, `mockito`, `test`
- No JSON serialization libraries beyond `dart:convert`
- No async/concurrency libraries beyond `dart:async`

**Rationale**: NATS is a foundational protocol layer. Keep it lightweight, portable, and dependency-free to maximize adoption.

### Constitution Amendments

- Amendments require documentation of rationale and migration plan
- Version follows semantic versioning:
  - **MAJOR**: Backward-incompatible principle removals/redefinitions
  - **MINOR**: New principles or materially expanded guidance
  - **PATCH**: Clarifications, wording fixes, non-semantic refinements
- All PRs MUST verify compliance with constitution principles
- Complexity violations MUST be explicitly justified in PR description

### References

- [Architecture Reference](../docs/nats_dart_architecture_reference.md)
- [NATS Protocol Spec](https://docs.nats.io/reference/reference-protocols/nats-protocol)
- [Dart Style Guide](https://dart.dev/guides/language/effective-dart)
- [Dart Testing Guide](https://dart.dev/guides/testing)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)

### Compliance

All development work MUST comply with this constitution. Violations require explicit justification and team approval before merging.

**Questions?** Refer to the [Architecture Reference](../docs/nats_dart_architecture_reference.md) or open a discussion.

**Something missing?** Update this document via amendment process.

---

**Version**: 1.0.0 | **Ratified**: 2026-02-23 | **Last Amended**: 2026-02-23
