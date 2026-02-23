---
name: solid-architecture-review
description: Quick reference guide for reviewing SOLID principles in nats_dart. Use during code reviews, design discussions, and implementation.
applyTo:
  includes: ["lib/**/*.dart"]
---

# SOLID Architecture Review Guide

## Quick Check (2-Minute Review)

Run this checklist on any class or module before committing:

| Principle | Check | Example |
|-----------|-------|---------|
| **S** | Does this class have ONE reason to change? | `NatsParser` only parses; doesn't authenticate |
| **O** | Can I extend it WITHOUT modifying it? | New transport: implement `Transport`, don't modify |
| **L** | Can I swap implementations seamlessly? | `Transport t = TcpTransport()` and `t = WebSocketTransport()` both work |
| **I** | Does the client only depend on methods it uses? | `Subscription` doesn't force `reconnect()` |
| **D** | Does it depend on abstractions, not concretions? | `NatsConnection(Transport t)` not `NatsConnection() { tcp = new TcpTransport() }` |

---

## Detailed Checklist by Principle

### S — Single Responsibility

A class should have ONE reason to change.

#### Red Flags 🚩
```dart
// ❌ BAD: Three reasons to change
class NatsConnection {
  void authenticate() { }      // Reason 1: Auth changes
  void publish(msg) { }         // Reason 2: Pub/sub logic changes
  void parseBytes(data) { }     // Reason 3: Protocol parsing changes
}
```

#### ✅ GOOD: Single Responsibility
```dart
// ✅ GOOD: NatsConnection only handles lifecycle and coordination
class NatsConnection {
  final Transport _transport;
  final NatsParser _parser;
  
  NatsConnection(this._transport, this._parser);
  
  Future<void> publish(subject, data) async {
    // Use parser and transport, but doesn't directly implement either
  }
}

// ✅ GOOD: Separate classes for parsing
class NatsParser {
  Stream<NatsMessage> get messages => /* ... */;
  void addBytes(data) { /* ... */ }
}

// ✅ GOOD: Separate classes for protocol
class NatsEncoder {
  static Uint8List pub(subject, data) { /* ... */ }
  static Uint8List hpub(subject, data) { /* ... */ }
}

// ✅ GOOD: Separate classes for transport
abstract class Transport {
  Future<void> write(Uint8List data);
  Stream<Uint8List> get incoming;
}
```

#### Questions to Ask
- [ ] Can I describe this class's purpose in one sentence without using "and"?
- [ ] If the protocol changes, does this class need to change?
- [ ] If authentication changes, does this class need to change?
- [ ] If transport changes (TCP→WebSocket), does this class need to change?

---

### O — Open/Closed

Classes should be open for extension, closed for modification.

#### Red Flags 🚩
```dart
// ❌ BAD: Modify existing code to add new transport
abstract class Transport {
  if (isTcp) {
    // TCP implementation
  } else if (isWebSocket) {
    // WebSocket implementation
  }
}
```

#### ✅ GOOD: Extend, Don't Modify
```dart
// ✅ GOOD: Abstract base
abstract class Transport {
  Future<void> write(Uint8List data);
  Stream<Uint8List> get incoming;
}

// ✅ GOOD: Extend for TCP
class TcpTransport implements Transport {
  // TCP-specific code only
}

// ✅ GOOD: Extend for WebSocket
class WebSocketTransport implements Transport {
  // WebSocket-specific code only
}

// ✅ GOOD: Add new transport without touching existing code
class MqttTransport implements Transport {
  // MQTT implementation
  // No existing code modified!
}
```

#### Application to nats_dart
- Protocol parser (`NatsParser`) is closed to modification
- But open to extension: handle new message types without changing parser logic
- Transport abstraction is closed; new platform support = new `Transport` implementation

#### Questions to Ask
- [ ] If I add a new feature, do I modify existing classes or extend them?
- [ ] Can a new team member add a transport without understanding existing code?
- [ ] Are utility methods/constants factored out to avoid duplication?

---

### L — Liskov Substitution

Every implementation should be substitutable for its interface.

#### Red Flags 🚩
```dart
// ❌ BAD: Violates Liskov — breaks contract
class StubTransport implements Transport {
  @override
  Future<void> write(Uint8List data) {
    throw UnimplementedError("Stub doesn't write");  // Breaks contract!
  }
}

// Code that depends on Transport breaks:
Future<void> sendData(Transport t) async {
  await t.write(data);  // Crashes if t is StubTransport
}
```

#### ✅ GOOD: Honor the Contract
```dart
// ✅ GOOD: Stub honors interface contract
class MockTransport implements Transport {
  final messages = <Uint8List>[];
  
  @override
  Future<void> write(Uint8List data) async {
    messages.add(data);  // Always succeeds, honors contract
  }
  
  @override
  Stream<Uint8List> get incoming => Stream.empty();
}

// Code that depends on Transport always works:
Future<void> sendData(Transport t) async {
  await t.write(data);  // Always succeeds with any Transport
}
```

#### Questions to Ask
- [ ] Can I use `TcpTransport` everywhere the code expects `Transport`?
- [ ] Can I use `WebSocketTransport` in place of `TcpTransport` without errors?
- [ ] Does every implementation actually implement all required methods?
- [ ] Do I have any `throw UnimplementedError()` overrides? (Probably Liskov violation)

---

### I — Interface Segregation

Clients should NOT be forced to depend on methods they don't use.

#### Red Flags 🚩
```dart
// ❌ BAD: Subscription forced to have everything
abstract class Subscription {
  Stream<NatsMessage> get messages;
  Future<void> unsubscribe();
  Future<void> reconnect();       // Not all subscriptions need this!
  void setQueueGroup(String group); // Ephemeral subs can't change group
  int get maxMessages;            // Only for auto-unsub
}

// Client forced to implement all:
class EphemeralSubscription implements Subscription {
  Future<void> reconnect() => throw UnimplementedError();  // Don't need this
}
```

#### ✅ GOOD: Segregated Interfaces
```dart
// ✅ GOOD: Minimal interface that all implementations need
abstract class Subscription {
  String get subject;
  Stream<NatsMessage> get messages;
  Future<void> unsubscribe();
}

// ✅ GOOD: Separate interface for advanced features
abstract class DurableSubscription implements Subscription {
  Future<void> reconnect();
}

// ✅ GOOD: Ephemeral subscriptions only implement base
class EphemeralSubscription implements Subscription {
  // Simple implementation
}

// ✅ GOOD: Durable subscriptions implement both
class DurableSubscription extends EphemeralSubscription 
    implements DurableSubscription {
  Future<void> reconnect() async { /* ... */ }
}
```

#### Application to nats_dart
- `Subscription` provides what ALL subscribers need
- `PullConsumer` is NOT a `Subscription` (different interface)
- `JsMsg` provides `ack()`, `nak()`, `term()` (required for JetStream)

#### Questions to Ask
- [ ] Does every implementation actually use all interface methods?
- [ ] Would I throw `UnimplementedError()` for any method? (Violation!)
- [ ] Can I split this interface into smaller, focused ones?
- [ ] Are there methods that only SOME implementations use?

---

### D — Dependency Inversion

Depend on abstractions, not concretions.

#### Red Flags 🚩
```dart
// ❌ BAD: Depends on concrete implementation
class NatsConnection {
  final TcpTransport _transport = TcpTransport();  // Hard-wired!
  
  void publish(data) {
    _transport.write(data);  // Tightly coupled
  }
}

// Can't test without real TCP:
test('publish', () {
  final nc = NatsConnection();  // Must be real TCP!
  nc.publish(data);
});
```

#### ✅ GOOD: Depend on Abstractions
```dart
// ✅ GOOD: Depends on Transport abstraction
class NatsConnection {
  final Transport _transport;  // Injected, not created
  
  NatsConnection(this._transport);  // Dependency injection
  
  void publish(data) {
    _transport.write(data);  // Loosely coupled
  }
}

// Can test with mock:
test('publish', () {
  final mockTransport = MockTransport();  // Test double
  final nc = NatsConnection(mockTransport);
  nc.publish(data);
  expect(mockTransport.messages, contains(data));
});

// Can use real transport in production:
final nc = NatsConnection(TcpTransport('localhost', 4222));
```

#### Injection Patterns

**Constructor Injection** (Preferred)
```dart
class NatsConnection {
  final Transport transport;
  final NatsParser parser;
  
  NatsConnection(this.transport, this.parser);  // Clear dependencies
}
```

**Factory Injection**
```dart
class JetStreamContext {
  final NatsConnection _nc;
  
  JetStreamContext(this._nc);  // Depends on Connection abstraction
  
  Future<PubAck> publish(subject, data) {
    // Use _nc.publish(), which uses injected Transport/Parser
  }
}
```

#### Questions to Ask
- [ ] Are dependencies injected or hard-coded?
- [ ] Can I run unit tests without a real server?
- [ ] Can I swap implementations (e.g., TcpTransport → WebSocketTransport)?
- [ ] Are there any `new TcpTransport()` or `new NatsParser()` calls outside factories?

---

## SOLID Violation Scorecard

Use this to evaluate code quality:

| Score | Status | Action |
|-------|--------|--------|
| 0 violations | ✅ **Excellent** | Ready to merge |
| 1-2 violations | ⚠️ **Fair** | Request changes; acceptable if documented |
| 3+ violations | 🚩 **Poor** | Reject; requires refactoring |

### Examples by Score

**✅ Score 0** (Excellent)
- Each class has one reason to change
- New features extend existing code, don't modify it
- All implementations satisfy their contracts
- Interfaces only include what clients use
- Tests inject mock dependencies

**⚠️ Score 1-2** (Fair)
- Parser combines parsing + state management (minor overlap OK)
- Transport has helper methods used by some not all implementations
- One method throws UnimplementedError but rarely called

**🚩 Score 3+** (Poor)
- Class does auth, parsing, AND connection management
- Adding new messages requires modifying parser
- Stub Transport throws UnimplementedError on key methods
- Subscription interface forces unused methods
- Everything depends on concrete TcpTransport

---

## During Code Review

Use these discussion starters:

### S (Single Responsibility)
> "This class changes when X _and_ when Y — should we split it?"

### O (Open/Closed)
> "Adding [feature] requires modifying existing code; can we extend instead?"

### L (Liskov)
> "Can a mock implementation honor this interface contract?"

### I (Interface Segregation)
> "Does every implementation actually use all methods?"

### D (Dependency Inversion)
> "Can we inject this dependency instead of creating it?"

---

## Architecture Patterns in nats_dart

### Transport (Dependency Inversion)
```dart
NatsConnection._connect() {
  _transport = transport_factory.createTransport(_uri);  // Abstraction
  await _transport.write(connectCmd);
}
```

### Parser (Single Responsibility)
```dart
class NatsParser {
  // Only parses wire protocol
  // Just addBytes() and messages stream
  // Doesn't do I/O, auth, or connection logic
}
```

### JetStream (Open/Closed for Extensions)
```dart
class JetStreamContext {
  // Core interface fixed
  Future<PubAck> publish(subject, data);
  
  // Extend with managers for specific operations
  StreamManager get streams;
  ConsumerManager get consumers;
}
```

### Message Models (Interface Segregation)
```dart
// Base interface — all messages have this
class NatsMessage {
  String? subject;
  Uint8List? payload;
}

// Extended for JetStream — only JS messages have this
class JsMsg extends NatsMessage {
  JsMsgInfo info;
  Future<void> ack();
}
```

---

## Summary

| Principle | In One Sentence | nats_dart Example |
|-----------|-----------------|------------------|
| **S** | One reason to change | `NatsParser` only parses |
| **O** | Extend, don't modify | `Transport` abstraction for new platforms |
| **L** | Swap implementations | `TcpTransport` ↔ `WebSocketTransport` |
| **I** | Don't force unused methods | `Subscription` ≠ `PullConsumer` |
| **D** | Depend on abstractions | `NatsConnection(Transport t)` |

---

## See Also

- `.github/copilot-instructions.md` — Project constitution
- `.github/agents/tdd-developer.agent.md` — Test-Driven Development guide
- `docs/nats_dart_architecture_reference.md` — Full architecture reference
