# nats_dart — Architecture & Implementation Reference

*A Native Dart/Flutter NATS Client with Full JetStream Support*

| | |
|---|---|
| **Project** | Braven Lab Studio |
| **Package** | nats_dart |
| **Date** | February 2026 |
| **Doc Type** | Architecture Reference |

> **About This Document**
> This document is the primary technical reference for implementing `nats_dart` — a new, first-class Dart/Flutter NATS client with complete JetStream support. It consolidates protocol specifications, architectural decisions, implementation patterns, API designs, and testing strategy needed to build the package from scratch. Reference this document continuously throughout development and update it as the implementation evolves.

---

## Table of Contents

1. [NATS Wire Protocol Reference](#1-nats-wire-protocol-reference)
2. [JetStream Protocol Reference](#2-jetstream-protocol-reference)
3. [Package Architecture](#3-package-architecture)
4. [Protocol Parser](#4-protocol-parser)
5. [JetStream & KV Implementation](#5-jetstream--kv-implementation)
6. [NUID Generator](#6-nuid-generator)
7. [Authentication & Reconnection](#7-authentication--reconnection)
8. [Server Configuration](#8-server-configuration)
9. [Build Plan & Test Strategy](#9-build-plan--test-strategy)
10. [Reference Sources](#10-reference-sources)

---

## 1 · NATS Wire Protocol Reference

NATS uses a simple, text-based publish/subscribe protocol transmitted byte-for-byte identically over both TCP and WebSocket. This means **100% of parser and JetStream logic can be written once and shared across all Flutter platforms** — only the transport layer differs.

> **Critical Insight:** The wire protocol is byte-for-byte identical over TCP and WebSocket. The entire parser and all JetStream logic is written once, shared across platforms. Only the Transport interface implementation differs: native uses TCP (`dart:io`), Flutter Web uses WebSocket (`web_socket_channel`). This is the architectural foundation of `nats_dart`.

### 1.1 Protocol Command Summary

| Direction | Command | Syntax | Purpose |
|-----------|---------|--------|---------|
| S→C | `INFO` | `INFO {...json...}` | Server capabilities, auth config, JetStream availability |
| C→S | `CONNECT` | `CONNECT {...json...}` | Client auth, headers capability flag, protocol version |
| C→S | `PUB` | `PUB <subj> [reply] <bytes>\r\n[payload]\r\n` | Publish message — **NO headers** (cannot reach JetStream) |
| C→S | `HPUB` | `HPUB <subj> [reply] <hdr> <total>\r\n[hdrs]\r\n\r\n[payload]\r\n` | Publish **WITH headers** — **REQUIRED for JetStream** |
| C→S | `SUB` | `SUB <subj> [queue] <sid>` | Subscribe to subject, optional queue group |
| C→S | `UNSUB` | `UNSUB <sid> [max_msgs]` | Unsubscribe; optional auto-unsub after N messages |
| S→C | `MSG` | `MSG <subj> <sid> [reply] <bytes>\r\n[payload]\r\n` | Deliver message to subscriber (no headers) |
| S→C | `HMSG` | `HMSG <subj> <sid> [reply] <hdr> <total>\r\n[hdrs]\r\n\r\n[payload]\r\n` | Deliver **WITH headers** — ALL JetStream responses use this |
| Both | `PING/PONG` | `PING\r\n / PONG\r\n` | Keep-alive heartbeat (server initiates) |
| S→C | `+OK/-ERR` | `+OK\r\n / -ERR <msg>\r\n` | Protocol acknowledgement or connection error |

### 1.2 INFO — Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `server_id` | string | Unique server identifier |
| `version` | string | NATS server version |
| `headers` | bool | Server supports HPUB/HMSG — **MUST be true** for JetStream use |
| `jetstream` | bool | JetStream is enabled on this server |
| `max_payload` | int | Maximum payload size in bytes |
| `auth_required` | bool | Client must authenticate in CONNECT |
| `tls_required` | bool | Client must perform TLS handshake |
| `nonce` | string | Challenge nonce for NKey/JWT authentication |
| `connect_urls` | []string | Cluster server URLs for connection failover |
| `ws_connect_urls` | []string | WebSocket cluster URLs for WS client failover |

### 1.3 CONNECT — Key Fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `verbose` | bool | Yes | Set `false` — disables +OK per-message (required for perf) |
| `pedantic` | bool | Yes | Set `false` in production |
| `headers` | bool | No | **MUST be `true`** — enables HPUB/HMSG and JetStream |
| `no_responders` | bool | No | Set `true` — fast 404 when no subscribers exist |
| `lang` | string | Yes | e.g. `'dart'` |
| `version` | string | Yes | Package version string |
| `jwt` | string | Conditional | JWT for decentralised auth |
| `nkey` | string | Conditional | Public NKey for challenge auth |
| `sig` | string | Conditional | Signed nonce (when server sent nonce in INFO) |
| `auth_token` | string | Conditional | Static token auth |
| `user` / `pass` | string | Conditional | Username / password auth |

### 1.4 HPUB — Publishing with Headers

HPUB is the **only** publish command that can reach JetStream. PUB without headers is silently accepted but will **NOT** be persisted in any JetStream stream.

**Syntax:**

```
HPUB <subject> [reply-to] <#header bytes> <#total bytes>\r\n
NATS/1.0\r\n
[Header-Name: Header-Value\r\n]
...additional headers...
\r\n
[payload]\r\n
```

**Byte Count Rules:**
- `#header bytes`: byte length of header section **INCLUDING** the trailing empty line (`\r\n\r\n`)
- `#total bytes`: `#header bytes` + payload byte length
- Header section **MUST** start with `NATS/1.0\r\n`
- Header section **MUST** end with `\r\n\r\n` (blank line)

**HPUB Examples:**

```
# Publish to JetStream stream with deduplication header:
HPUB TESTS.session_1 _INBOX.abc123 52 74\r\n
NATS/1.0\r\n
Nats-Msg-Id: session-42-001\r\n
\r\n
{"power":285,"hr":148}\r\n

# Header-only publish (no payload):
HPUB NOTIFY 22 22\r\n
NATS/1.0\r\n
Bar: Baz\r\n
\r\n
\r\n

# Multi-value header:
HPUB MORNING.MENU 47 51\r\n
NATS/1.0\r\n
BREAKFAST: donut\r\n
BREAKFAST: eggs\r\n
\r\n
Yum!\r\n
```

### 1.5 HMSG — Receiving Messages with Headers

HMSG is the server-to-client delivery for messages that carry NATS headers. **ALL JetStream messages arrive as HMSG** — flow control, consumer ack subjects, KV entries, status responses.

**Syntax:**

```
HMSG <subject> <sid> [reply-to] <#header bytes> <#total bytes>\r\n
NATS/1.0[SP status-code description]\r\n
[Header-Name: Header-Value\r\n]
\r\n
[payload]\r\n
```

**HMSG Status Codes:**

| Status Line | Meaning | Required Client Action |
|-------------|---------|----------------------|
| `NATS/1.0` | Normal message delivery | Process payload normally |
| `NATS/1.0 100 FlowControl Request` | Server requesting flow control | Publish empty message to `msg.replyTo` immediately |
| `NATS/1.0 100 Idle Heartbeat` | Heartbeat from ordered/push consumer | Verify sequence continuity; no reply needed |
| `NATS/1.0 404 No Messages` | Pull consumer: no more messages | End batch loop; issue new fetch later |
| `NATS/1.0 408 Request Timeout` | Pull request expired server-side | Issue new fetch request |
| `NATS/1.0 409 Message Size Exceeds MaxBytes` | Batch byte cap reached | Reduce `maxBytes` in next fetch |
| `NATS/1.0 409 Consumer Deleted` | Consumer removed externally | Recreate consumer |

**HMSG Examples:**

```
# JetStream message with ack subject in reply-to:
HMSG TESTS.session_1 1 $JS.ACK.TESTS.consumer.1.42.42.1700000000.0 34 56\r\n
NATS/1.0\r\n
\r\n
{"power":285,"hr":148}\r\n

# Flow control (MUST reply with empty publish to replyTo):
HMSG _INBOX.abc 1 $JS.FC.TESTS.consumer.1 23 23\r\n
NATS/1.0 100 FlowControl Request\r\n
\r\n
\r\n

# Pull consumer: no messages (404):
HMSG _INBOX.xyz 1 12 12\r\n
NATS/1.0 404\r\n
\r\n
\r\n
```

### 1.6 Subject Naming Conventions

| Pattern | Examples | Description |
|---------|---------|-------------|
| Wildcard `*` | `TESTS.*` | Single token wildcard |
| Wildcard `>` | `TESTS.>` | Multi-token wildcard (end of subject only) |
| `_INBOX.*` | `_INBOX.abc123` | Private reply-to inboxes |
| `$JS.API.*` | `$JS.API.STREAM.CREATE.X` | JetStream management API |
| `$JS.ACK.*` | `$JS.ACK.STREAM.CONSUMER.*` | JetStream message ack subjects |
| `$JS.FC.*` | `$JS.FC.STREAM.CONSUMER.1` | Flow control reply subjects |
| `$KV.*` | `$KV.bucket.key` | Key-Value store subjects |
| `KV_*` | `KV_BravenSession` | Underlying JetStream stream for KV bucket |

---

## 2 · JetStream Protocol Reference

JetStream has **no separate wire protocol**. It is implemented as JSON request/reply on `$JS.API.*` subjects using core NATS pub/sub. Any client with correct HPUB/HMSG support can reach JetStream by layering these API calls on top.

### 2.1 JetStream API Subjects

**General Info:**

| Subject | Description | Request Payload |
|---------|-------------|----------------|
| `$JS.API.INFO` | Account JetStream limits and stats | empty |

**Stream Management:**

| Subject | Description |
|---------|-------------|
| `$JS.API.STREAM.CREATE.<name>` | Create or update a stream (idempotent) |
| `$JS.API.STREAM.UPDATE.<name>` | Update stream config |
| `$JS.API.STREAM.INFO.<name>` | Get stream config and state |
| `$JS.API.STREAM.LIST` | Paged list of all streams |
| `$JS.API.STREAM.NAMES` | Paged list of stream names only |
| `$JS.API.STREAM.DELETE.<name>` | Delete stream and all messages |
| `$JS.API.STREAM.PURGE.<name>` | Purge all messages, keep stream |
| `$JS.API.STREAM.MSG.GET.<name>` | Fetch specific message by sequence |
| `$JS.API.STREAM.MSG.DELETE.<name>` | Delete specific message by sequence |

**Consumer Management:**

| Subject | Description |
|---------|-------------|
| `$JS.API.CONSUMER.CREATE.<stream>` | Create ephemeral consumer (no filter or multi-filter) |
| `$JS.API.CONSUMER.CREATE.<stream>.<name>.<filter>` | Create consumer with single filter subject (server 2.9+) |
| `$JS.API.CONSUMER.DURABLE.CREATE.<stream>.<name>` | Create named durable consumer (legacy API) |
| `$JS.API.CONSUMER.INFO.<stream>.<name>` | Get consumer config and state |
| `$JS.API.CONSUMER.LIST.<stream>` | Paged list of consumers for stream |
| `$JS.API.CONSUMER.NAMES.<stream>` | Paged list of consumer names |
| `$JS.API.CONSUMER.DELETE.<stream>.<name>` | Delete named consumer |

**Pull Consumer Fetch:**

| Subject | Description |
|---------|-------------|
| `$JS.API.CONSUMER.MSG.NEXT.<stream>.<consumer>` | Fetch batch of messages from pull consumer |

**Acks and Flow Control:**

| Subject | Description |
|---------|-------------|
| `$JS.ACK.<stream>.<consumer>.<meta>` | Acknowledge a message (subject embedded in HMSG reply-to) |
| `$JS.FC.<stream>.<consumer>.<id>` | Reply to flow control request (empty publish) |

**Key-Value Store:**

| Subject | Description |
|---------|-------------|
| `$KV.<bucket>.<key>` | Publish value to KV bucket |
| `$JS.API.DIRECT.GET.KV-<bucket>.<key>` | Direct get of KV entry (lower latency) |
| `KV_<bucket>` (stream name) | Underlying JetStream stream for KV bucket |

### 2.2 StreamConfig (Key Fields)

```json
{
  "name": "TESTS",
  "subjects": ["TESTS.>"],
  "storage": "file",
  "retention": "limits",
  "max_consumers": -1,
  "max_msgs": -1,
  "max_bytes": -1,
  "max_age": 0,
  "num_replicas": 1,
  "discard": "old",
  "duplicate_window": 120000000000
}
```

| Field | Values | Notes |
|-------|--------|-------|
| `storage` | `"file"` / `"memory"` | |
| `retention` | `"limits"` / `"interest"` / `"workqueue"` | |
| `discard` | `"old"` / `"new"` | old = drop oldest; new = reject new |
| `max_age` | nanoseconds | 0 = never expire |
| `duplicate_window` | nanoseconds | 2min = 120000000000 |

### 2.3 ConsumerConfig (Key Fields for Pull Consumer)

```json
{
  "durable_name": "braven-processor",
  "deliver_policy": "all",
  "ack_policy": "explicit",
  "ack_wait": 30000000000,
  "max_deliver": 5,
  "filter_subject": "TESTS.session_1",
  "replay_policy": "instant",
  "max_ack_pending": 1000,
  "inactive_threshold": 5000000000
}
```

| Field | Values | Notes |
|-------|--------|-------|
| `deliver_policy` | `"all"` / `"new"` / `"last"` / `"by_start_sequence"` | |
| `ack_policy` | `"explicit"` recommended for pull | |
| `ack_wait` | nanoseconds | 30s = 30000000000 |
| `inactive_threshold` | nanoseconds | Auto-delete ephemeral after 5s |

### 2.4 Pull Fetch Request

Publish to `$JS.API.CONSUMER.MSG.NEXT.<stream>.<consumer>` with client inbox as reply-to:

```json
{
  "batch": 50,
  "max_bytes": 1048576,
  "expires": 5000000000,
  "no_wait": false
}
```

### 2.5 Ack Subjects & Ack Types

Every JetStream HMSG has an ack subject in its reply-to field:

```
$JS.ACK.<stream>.<consumer>.<num_delivered>.<stream_seq>.<consumer_seq>.<timestamp>.<pending>
```

| Publish Payload | Ack Type | Semantics |
|----------------|----------|-----------|
| `+ACK` or empty | Ack | Processed — do not redeliver |
| `-NAK` | Nak | Not processed — redeliver after `ack_wait` |
| `-NAK {"delay":5000000000}` | Nak with delay | Redeliver after 5 seconds |
| `+WPI` | In Progress | Still working — reset ack timer |
| `+TERM` | Terminate | Permanently discard — never redeliver |

### 2.6 JetStream Publish Flow

```
// 1. Client sends HPUB with unique inbox as reply-to:
HPUB TESTS.session_1 _INBOX.nuid123 52 74\r\n
NATS/1.0\r\n
Nats-Msg-Id: session-1-001\r\n
\r\n
{"power":285,"hr":148,"ts":1706000000}\r\n

// 2. Server responds to inbox with PubAck JSON:
{
  "stream": "TESTS",
  "seq": 42,
  "duplicate": false
}
```

> **Deduplication via Nats-Msg-Id:** If the same `Nats-Msg-Id` is published again within the stream's `duplicate_window`, the server stores it only once and returns `{"duplicate": true}` in the PubAck. Use `sessionId + incrementing sequence` as the message ID for at-least-once delivery with built-in dedup.

---

## 3 · Package Architecture

### 3.1 Directory Structure

```
nats_dart/
├── lib/
│   ├── nats_dart.dart              # Public API barrel export
│   └── src/
│       ├── transport/
│       │   ├── transport.dart              # Abstract Transport interface
│       │   ├── transport_factory.dart      # Conditional import selector
│       │   ├── transport_factory_stub.dart # Non-platform stub
│       │   ├── transport_factory_io.dart   # dart:io — TCP + optional WS (native)
│       │   ├── transport_factory_web.dart  # WS only (Flutter Web / browser)
│       │   ├── tcp_transport.dart          # dart:io Socket implementation
│       │   └── websocket_transport.dart    # web_socket_channel implementation
│       ├── protocol/
│       │   ├── parser.dart         # Stateful byte-buffer parser (MSG+HMSG)
│       │   ├── encoder.dart        # HPUB/PUB/SUB/CONNECT encoder
│       │   ├── message.dart        # NatsMessage + headers Map model
│       │   └── nuid.dart           # NATS Unique ID generator (base62)
│       ├── client/
│       │   ├── connection.dart     # NatsConnection — top-level API
│       │   ├── subscription.dart   # Subscription<NatsMessage> stream
│       │   └── options.dart        # ConnectOptions + auth config
│       ├── jetstream/
│       │   ├── jetstream.dart      # JetStreamContext entry point
│       │   ├── stream_manager.dart # Stream CRUD
│       │   ├── consumer_manager.dart # Consumer CRUD
│       │   ├── producer.dart       # jsPublish() → PubAck
│       │   ├── pull_consumer.dart  # fetch() + consume() stream
│       │   ├── ordered_consumer.dart # Auto-recreate on sequence gap
│       │   └── js_msg.dart         # JsMsg: ack/nak/term/inProgress
│       └── kv/
│           ├── kv.dart             # KeyValue API
│           └── kv_entry.dart       # KvEntry model
├── test/
│   ├── unit/                       # Parser + encoder unit tests
│   └── integration/                # Tests against real NATS server
├── example/
│   ├── flutter_web/                # Flutter Web example
│   └── flutter_native/             # Flutter native example
└── pubspec.yaml
```

### 3.2 Transport Abstraction — Conditional Imports

Use **compile-time conditional imports** — NOT runtime `kIsWeb` checks. This produces smaller builds where platform-specific code is entirely excluded at compile time.

> **Transparent to Caller:** The caller never thinks about transports. On Flutter Web, passing `nats://` is silently converted to `ws://`. On native, TCP is used for maximum performance. Same application code runs on all platforms.

```dart
// transport_factory.dart — the selector
export 'transport_factory_stub.dart'
    if (dart.library.io) 'transport_factory_io.dart'
    if (dart.library.html) 'transport_factory_web.dart';

// transport_factory_io.dart — native: TCP default, WebSocket optional
Transport createTransport(Uri uri) {
  if (uri.scheme == 'ws' || uri.scheme == 'wss') return WebSocketTransport(uri);
  return TcpTransport(uri.host, uri.port);
}

// transport_factory_web.dart — browser: WebSocket only, coerce scheme
Transport createTransport(Uri uri) {
  final wsUri = uri.replace(
    scheme: uri.scheme == 'tls' ? 'wss'
           : uri.scheme == 'nats' ? 'ws'
           : uri.scheme,
  );
  return WebSocketTransport(wsUri);
}
```

### 3.3 Abstract Transport Interface

```dart
abstract class Transport {
  Stream<Uint8List> get incoming;   // Byte stream from server
  Future<void> write(Uint8List data); // Send bytes to server
  Future<void> close();
  bool get isConnected;
  Stream<Object> get errors;         // Unexpected disconnection events
}
```

### 3.4 NatsConnection Public API

```dart
class NatsConnection {
  static Future<NatsConnection> connect(String url, {ConnectOptions? options});

  // Core pub/sub
  Future<void> publish(String subject, Uint8List data,
      {String? replyTo, Map<String, String>? headers});
  Future<NatsMessage> request(String subject, Uint8List data,
      {Duration timeout = const Duration(seconds: 10)});
  Subscription subscribe(String subject, {String? queueGroup});
  Future<void> unsubscribe(Subscription sub);

  // Lifecycle
  Stream<ConnectionStatus> get status;
  Future<void> drain();
  Future<void> close();

  // JetStream access
  JetStreamContext jetStream({String? domain,
      Duration timeout = const Duration(seconds: 5)});
}
```

### 3.5 ConnectOptions

```dart
class ConnectOptions {
  final String? name;                   // Client name (visible in monitoring)
  final int maxReconnectAttempts;       // -1 = infinite
  final Duration reconnectDelay;        // Default: 2 seconds
  final Duration pingInterval;          // Default: 2 minutes
  final int maxPingOut;                 // Default: 2
  final bool noEcho;                    // Don't receive own publishes
  final String inboxPrefix;             // Default: '_INBOX'

  // Auth — set exactly one:
  final String? authToken;
  final String? user;
  final String? pass;
  final String? jwt;
  final String? nkeyPath;              // Path to .nk seed file
}
```

---

## 4 · Protocol Parser

The parser is the most critical component. It must be stateful (messages span multiple frames), handle MSG and HMSG, and correctly parse header status codes.

### 4.1 Parser State Machine

```dart
class NatsParser {
  final _buffer = BytesBuilder(copy: false);
  final _controller = StreamController<NatsMessage>.broadcast();
  Stream<NatsMessage> get messages => _controller.stream;

  void addBytes(Uint8List data) {
    _buffer.add(data);
    _tryParse();
  }

  void _tryParse() {
    while (true) {
      final bytes = _buffer.toBytes();
      final crlfIdx = _findCRLF(bytes);
      if (crlfIdx == -1) return; // incomplete — wait

      final controlLine = utf8.decode(bytes.sublist(0, crlfIdx));
      final op = controlLine.split(' ')[0].toUpperCase();

      switch (op) {
        case 'MSG':  _parseMsgOrHmsg(controlLine, bytes, false); break;
        case 'HMSG': _parseMsgOrHmsg(controlLine, bytes, true); break;
        case 'INFO': _emitInfo(controlLine); _advance(crlfIdx + 2); break;
        case 'PING': _emit(NatsMessage.ping()); _advance(crlfIdx + 2); break;
        case '+OK':  _emit(NatsMessage.ok()); _advance(crlfIdx + 2); break;
        case '-ERR': _emitErr(controlLine); _advance(crlfIdx + 2); break;
        default:     _advance(crlfIdx + 2); // Unknown op — skip
      }
    }
  }
}
```

### 4.2 MSG / HMSG Parsing

```dart
// MSG format:  MSG  subject sid [reply] #bytes
// HMSG format: HMSG subject sid [reply] #hdrBytes #totalBytes

void _parseMsgOrHmsg(String line, Uint8List buf, bool hasHeaders) {
  final parts = line.split(' ');
  String subject, sid;
  String? replyTo;
  int hdrBytes = 0, totalBytes;

  subject = parts[1]; sid = parts[2];
  if (hasHeaders) {
    if (parts.length == 6) { replyTo=parts[3]; hdrBytes=int.parse(parts[4]); totalBytes=int.parse(parts[5]); }
    else                   { hdrBytes=int.parse(parts[3]); totalBytes=int.parse(parts[4]); }
  } else {
    if (parts.length == 5) { replyTo=parts[3]; totalBytes=int.parse(parts[4]); }
    else                   { totalBytes=int.parse(parts[3]); }
  }

  final ctrlLen = line.length + 2; // +2 for \r\n
  final requiredLen = ctrlLen + totalBytes + 2; // +2 for trailing \r\n
  if (buf.length < requiredLen) return; // wait for more bytes

  Map<String, List<String>>? headers;
  int? statusCode; String? statusDesc;
  Uint8List payload;

  if (hasHeaders) {
    final hdrSection = buf.sublist(ctrlLen, ctrlLen + hdrBytes);
    final parsed = _parseHeaderSection(hdrSection);
    headers = parsed.headers;
    statusCode = parsed.statusCode;
    statusDesc = parsed.description;
    payload = buf.sublist(ctrlLen + hdrBytes, ctrlLen + totalBytes);
  } else {
    payload = buf.sublist(ctrlLen, ctrlLen + totalBytes);
  }

  _emit(NatsMessage(subject:subject, sid:sid, replyTo:replyTo,
      payload:payload, headers:headers, statusCode:statusCode, statusDesc:statusDesc));
  _advance(requiredLen);
}
```

### 4.3 Header Section Parser

```dart
({int? statusCode, String? description, Map<String, List<String>> headers})
_parseHeaderSection(Uint8List headerBytes) {
  final text = utf8.decode(headerBytes);
  final lines = text.split('\r\n');

  // First line: 'NATS/1.0' or 'NATS/1.0 100 FlowControl Request'
  int? statusCode; String? description;
  if (lines[0].startsWith('NATS/1.0')) {
    final rest = lines[0].substring(8).trim();
    if (rest.isNotEmpty) {
      final sp = rest.indexOf(' ');
      statusCode = int.tryParse(sp != -1 ? rest.substring(0, sp) : rest);
      description = sp != -1 ? rest.substring(sp + 1) : null;
    }
  }

  // Remaining lines: 'Key: Value' pairs until blank line
  final headers = <String, List<String>>{};
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].isEmpty) break;
    final ci = lines[i].indexOf(':');
    if (ci == -1) continue;
    final key = lines[i].substring(0, ci).trim();
    final val = lines[i].substring(ci + 1).trim();
    headers.putIfAbsent(key, () => []).add(val);
  }

  return (statusCode: statusCode, description: description, headers: headers);
}
```

### 4.4 NatsMessage Model

```dart
class NatsMessage {
  final String subject;
  final String sid;
  final String? replyTo;
  final Uint8List payload;
  final Map<String, List<String>>? headers;
  final int? statusCode;
  final String? statusDesc;

  bool get isFlowCtrl  => statusCode == 100 && (statusDesc?.contains('Flow') ?? false);
  bool get isHeartbeat => statusCode == 100 && (statusDesc?.contains('Idle') ?? false);
  bool get isNoMsg     => statusCode == 404;
  bool get isTimeout   => statusCode == 408;

  String? header(String name) => headers?[name]?.firstOrNull;
  List<String>? headerAll(String name) => headers?[name];
}
```

---

## 5 · JetStream & KV Implementation

### 5.1 JetStreamContext

```dart
class JetStreamContext {
  final NatsConnection _nc;
  final String? _domain;
  final Duration _timeout;

  StreamManager get streams   => StreamManager(this);
  ConsumerManager get consumers => ConsumerManager(this);

  Future<PubAck> publish(String subject, Uint8List data,
      {String? msgId, Map<String, String>? headers});
  Future<PullConsumer> consumer(String stream, String name);
  Future<KeyValue> keyValue(String bucket);

  String _api(String path) =>
      _domain != null ? '\$JS.$_domain.API.$path' : '\$JS.API.$path';
}
```

### 5.2 PullConsumer

```dart
class PullConsumer {
  Future<List<JsMsg>> fetch(int max, {
    Duration expires = const Duration(seconds: 5),
    int? maxBytes,
    bool noWait = false,
  }) async {
    final inbox = _js._nc._nuid.inbox();
    final sub = _js._nc.subscribe(inbox);
    final msgs = <JsMsg>[];

    await _js._nc.publish(
      '\$JS.API.CONSUMER.MSG.NEXT.$_stream.$_name',
      jsonEncodeUtf8({'batch': max, 'expires': expires.inMicroseconds * 1000,
        if (maxBytes != null) 'max_bytes': maxBytes,
        if (noWait) 'no_wait': true}),
      replyTo: inbox,
    );

    await for (final raw in sub.messages.timeout(expires + const Duration(seconds: 1))) {
      if (raw.isNoMsg || raw.isTimeout) break;
      if (raw.isFlowCtrl) {
        await _js._nc.publish(raw.replyTo!, Uint8List(0));
        continue;
      }
      msgs.add(JsMsg(raw, _js._nc));
      if (msgs.length >= max) break;
    }

    await _js._nc.unsubscribe(sub);
    return msgs;
  }

  Stream<JsMsg> consume({int batchSize = 100,
      Duration fetchExpiry = const Duration(seconds: 5)}) async* {
    while (true) {
      final batch = await fetch(batchSize, expires: fetchExpiry);
      for (final msg in batch) yield msg;
      if (batch.isEmpty) await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}
```

### 5.3 JsMsg — Ack Model

```dart
class JsMsg {
  Uint8List get data    => _raw.payload;
  String get subject    => _raw.subject;
  late final JsMsgInfo info = JsMsgInfo.parse(_raw.replyTo!);

  Future<void> ack()         => _nc.publish(_raw.replyTo!, utf8.encode('+ACK') as Uint8List);
  Future<void> nak({Duration? delay}) { /* ... */ }
  Future<void> term()        => _nc.publish(_raw.replyTo!, utf8.encode('+TERM') as Uint8List);
  Future<void> inProgress()  => _nc.publish(_raw.replyTo!, utf8.encode('+WPI') as Uint8List);
}

class JsMsgInfo {
  final String stream, consumer;
  final int numDelivered, streamSequence, consumerSequence, pending;

  // Parse: $JS.ACK.<stream>.<consumer>.<delivered>.<streamSeq>.<consumerSeq>.<ts>.<pending>
  static JsMsgInfo parse(String ackSubject) { /* ... */ }
}
```

### 5.4 OrderedConsumer (KV Watch Internals)

```dart
class OrderedConsumer {
  int _expectedSeq = 1;

  Stream<JsMsg> messages() async* {
    await _createConsumer();

    await for (final raw in _sub.messages) {
      if (raw.isHeartbeat) continue;
      if (raw.isFlowCtrl) { await _js._nc.publish(raw.replyTo!, Uint8List(0)); continue; }

      final msg = JsMsg(raw, _js._nc);
      if (msg.info.streamSequence != _expectedSeq) {
        // Gap detected — recreate from current expected sequence
        await _recreateConsumer(_expectedSeq);
        continue;
      }
      _expectedSeq++;
      yield msg;
    }
  }

  Future<void> _createConsumer() async {
    // Create ephemeral ordered push consumer:
    // ackPolicy: none, flowControl: true, idleHeartbeat: 5s
    // deliverSubject: fresh inbox, optStartSeq: _expectedSeq
  }
}
```

### 5.5 KeyValue API

```dart
class KeyValue {
  // KV bucket '$bucket' maps to JetStream stream 'KV_$bucket'

  Future<int> put(String key, Uint8List value) async {
    final ack = await _js.publish('\$KV.$_bucket.$key', value);
    return ack.sequence;
  }

  Future<KvEntry?> get(String key) async {
    // Request to $JS.API.DIRECT.GET.KV-$bucket.$key
    // Returns null if 404
  }

  Future<void> delete(String key) =>
      _js.publish('\$KV.$_bucket.$key', Uint8List(0),
          headers: {'KV-Operation': 'DEL'});

  Stream<KvEntry> watch(String key) =>
      _watchSubject('\$KV.$_bucket.$key');

  Stream<KvEntry> watchAll() =>
      _watchSubject('\$KV.$_bucket.>');

  Stream<KvEntry> _watchSubject(String filter) async* {
    final consumer = OrderedConsumer(_js, _stream, filterSubject: filter);
    await for (final msg in consumer.messages()) {
      yield KvEntry.fromJsMsg(msg);
    }
  }
}

class KvEntry {
  final String bucket, key;
  final Uint8List value;
  final int revision;           // JetStream stream sequence
  final DateTime created;
  final KvOp operation;         // put | del | purge

  String get valueString => utf8.decode(value);
  bool get isDeleted     => operation != KvOp.put;
}

enum KvOp { put, del, purge }
```

---

## 6 · NUID Generator

NUID generates URL-safe base62 identifiers used for reply-to inboxes, subscription IDs, and dedup message IDs. Port directly from `nats-io/nats.deno/nats-base-client/nuid.ts`.

```dart
class Nuid {
  static const _digits = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static const _preLen  = 12;
  static const _seqLen  = 10;
  static const _maxSeq  = 839299365868340224; // 62^10
  static const _minInc  = 33;
  static const _maxInc  = 333;

  final _random = Random.secure();
  late String _pre;
  late int _seq;
  late int _inc;

  Nuid() { _randomizePrefix(); _seq = _random.nextInt(_maxSeq); _inc = _minInc + _random.nextInt(_maxInc - _minInc); }

  String next() {
    _seq += _inc;
    if (_seq >= _maxSeq) { _randomizePrefix(); _seq = _inc; }
    return '$_pre${_seqStr()}';
  }

  String inbox([String prefix = '_INBOX']) => '$prefix.${next()}';

  void _randomizePrefix() {
    _pre = List.generate(_preLen, (_) => _digits[_random.nextInt(62)]).join();
    _inc = _minInc + _random.nextInt(_maxInc - _minInc);
  }

  String _seqStr() {
    var n = _seq;
    final b = List.filled(_seqLen, '0');
    for (var i = _seqLen - 1; i >= 0; i--) { b[i] = _digits[n % 62]; n ~/= 62; }
    return b.join();
  }
}
```

---

## 7 · Authentication & Reconnection

### 7.1 Authentication Modes

| Auth Type | CONNECT Fields | Notes |
|-----------|---------------|-------|
| No Auth | (none) | Local dev / open servers |
| Token | `auth_token: 'mytoken'` | Simple single-server setups |
| User/Password | `user: 'alice', pass: 'pw'` | Multi-user basic credentials |
| NKey | `nkey: '<public>', sig: '<signed nonce>'` | Cryptographic — preferred for production |
| JWT | `jwt: '<JWT>', nkey: '<public>', sig: '<signed nonce>'` | Decentralised operator model — enterprise |

### 7.2 JWT + NKey Handshake

```dart
// 1. Server sends INFO:
{"nonce": "randomstring", "auth_required": true}

// 2. Client signs nonce using NKey private seed:
final signature = nkeySign(nonce, privateKeySeed);

// 3. Client sends CONNECT:
{
  "jwt": "<base64-user-JWT>",
  "nkey": "<public-nkey>",
  "sig": "<base64url-signed-nonce>"
}

// 4. Server verifies signature against public key in JWT.
```

### 7.3 Reconnection & Subscription Replay

```dart
Future<void> _reconnect() async {
  int attempts = 0;
  while (_options.maxReconnectAttempts == -1 || attempts < _options.maxReconnectAttempts) {
    _status.add(ConnectionStatus.reconnecting);
    await Future.delayed(_options.reconnectDelay);
    try {
      await _connect();
      await _replaySubscriptions(); // Re-send all SUB commands
      _status.add(ConnectionStatus.connected);
      return;
    } catch (_) { attempts++; }
  }
  _status.add(ConnectionStatus.closed);
}

// JetStream note:
// - Pull consumers need to re-issue fetch requests after reconnect
// - Durable consumers persist on server — continue from last acked sequence
// - Ordered consumers (KV watch) auto-recreate from last known sequence
```

---

## 8 · Server Configuration

### 8.1 Docker Quick Start

```bash
# Dev server with JetStream + WebSocket, no TLS:
docker run -p 4222:4222 -p 9222:9222 -p 8222:8222 nats:latest \
  -js --websocket_port 9222 --websocket_no_tls

# Verify:
curl http://localhost:8222/varz   # Check 'headers' and 'jetstream' fields
curl http://localhost:8222/jsz    # JetStream stats
```

### 8.2 nats-server.conf

```
port: 4222
server_name: braven-nats

jetstream {
  store_dir: "/data/nats"
  max_memory_store: 1GB
  max_file_store: 10GB
}

# Flutter Web WebSocket connections
websocket {
  port: 9222
  no_tls: true   # Dev only
  allowed_origins: [
    "http://localhost:3000",
    "http://localhost:8080"
  ]
  # Production TLS:
  # tls {
  #   cert_file: "/etc/ssl/certs/nats.crt"
  #   key_file: "/etc/ssl/private/nats.key"
  # }
}

http_port: 8222
```

### 8.3 Connection URLs by Platform

```dart
// Flutter Web — WebSocket only (browser security model)
await NatsClient.connect('ws://nats.example.com:9222');
await NatsClient.connect('wss://nats.example.com:9222'); // production TLS

// Flutter Native (iOS, Android, macOS, Windows, Linux) — TCP preferred
await NatsClient.connect('nats://nats.example.com:4222');

// Native also supports WebSocket (through proxies, etc)
await NatsClient.connect('wss://nats.example.com:9222');

// All platforms: identical JetStream API after connecting
final js = nc.jetStream();
final kv = await js.keyValue('BravenTestSession');
await kv.put('session.hr', utf8.encode('148') as Uint8List);
```

### 8.4 Docker Compose — Integration Test Environment

```yaml
# docker-compose.yml
services:
  nats:
    image: nats:latest
    command: >
      -js -p 4222 -m 8222
      --websocket_port 9222 --websocket_no_tls
    ports:
      - '4222:4222'   # TCP — native Flutter
      - '9222:9222'   # WebSocket — Flutter Web
      - '8222:8222'   # Monitoring
```

---

## 9 · Build Plan & Test Strategy

### 9.1 Build Phases

| Phase | Deliverables | Est. Time | Milestone |
|-------|-------------|-----------|-----------|
| **Phase 1** — Core Client | Parser: MSG, HMSG, INFO, PING, +OK, -ERR · HPUB encoder with correct byte counting · WebSocket transport (`web_socket_channel`) · TCP transport (`dart:io`, conditional import) · CONNECT with `headers: true` · Auth: token, user/pass, NKey, JWT · Reconnection + subscription replay · NUID generator | 2–3 weeks | All Flutter platforms can pub/sub/request |
| **Phase 2** — JetStream | JetStreamContext (`nc.jetStream()`) · StreamManager: create/info/list/delete · ConsumerManager: create/info/delete · JS publish with PubAck + Nats-Msg-Id dedup · PullConsumer: `fetch()` and `consume()` · OrderedConsumer: auto-recreate on gap · JsMsg: ack/nak/term/inProgress · Flow control (`$JS.FC.*`) handling | 2–3 weeks | Full JetStream on all platforms |
| **Phase 3** — KV + Polish | KeyValue: put/get/delete/watch/watchAll · KvEntry model with operation type · KV bucket create with config · Integration test suite vs real server · pub.dev publication + README · Example Flutter Web + native apps | 1–2 weeks | Publishable open-source package |

### 9.2 MVP Scope — Week 3 Milestone

Minimum scope to unblock Braven Lab Studio:

- Full parser: MSG, HMSG, INFO, PING, +OK, -ERR
- HPUB encoder with correct byte counting
- WebSocket + TCP transports with conditional imports
- JWT authentication
- JetStream publish with PubAck + Nats-Msg-Id deduplication
- Pull consumer `fetch()` and `consume()` stream
- KeyValue `put()`, `get()`, `watch()`

### 9.3 Test Matrix

| Category | What to Test | Approach |
|----------|-------------|---------|
| Parser unit tests | MSG, HMSG, INFO, PING, +OK, -ERR; partial frames; status codes | Pre-recorded bytes, no server |
| Encoder unit tests | HPUB byte output, header byte counting, CONNECT JSON | Pure unit tests |
| NUID | Uniqueness, format, prefix rollover at `_maxSeq` | Statistical + deterministic |
| Transport: TCP | Connect, write, read, reconnect | Docker NATS |
| Transport: WebSocket | Connect `ws://`, disconnect, reconnect | Docker NATS |
| Core pub/sub | Round-trip, queue groups, wildcards, request/reply | Docker NATS |
| Auth | Token, user/pass, NKey, JWT challenge | Docker NATS with auth config |
| Reconnection | Kill server → reconnect → sub replay verified | Kill container mid-test |
| JS: publish | PubAck received, `duplicate:true` on same `Nats-Msg-Id` | Docker NATS + JetStream |
| JS: pull fetch | Batch sizes, `no_wait`, 404 signal, flow control reply | Docker NATS + JetStream |
| JS: `consume()` | Continuous stream, multiple batches, ack/nak/term | Docker NATS + JetStream |
| OrderedConsumer | Gap detection → recreation, sequence continuity | Docker NATS + JetStream |
| KV: CRUD | put, get, delete, purge | Docker NATS + JetStream |
| KV: watch | Real-time updates via `watch()` and `watchAll()` | Docker NATS + JetStream |
| Flutter Web | Full pub/sub + JetStream via WebSocket | Chrome headless + Docker NATS |

---

## 10 · Reference Sources

### 10.1 Primary References

| Source | URL | Use |
|--------|-----|-----|
| NATS Client Protocol Spec | docs.nats.io/reference/reference-protocols/nats-protocol | Authoritative spec: all 10 protocol commands, HPUB/HMSG syntax, INFO/CONNECT fields |
| JetStream Wire API Reference | docs.nats.io/reference/reference-protocols/nats_api_reference | All `$JS.API.*` subjects, JSON schemas, ack format, pull consumer semantics |
| ADR-4: NATS Headers | github.com/nats-io/nats-architecture-and-design/blob/main/adr/ADR-4.md | Definitive HPUB/HMSG header format, NATS/1.0 status codes, multi-value headers |
| NATS KV Concepts | docs.nats.io/nats-concepts/jetstream/key-value-store | KV bucket design, operations, ordering guarantees, underlying stream mapping |
| JetStream Consumers | docs.nats.io/nats-concepts/jetstream/consumers | Pull vs push consumers, ack policies, deliver policies, ordered consumer |
| nats-io/nats.deno | github.com/nats-io/nats.deno | **PRIMARY** implementation reference — parser, JetStream, ordered consumer, KV, NUID |
| nats.js v3 mono-repo | github.com/nats-io/nats.js | Transport abstraction architecture — the conditional-import pattern to follow |
| NATS Schema Repository | github.com/nats-io/jsm.go/schemas | JSON schemas for all JetStream API request/response payloads |
| demo.nats.io WebSocket | wss://demo.nats.io:8443 | Public NATS server for Phase 1 WebSocket validation (core NATS only, no JetStream) |
| NATS NKeys | github.com/nats-io/nkeys | NKey cryptography for auth — Dart port needed |

### 10.2 Key Files in nats.deno to Study

| File | Why It Matters |
|------|---------------|
| `nats-base-client/parser.ts` | Stateful byte-buffer parser — port this directly to Dart |
| `nats-base-client/core.ts` | NatsConnection — subscription management, request/reply, reconnection |
| `nats-base-client/jetstream.ts` | JetStreamContext, StreamManager, ConsumerManager |
| `nats-base-client/consumermessages.ts` | PullConsumer `fetch()` and `consume()` internals |
| `nats-base-client/consumer.ts` | OrderedConsumer sequence tracking and gap detection |
| `nats-base-client/kv.ts` | Full KeyValue API — bucket creation, watch, put/get |
| `nats-base-client/nuid.ts` | NUID generator — port to Dart |
| `nats-ws/src/ws_transport.ts` | WebSocket transport — maps to `websocket_transport.dart` |
| `nats-deno/src/tcp.ts` | TCP transport — maps to `tcp_transport.dart` |
| `tests/jetstream_test.ts` | Critical JetStream edge cases to replicate in Dart tests |

---

## Appendix A · JetStream Headers Reference

### Client → Server (HPUB) Headers

| Header | Example Value | Purpose |
|--------|--------------|---------|
| `Nats-Msg-Id` | `session-1-001` | Deduplication ID within stream's `duplicate_window` |
| `Nats-Expected-Stream` | `TESTS` | Publish rejected if stream name doesn't match |
| `Nats-Expected-Last-Msg-Id` | `session-1-000` | Optimistic concurrency — reject if last ID differs |
| `Nats-Expected-Last-Sequence` | `41` | Reject if stream last sequence doesn't match |
| `Nats-Rollup` | `sub` | KV rollup: `'sub'` for this key, `'all'` for entire bucket |
| `KV-Operation` | `DEL` | KV delete marker (empty payload) |

### Server → Client (HMSG) Headers

| Header | Example Value | Purpose |
|--------|--------------|---------|
| `Nats-Sequence` | `42` | Stream sequence number of this message |
| `Nats-Subject` | `TESTS.session_1` | Original publish subject |
| `Nats-Time-Stamp` | `2026-02-01T12:00:00Z` | Server-side receive timestamp |
| `Nats-Stream` | `TESTS` | Stream name |
| `Nats-Consumer` | `braven-consumer` | Consumer that delivered this message |
| `Nats-Num-Pending` | `142` | Pending messages in consumer at time of delivery |
| `Nats-Last-Sequence` | `41` | Previous sequence for this KV key |

### HMSG Status Codes — Complete Reference

| Code | Description | Required Action |
|------|-------------|----------------|
| 100 | FlowControl Request | Publish empty message to reply-to subject immediately |
| 100 | Idle Heartbeat | Verify sequence continuity; no reply |
| 404 | No Messages | End of batch — stop waiting, issue new fetch later |
| 408 | Request Timeout | Pull request expired — issue new fetch |
| 409 | Message Size Exceeds MaxBytes | Reduce `maxBytes` in next fetch request |
| 409 | Consumer Deleted | Recreate the consumer |
| 409 | Consumer is push based | Use correct consumer type for this operation |

---

*— End of Document —*
