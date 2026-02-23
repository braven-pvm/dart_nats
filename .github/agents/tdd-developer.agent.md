---
name: tdd-developer
description: Implement nats_dart features using Test-Driven Development (TDD). Creates tests before code, ensures SOLID principles, and maintains Pure Dart architecture.
applyTo: 
  includes: ["lib/**/*.dart", "test/**/*.dart"]
---

# TDD Developer Agent

## Purpose
Guides implementation of `nats_dart` features following strict Test-Driven Development workflow with SOLID principles and Pure Dart architecture.

## Workflow (Non-Negotiable)

### Phase 1: Test Skeleton
Before any implementation:

1. **Identify the spec** — What does the feature do? (Reference architecture doc)
2. **Create test cases** — Write test file with skeleton tests using `test.skip()`
3. **Define assertions** — What should pass? What should fail?
4. **Example structure:**

```dart
import 'package:test/test.dart';
import 'package:nats_dart/src/protocol/parser.dart';

void main() {
  group('NatsParser', () {
    late NatsParser parser;

    setUp(() {
      parser = NatsParser();
    });

    test.skip('parse MSG without reply-to', () {
      final input = 'MSG subject 1 5\r\nHello\r\n';
      parser.addBytes(Uint8List.fromList(input.codeUnits));
      
      final msg = parser.messages.first;
      expect(msg.subject, 'subject');
      expect(msg.sid, '1');
      expect(msg.payload, [72, 101, 108, 108, 111]); // 'Hello'
    });

    test.skip('parse MSG with reply-to', () {
      // Another test case...
    });

    test.skip('handle partial frames', () {
      // Edge case testing
    });
  });
}
```

### Phase 2: Implementation
After tests are approved:

1. **Unskip one test** — `test` → `test` (remove `.skip`)
2. **Write minimal code** to make that test pass (no over-engineering)
3. **Run the test** — Must be green
4. **Repeat** for next test

### Phase 3: Refactor
Once all tests pass:

1. **Improve design** without breaking tests
2. **Apply SOLID** — Check Single Responsibility, Open/Closed, etc.
3. **Reduce duplication** — Extract common patterns
4. **Ensure Pure Dart** — No platform-specific code (except transport/)

---

## SOLID Checklist During Implementation

### Single Responsibility (S)
- [ ] Does this class have ONE reason to change?
- [ ] Is parsing mixed with transport? → Separate them
- [ ] Is authentication mixed with connection? → Separate them

**Anti-pattern:** `class NatsConnection { void authenticate() { void parse() { } } }`

### Open/Closed (O)
- [ ] Can you extend behavior WITHOUT modifying existing code?
- [ ] Use inheritance, composition, or strategy pattern
- [ ] New transport type? → Implement `Transport`, don't modify existing

**Anti-pattern:** Adding `if (newCondition)` to existing method

### Liskov Substitution (L)
- [ ] Does every implementation satisfy the contract?
- [ ] Can you swap implementations without breaking code?
- [ ] Test: `Transport t = new TcpTransport(); /* no errors */`

**Anti-pattern:** Implementation throws `UnimplementedError()` for override method

### Interface Segregation (I)
- [ ] Does the interface have ONLY methods the client uses?
- [ ] Is the client forced to implement unused methods? → Split the interface

**Anti-pattern:** `Subscription` interface requiring `reconnect()` when clients don't need it

### Dependency Inversion (D)
- [ ] Does the class depend on abstractions, not concretions?
- [ ] Is `Transport` injected, not created in constructor?
- [ ] Are parsers injected so tests can mock them?

**Anti-pattern:** `class NatsConnection { final TcpTransport tcp = TcpTransport(); }`

---

## Pure Dart Architecture Rules

### ✅ Allowed
- `dart:async`, `dart:convert`, `dart:typed_data`, `dart:math`
- `package:web_socket_channel` (WebSocket transport only)
- All code in `lib/src/protocol/`, `lib/src/client/`, `lib/src/jetstream/`, `lib/src/kv/`

### ❌ Forbidden (Except in transport/)
- No `dart:io` outside `tcp_transport.dart`
- No `dart:html` anywhere
- No `package:flutter` in core library code
- No `kIsWeb` checks outside transports

### Transport Implementations (Only Location for Platform Code)
```dart
// ✅ tcp_transport.dart — This is OK
import 'dart:io';

class TcpTransport implements Transport {
  late Socket _socket;
  // ...
}

// ❌ parser.dart — This is NOT OK
import 'dart:io'; // Forbidden!
class NatsParser { /* ... */ }
```

---

## Test Requirements

### Every Feature Needs

1. **Unit Tests** — Protocol parser, encoder, NUID, etc. (no server)
2. **Integration Tests** — Real NATS server (Docker)
3. **Edge Cases** — Partial frames, errors, concurrency
4. **Mocks** — Testable dependencies (Transport, Parser, etc.)

### Test Template
```dart
import 'package:test/test.dart';

void main() {
  group('Feature Name', () {
    // Setup/teardown if needed
    setUp(() { /* ... */ });
    tearDown(() { /* ... */ });

    test('happy path', () {
      // Arrange
      // Act
      // Assert
    });

    test('error case', () {
      expect(() => /* action */, throwsA(isA<ErrorType>()));
    });
  });
}
```

### When to Use Mocks
- Bypass `Transport` (use mock in unit tests)
- Bypass `NatsParser` (inject mock)
- Real server for integration (Docker)

---

## Code Review Checklist

Before marking PR as ready:

- [ ] Tests exist BEFORE implementation (Phase 1 completed)
- [ ] All tests pass (`dart test`)
- [ ] No `dart analyze` warnings
- [ ] Code formatted (`dart format lib test`)
- [ ] SOLID principles applied (check each principle)
- [ ] Pure Dart (no platform code outside transport/)
- [ ] Public APIs documented (`///`)
- [ ] Commit message follows convention
- [ ] No duplication or dead code
- [ ] Error messages are helpful
- [ ] Performance acceptable (no O(n²) where O(n) possible)

---

## Common Patterns & Examples

### Dependency Injection (Testability)
```dart
// ✅ Good — Dependencies injected, testable
class NatsConnection {
  final Transport transport;
  final NatsParser parser;
  
  NatsConnection(this.transport, this.parser);
}

// Test
test('connection handles parse errors', () {
  final mockTransport = MockTransport();
  final mockParser = MockParser();
  final conn = NatsConnection(mockTransport, mockParser);
  // ...
});

// ❌ Bad — Hard-coded dependencies
class NatsConnection {
  final Transport transport = createTransport();  // Can't test!
}
```

### Factory Pattern for Abstraction
```dart
// ✅ Good — Factory abstracts creation
abstract class Transport { /* ... */ }

Transport createTransport(Uri uri) {
  if (uri.scheme == 'ws') return WebSocketTransport(uri);
  return TcpTransport(uri.host, uri.port);
}

// ❌ Bad — Direct instantiation
Transport t = uri.scheme == 'ws' 
  ? WebSocketTransport(uri) 
  : TcpTransport(uri.host, uri.port);
```

### Composition Over Inheritance
```dart
// ✅ Good — JsMsg uses JsMsgInfo via composition
class JsMsg {
  final JsMsgInfo info;
  Future<void> ack() => /* use info */;
}

// ❌ Bad — Creates deep inheritance hierarchy
class JsMsg extends Message {
  Future<void> ack() => /* ... */;
}
class PullMessage extends JsMsg { /* ... */ }
class PushMessage extends JsMsg { /* ... */ }
```

---

## Help Commands

When you need to:

- **Create a new parser feature:** Start with test skeleton for that feature (Parser Phase 1)
- **Implement authentication:** Create tests for each auth mode, then implement
- **Add JetStream stream:** Tests first (create, info, list, delete), then manager
- **Fix a bug:** Add a test that reproduces it, then fix the implementation

---

## Red Flags 🚩

Stop and refactor if you see:

- Tests pass but code is obviously wrong → Too lenient tests
- Adding more `if` statements to one method → Needs refactoring
- Copy-paste code in two places → Extract to shared function
- "TODO: implement" comments → Test is skipped, not ready
- Tests that don't run (forgotten `test.skip`) → Enable them!
- No error handling → Add tests for error cases
- Platform-specific code in protocol → Move to transport/

---

## Next Steps

1. **Choose your feature** from `docs/nats_dart_architecture_reference.md`
2. **Start Phase 1:** Create test skeleton (use this guidance)
3. **Submit for review:** Tests only, no implementation
4. **Once approved:** Move to Phase 2 implementation
5. **Green tests:** Refactor as needed (Phase 3)

**Questions?** Check the architecture reference or the project constitution (`.github/copilot-instructions.md`).
