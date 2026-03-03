/// Interactive NATS Test Harness
///
/// A CLI tool for manually testing pub/sub, request/reply, and wildcard
/// subscriptions against a live NATS server. Useful for cross-language
/// interop testing (e.g. Dart ↔ Kotlin).
///
/// Usage:
/// ```bash
/// # Start NATS server (see docker-compose.yml in repo root)
/// docker-compose up -d nats
///
/// # Run with defaults (localhost:4222)
/// dart run example/test_harness.dart
///
/// # Run against a specific server
/// dart run example/test_harness.dart nats://myserver:4222
/// ```
///
/// Commands (interactive):
/// ```
/// sub <subject>              Subscribe to a subject
/// pub <subject> <payload>   Publish a message
/// req <subject> <payload>   Send a request and wait for reply (timeout 5s)
/// rep <subject>             Start an echo responder on a subject
/// unsub <subject>           Unsubscribe from a subject
/// status                    Show connection status and active subscriptions
/// quit                      Disconnect and exit
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

// ANSI colour helpers
String _green(String s) => '\x1B[32m$s\x1B[0m';
String _yellow(String s) => '\x1B[33m$s\x1B[0m';
String _red(String s) => '\x1B[31m$s\x1B[0m';
String _cyan(String s) => '\x1B[36m$s\x1B[0m';
String _dim(String s) => '\x1B[2m$s\x1B[0m';

// ignore_for_file: avoid_print
void _log(String msg) => print(msg);
void _ok(String msg) => _log(_green('✓ $msg'));
void _warn(String msg) => _log(_yellow('⚠ $msg'));
void _err(String msg) => _log(_red('✗ $msg'));
void _info(String msg) => _log(_cyan('  $msg'));

String _ts() {
  final now = DateTime.now();
  return _dim(
    '[${now.hour.toString().padLeft(2, '0')}:'
    '${now.minute.toString().padLeft(2, '0')}:'
    '${now.second.toString().padLeft(2, '0')}.'
    '${now.millisecond.toString().padLeft(3, '0')}]',
  );
}

// ── Subscription registry ────────────────────────────────────────────────────

final Map<String, Subscription> _subs = {};
final Map<String, Subscription> _responders = {};

void _printHelp() {
  _log('');
  _log(_cyan('╔══════════════════════════════════════════════════╗'));
  _log(_cyan('║         NATS Dart Test Harness — Commands        ║'));
  _log(_cyan('╠══════════════════════════════════════════════════╣'));
  _log(_cyan('║  sub   <subject>              Subscribe          ║'));
  _log(_cyan('║  pub   <subject> <payload>    Publish            ║'));
  _log(_cyan('║  pubh  <subject> <k=v,...>    Publish w/headers  ║'));
  _log(_cyan('║  req   <subject> <payload>    Request/Reply      ║'));
  _log(_cyan('║  rep   <subject>              Start echo service ║'));
  _log(_cyan('║  unsub <subject>              Unsubscribe        ║'));
  _log(_cyan('║  status                       Show state         ║'));
  _log(_cyan('║  help                         Show this menu     ║'));
  _log(_cyan('║  quit                         Disconnect & exit  ║'));
  _log(_cyan('╚══════════════════════════════════════════════════╝'));
  _log('');
}

// ── Message display ──────────────────────────────────────────────────────────

void _displayMessage(NatsMessage msg, {String prefix = '◀ MSG'}) {
  final payload =
      msg.payload != null ? _tryUtf8(msg.payload!) : _dim('<empty>');
  final replyStr = msg.replyTo != null ? _dim('→ ${msg.replyTo!}') : '';

  _log(
    '${_ts()} ${_cyan(prefix)} '
    '${_yellow(msg.subject ?? "(no subject)")} $replyStr'
    '\n         payload : $payload',
  );

  if (msg.headers != null && msg.headers!.isNotEmpty) {
    for (final entry in msg.headers!.entries) {
      _log('         header  : ${entry.key}: ${entry.value.join(", ")}');
    }
  }

  if (msg.statusCode != null) {
    _log('         status  : ${msg.statusCode} ${msg.statusDesc ?? ""}');
  }
}

String _tryUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}';
  }
}

// ── Command handlers ─────────────────────────────────────────────────────────

Future<void> _handleSub(NatsConnection nc, List<String> args) async {
  if (args.isEmpty) {
    _err('Usage: sub <subject>');
    return;
  }
  final subject = args[0];

  if (_subs.containsKey(subject)) {
    _warn('Already subscribed to "$subject"');
    return;
  }

  final sub = await nc.subscribe(subject);
  _subs[subject] = sub;
  _ok('Subscribed to "$subject"');

  sub.messages.listen(
    (msg) => _displayMessage(msg),
    onDone: () {
      _subs.remove(subject);
      _info('Subscription "$subject" closed');
    },
  );
}

Future<void> _handlePub(NatsConnection nc, List<String> args) async {
  if (args.length < 2) {
    _err('Usage: pub <subject> <payload>');
    return;
  }
  final subject = args[0];
  final payload = Uint8List.fromList(utf8.encode(args.sublist(1).join(' ')));

  await nc.publish(subject, payload);
  _ok('Published to "$subject": ${utf8.decode(payload)}');
}

Future<void> _handlePubWithHeaders(NatsConnection nc, List<String> args) async {
  if (args.length < 2) {
    _err('Usage: pubh <subject> <key=value,...> [payload]');
    _info(
        'Example: pubh events.order Nats-Msg-Id=abc123,Content-Type=text/plain hello');
    return;
  }

  final subject = args[0];
  final headerStr = args[1];
  final payloadStr = args.length > 2 ? args.sublist(2).join(' ') : '';

  final headers = <String, String>{};
  for (final part in headerStr.split(',')) {
    final idx = part.indexOf('=');
    if (idx > 0) {
      headers[part.substring(0, idx).trim()] = part.substring(idx + 1).trim();
    }
  }

  final payload = Uint8List.fromList(utf8.encode(payloadStr));
  await nc.publish(subject, payload, headers: headers);
  _ok('Published to "$subject" with headers: ${headers.keys.join(", ")}');
}

Future<void> _handleReq(NatsConnection nc, List<String> args) async {
  if (args.length < 2) {
    _err('Usage: req <subject> <payload>');
    return;
  }
  final subject = args[0];
  final payload = Uint8List.fromList(utf8.encode(args.sublist(1).join(' ')));

  _info('Sending request to "$subject"...');
  try {
    final reply = await nc.request(
      subject,
      payload,
      timeout: const Duration(seconds: 5),
    );
    _ok('Reply received:');
    _displayMessage(reply, prefix: '◀ REP');
  } on TimeoutException {
    _err('Request timed out (5s) — no responder on "$subject"');
  } catch (e) {
    _err('Request failed: $e');
  }
}

Future<void> _handleRep(NatsConnection nc, List<String> args) async {
  if (args.isEmpty) {
    _err('Usage: rep <subject>');
    return;
  }
  final subject = args[0];

  if (_responders.containsKey(subject)) {
    _warn('Already have an echo responder on "$subject"');
    return;
  }

  final sub = await nc.subscribe(subject);
  _responders[subject] = sub;
  _ok('Echo responder started on "$subject" (replies with ECHO:<payload>)');

  sub.messages.listen((msg) async {
    _displayMessage(msg, prefix: '◀ REC');

    if (msg.replyTo != null) {
      final inPayload = msg.payload != null ? _tryUtf8(msg.payload!) : '';
      final response = Uint8List.fromList(utf8.encode('ECHO:$inPayload'));
      await nc.publish(msg.replyTo!, response);
      _info('  → echoed to ${msg.replyTo}');
    } else {
      _dim('  (no replyTo — no response sent)');
    }
  });
}

Future<void> _handleUnsub(NatsConnection nc, List<String> args) async {
  if (args.isEmpty) {
    _err('Usage: unsub <subject>');
    return;
  }
  final subject = args[0];

  final sub = _subs[subject] ?? _responders[subject];
  if (sub == null) {
    _err('No active subscription for "$subject"');
    return;
  }

  await nc.unsubscribe(sub);
  _subs.remove(subject);
  _responders.remove(subject);
  _ok('Unsubscribed from "$subject"');
}

void _handleStatus(NatsConnection nc) {
  _log('');
  _log(_cyan('── Connection Status ───────────────────────'));
  _info('Connected : ${nc.isConnected ? _green("yes") : _red("no")}');
  _log('');

  if (_subs.isEmpty && _responders.isEmpty) {
    _info('No active subscriptions');
  } else {
    if (_subs.isNotEmpty) {
      _info('Subscriptions:');
      for (final s in _subs.keys) {
        _log('    ${_yellow(s)}');
      }
    }
    if (_responders.isNotEmpty) {
      _info('Echo responders:');
      for (final s in _responders.keys) {
        _log('    ${_yellow(s)} ${_dim("(echo)")}');
      }
    }
  }
  _log('');
}

// ── Main ─────────────────────────────────────────────────────────────────────

Future<void> main(List<String> argv) async {
  final serverUrl = argv.isNotEmpty ? argv[0] : 'nats://localhost:4222';

  _log('');
  _log(_cyan('═══════════════════════════════════════════════════'));
  _log(_cyan('  NATS Dart Test Harness'));
  _log(_cyan('  Server : $serverUrl'));
  _log(_cyan('═══════════════════════════════════════════════════'));
  _log('');

  // ── Connect ─────────────────────────────────────────────────────────────
  late NatsConnection nc;
  try {
    nc = await NatsConnection.connect(
      serverUrl,
      options: const ConnectOptions(
        name: 'dart-test-harness',
        maxReconnectAttempts: -1, // infinite
        reconnectDelay: Duration(seconds: 2),
        pingInterval: Duration(seconds: 30),
      ),
    );
    _ok('Connected to $serverUrl');
  } catch (e) {
    _err('Failed to connect: $e');
    _info('Make sure NATS is running:  docker run -p 4222:4222 nats:latest');
    exit(1);
  }

  // ── Status stream ────────────────────────────────────────────────────────
  nc.status.listen((status) {
    switch (status) {
      case ConnectionStatus.reconnecting:
        _warn('Connection lost — reconnecting...');
      case ConnectionStatus.connected:
        _ok('Reconnected');
      case ConnectionStatus.closed:
        _warn('Connection closed');
      default:
        break;
    }
  });

  _printHelp();

  // ── REPL ─────────────────────────────────────────────────────────────────
  stdout.write('> ');
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      stdout.write('> ');
      continue;
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final cmd = parts[0].toLowerCase();
    final args = parts.sublist(1);

    try {
      switch (cmd) {
        case 'sub':
          await _handleSub(nc, args);
        case 'pub':
          await _handlePub(nc, args);
        case 'pubh':
          await _handlePubWithHeaders(nc, args);
        case 'req':
          await _handleReq(nc, args);
        case 'rep':
          await _handleRep(nc, args);
        case 'unsub':
          await _handleUnsub(nc, args);
        case 'status':
          _handleStatus(nc);
        case 'help':
          _printHelp();
        case 'quit':
        case 'exit':
        case 'q':
          _log('Disconnecting...');
          await nc.close();
          _ok('Goodbye.');
          exit(0);
        default:
          _err('Unknown command: "$cmd"  (type "help" for commands)');
      }
    } catch (e, st) {
      _err('Error: $e');
      _log(_dim(st.toString()));
    }

    stdout.write('> ');
  }
}
