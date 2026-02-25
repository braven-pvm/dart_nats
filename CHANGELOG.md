# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-23

### Added

#### Core Architecture
- Pure Dart implementation with no platform-specific code outside transport layer
- Clean architecture following SOLID principles
- Protocol layer (parser/encoder) is 100% platform-agnostic

#### Transport Layer
- `Transport` abstraction interface
- `TcpTransport`: dart:io implementation for native platforms (iOS, Android, macOS, Windows, Linux)
- `WebSocketTransport`: web_socket_channel implementation for Flutter Web
- `TransportFactory`: conditional import selector based on platform

#### Protocol Layer
- `NatsParser`: Stateful byte-buffer parser for wire protocol
  - Handles MSG and HMSG messages with headers and status codes
  - Supports INFO, PING, +OK, -ERR, PONG commands
  - Manages partial frames and multi-frame messages
  - Stream-based message emission for reactive processing
  
- `NatsEncoder`: Wire protocol encoder
  - PUB and HPUB commands with automatic header section computation
  - SUB with optional queue group and max messages
  - UNSUB for subscription removal
  - CONNECT with authentication parameters
  - PING/PONG for keep-alive
  
- `NUIDGenerator`: Unique ID generator for inbox subjects

#### Client Layer
- `NatsConnection`: High-level NATS client API
  - `connect()`: Establish connection with optional authentication
  - `publish()`: Fire-and-forget messaging with optional headers
  - `subscribe()`: Subscribe with wildcard support and queue groups
  - `unsubscribe()`: Clean subscription removal
  - `request()`: Synchronous request/reply with timeout
  - `drain()`: Graceful shutdown (wait for pending messages)
  - `close()`: Immediate connection termination
  - `status`: Stream of connection state changes
  - `isConnected`: Boolean state check
  
- `ConnectOptions`: Connection configuration
  - Reconnection settings (max attempts, exponential backoff)
  - PING/PONG keep-alive configuration
  - Authentication modes (token, user/pass, JWT, NKey)
  - Customization (client name, inbox prefix, noEcho)

#### Authentication
- Token-based authentication
- Username/password authentication
- JWT + NKey authentication with nonce signing

#### Reconnection & Resilience
- Automatic reconnection with exponential backoff
- Subscription replay after reconnection (re-subscribe to all active subs)
- PING/PONG keep-alive with timeout detection
- Max unanswered PINGs threshold

#### JetStream Foundation
- `JetStreamContext`: Entry point for JetStream operations
- `publish()`: Publish to JetStream streams with deduplication support
- `PubAck`: Publish acknowledgment with stream name, sequence, duplicate detection
- Stream and consumer management stubs (Phase 2)

#### KeyValue Store Foundation
- Bucket access API stubs (Phase 3)
- Operations: put, get, delete, watch, watchAll (Phase 3)

#### Platform Support
- Flutter Web: WebSocket transport
- Flutter iOS / Android / macOS / Windows / Linux: TCP transport
- Dart VM: Both TCP and WebSocket transports

#### Testing
- Unit tests for parser (11+ tests)
- Unit tests for encoder (43+ tests)
- Unit tests for connection (11+ tests)
- Unit tests for NUID generation
- Performance tests for parser and encoder
- 80%+ coverage target for protocol layer

#### Documentation
- Architecture reference document
- Quick start guide with examples
- API contracts (connection, JetStream, KeyValue)
- Data model and state machine diagrams
- Architecture decision records (ADRs)

### Technical Details

#### Protocol Compliance
- Implements [NATS Protocol Specification](https://docs.nats.io/reference/reference-protocols/nats-protocol)
- Supports headers (HMSG) with status codes
- Exact byte-count tracking for headers section

#### Code Quality
- `dart analyze` passes with no warnings
- `dart format` applied to all code
- SOLID principles enforced
- Comprehensive inline documentation

### Planned (Future Phases)

#### Phase 2: Full JetStream Implementation
- Stream management (create, delete, info, list)
- Consumer management (create durable/ephemeral consumers)
- Pull consumer (fetch batches, continuous consume)
- Ordered consumer (auto-recreate on sequence gaps)

#### Phase 3: KeyValue Store Implementation
- `put()`, `get()`, `delete()` operations
- `watch()` single key and `watchAll()` all keys
- `KvEntry` with revision tracking and operation type
- Bucket creation and configuration

#### Phase 4: Ecosystem
- Integration tests against Docker NATS server
- Example Flutter Web application
- Example Flutter native application  
- Publication to pub.dev
