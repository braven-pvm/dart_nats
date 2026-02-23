# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Project scaffold with core architecture
- Transport abstraction (TCP, WebSocket)
- Wire protocol parser (MSG, HMSG, INFO, PING, +OK, -ERR)
- Protocol encoder (PUB, HPUB, SUB, UNSUB, CONNECT, PING, PONG)
- NUID generator for unique IDs
- NATS connection with pub/sub and request/reply
- Basic authentication support (token, user/pass, JWT, NKey)
- JetStream context and API stubs
- KeyValue store API stubs
- Comprehensive architecture reference documentation

### Planned
- Phase 2: Full JetStream implementation (streams, consumers, pull fetch)
- Phase 3: KeyValue store implementation (put, get, delete, watch)
- Integration test suite vs real NATS server
- Example Flutter Web app
- Example Flutter native app
- Package publication to pub.dev

## [0.1.0] - 2026-02-23

### Initial Release
- Project structure and scaffolding
- Transport layer (TCP and WebSocket)
- Protocol parser and encoder
- Connection management
- Pub/sub and request/reply basics
