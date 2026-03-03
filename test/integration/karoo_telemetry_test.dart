/// Integration tests for the Karoo live telemetry NATS stream.
///
/// These tests validate the [SessionState] JSON payload published by the
/// Karoo extension at 1 Hz on the [_testSubject] subject, received over
/// the embedded nats-server WebSocket transport.
///
/// Prerequisites:
///   - Karoo K24 must be on the local network running the 'nats' flavor APK
///   - nats-server must be listening on ws://<karoo-ip>:9222
///   - The device does NOT need to be in an active ride — idle payloads are
///     sufficient for schema and rate tests.
///
/// Run all:
///   dart test test/integration/karoo_telemetry_test.dart --reporter=expanded
///
/// Run a single group:
///   dart test test/integration/karoo_telemetry_test.dart --name="Payload schema" --reporter=expanded
///
/// All tests skip automatically when the Karoo is not reachable.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _karooHost = '192.168.0.137';
const _karooWsPort = 9222;
const _karooUrl = 'ws://$_karooHost:$_karooWsPort';
const _testSubject = 'TESTS.karoo';

/// Probe whether the Karoo NATS WebSocket port is reachable.
Future<bool> _isKarooAvailable() async {
  try {
    final socket = await Socket.connect(
      _karooHost,
      _karooWsPort,
      timeout: const Duration(milliseconds: 800),
    );
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Connect to the Karoo NATS server via WebSocket.
Future<NatsConnection> _connect() =>
    NatsConnection.connect(_karooUrl).timeout(const Duration(seconds: 5));

/// Decode a NATS message payload to a JSON map.
Map<String, dynamic> _decode(NatsMessage msg) {
  final raw = String.fromCharCodes(msg.payload ?? Uint8List(0));
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// Subscribe to [subject] on [nc] and collect up to [count] messages
/// within [timeout]. Returns however many arrived.
Future<List<Map<String, dynamic>>> _collect(
  NatsConnection nc,
  String subject, {
  int count = 3,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final sub = await nc.subscribe(subject);
  final results = <Map<String, dynamic>>[];
  final deadline = DateTime.now().add(timeout);

  final listener = sub.messages.listen((msg) {
    if (results.length < count) {
      results.add(_decode(msg));
    }
  });

  while (results.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  await listener.cancel();
  await nc.unsubscribe(sub);
  return results;
}

/// Throw a test-skip signal if the Karoo is not reachable.
/// Must be called at the very start of a test body (not setUp).
void _requireKaroo() {
  if (!_karooAvailable) {
    markTestSkipped('Karoo not reachable at $_karooHost:$_karooWsPort');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared availability flag
// ─────────────────────────────────────────────────────────────────────────────

bool _karooAvailable = false;

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    _karooAvailable = await _isKarooAvailable();
    if (_karooAvailable) {
      print('[KarooTelemetry] Karoo reachable at $_karooUrl');
    } else {
      print('[KarooTelemetry] $_karooHost:$_karooWsPort not reachable — '
          'all tests will be skipped.');
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 1. Payload schema
  // ───────────────────────────────────────────────────────────────────────────

  group('Payload schema', () {
    late NatsConnection nc;

    setUp(() async {
      nc = await _connect();
    });

    tearDown(() async {
      try { await nc.close(); } catch (_) {}
    });

    test('all required fields are present in the JSON payload', () async {
      _requireKaroo();

      final msgs = await _collect(nc, _testSubject, count: 1);
      expect(msgs, isNotEmpty, reason: 'Expected at least one message');
      final p = msgs.first;
      print('[Field check] keys: ${p.keys.toList()..sort()}');

      const requiredIntFields = [
        'power', 'power3sAvg', 'powerZone',
        'heartRate', 'maxHeartRate', 'cadence',
        'elapsedTime', 'lapNumber', 'lapPower', 'lapTime',
        'lapHeartRate', 'lapCadence', 'lapNormalizedPower', 'lapMaxPower',
        'lastLapPower', 'lastLapTime', 'batteryPercent', 'timestamp',
      ];

      const requiredNumFields = [
        'speed', 'averageSpeed', 'distance', 'elevation', 'grade',
        'temperature', 'coreTemp', 'latitude', 'longitude',
        'lapSpeed', 'lapDistance', 'lastLapSpeed',
      ];

      const requiredStringFields = [
        'trainerState', 'rideState', 'wifiState', 'natsState',
      ];

      // Nullable fields — must be present in the JSON, but may be null.
      const nullableFields = [
        'lactate', 'lactateTimestamp',
        'trainerDeviceName', 'trainerTargetPower', 'trainerError',
        'rideStartedAt',
      ];

      for (final field in requiredIntFields) {
        expect(p.containsKey(field), isTrue,
            reason: 'Missing integer field: $field');
        expect(p[field], isA<int>(),
            reason: '$field should be an int, got ${p[field].runtimeType}');
      }

      for (final field in requiredNumFields) {
        expect(p.containsKey(field), isTrue,
            reason: 'Missing numeric field: $field');
        expect(p[field], isA<num>(),
            reason: '$field should be a num, got ${p[field].runtimeType}');
      }

      for (final field in requiredStringFields) {
        expect(p.containsKey(field), isTrue,
            reason: 'Missing string field: $field');
        expect(p[field], isA<String>(),
            reason: '$field should be a String, got ${p[field].runtimeType}');
      }

      for (final field in nullableFields) {
        expect(p.containsKey(field), isTrue,
            reason: 'Nullable field $field must be present (even if null)');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('nullable fields are null or the expected type', () async {
      _requireKaroo();

      final msgs = await _collect(nc, _testSubject, count: 1);
      expect(msgs, isNotEmpty);
      final p = msgs.first;

      // lactate: null or double
      final lactate = p['lactate'];
      expect(
        lactate == null || lactate is num,
        isTrue,
        reason: 'lactate should be null or num, got ${lactate.runtimeType}',
      );

      // lactateTimestamp: null or int
      final lactateTs = p['lactateTimestamp'];
      expect(
        lactateTs == null || lactateTs is int,
        isTrue,
        reason: 'lactateTimestamp should be null or int, '
            'got ${lactateTs.runtimeType}',
      );

      // trainerDeviceName: null or String
      final trainerName = p['trainerDeviceName'];
      expect(
        trainerName == null || trainerName is String,
        isTrue,
        reason: 'trainerDeviceName should be null or String',
      );

      // trainerTargetPower: null or int
      final trainerPower = p['trainerTargetPower'];
      expect(
        trainerPower == null || trainerPower is int,
        isTrue,
        reason: 'trainerTargetPower should be null or int',
      );

      // trainerError: null or String
      final trainerError = p['trainerError'];
      expect(
        trainerError == null || trainerError is String,
        isTrue,
        reason: 'trainerError should be null or String',
      );

      // rideStartedAt: null when idle, int when recording
      final rideStartedAt = p['rideStartedAt'];
      expect(
        rideStartedAt == null || rideStartedAt is int,
        isTrue,
        reason: 'rideStartedAt should be null or int, '
            'got ${rideStartedAt.runtimeType}',
      );
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. Physical plausibility
  // ───────────────────────────────────────────────────────────────────────────

  group('Physical plausibility', () {
    late NatsConnection nc;

    setUp(() async {
      nc = await _connect();
    });

    tearDown(() async {
      try { await nc.close(); } catch (_) {}
    });

    test('numeric fields are within physically valid ranges', () async {
      _requireKaroo();

      // Collect a few messages and check every one — if the Karoo is
      // occasionally spiking a bad value, we want to catch it.
      final msgs = await _collect(nc, _testSubject, count: 3);
      expect(msgs, isNotEmpty);

      for (final p in msgs) {
        // Power — cyclists produce 0–3000 W in reality; never negative
        expect((p['power'] as int), greaterThanOrEqualTo(0),
            reason: 'power must be >= 0');
        expect((p['power'] as int), lessThanOrEqualTo(3000),
            reason: 'power looks unrealistically high');

        expect((p['power3sAvg'] as int), greaterThanOrEqualTo(0),
            reason: 'power3sAvg must be >= 0');

        expect((p['powerZone'] as int), inInclusiveRange(0, 7),
            reason: 'powerZone must be 0–7');

        // Heart rate — 0 means no sensor; max credible ~300 bpm
        expect((p['heartRate'] as int), inInclusiveRange(0, 300),
            reason: 'heartRate out of range');
        expect((p['maxHeartRate'] as int), inInclusiveRange(0, 300),
            reason: 'maxHeartRate out of range');
        expect((p['heartRate'] as int),
            lessThanOrEqualTo(p['maxHeartRate'] as int),
            reason:
                'heartRate should not exceed maxHeartRate (both may be 0 at idle)');

        // Cadence — 0–250 rpm
        expect((p['cadence'] as int), inInclusiveRange(0, 250),
            reason: 'cadence out of range');

        // Speed — 0–200 km/h
        expect((p['speed'] as num).toDouble(), greaterThanOrEqualTo(0.0),
            reason: 'speed must be >= 0');
        expect((p['speed'] as num).toDouble(), lessThanOrEqualTo(200.0),
            reason: 'speed looks unrealistically high');

        // Battery — -1 means unavailable, 0-100 otherwise
        expect((p['batteryPercent'] as int), inInclusiveRange(-1, 100),
            reason: 'batteryPercent must be -1 or 0-100');

        // Lat/lon — within valid WGS-84 bounds
        expect((p['latitude'] as num).toDouble(), inInclusiveRange(-90.0, 90.0),
            reason: 'latitude out of WGS-84 range');
        expect(
            (p['longitude'] as num).toDouble(), inInclusiveRange(-180.0, 180.0),
            reason: 'longitude out of WGS-84 range');

        // Lap number must be >= 1
        expect((p['lapNumber'] as int), greaterThanOrEqualTo(0),
            reason: 'lapNumber must be >= 0');

        // Elapsed time must be non-negative
        expect((p['elapsedTime'] as int), greaterThanOrEqualTo(0),
            reason: 'elapsedTime must be >= 0');

        // Distance must be non-negative
        expect((p['distance'] as num).toDouble(), greaterThanOrEqualTo(0.0),
            reason: 'distance must be >= 0');

        // Timestamp must be a plausible recent unix-ms
        final ts = p['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        expect(ts, greaterThan(0), reason: 'timestamp must be > 0');
        expect(ts, lessThanOrEqualTo(now + 5000),
            reason: 'timestamp is in the future (clock skew?)');
        expect(ts, greaterThanOrEqualTo(now - 30000),
            reason: 'timestamp is more than 30s in the past — may be stale');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('enum string fields contain only valid values', () async {
      _requireKaroo();

      const validRideStates = {'IDLE', 'RECORDING', 'PAUSED', 'PAUSED_AUTO'};
      const validWifiStates = {'UNKNOWN', 'CONNECTED', 'DISCONNECTED'};
      const validNatsStates = {
        'DISABLED', 'CONNECTING', 'CONNECTED', 'DISCONNECTED'
      };
      const validTrainerStates = {
        'DISCONNECTED', 'SCANNING', 'CONNECTING', 'CONNECTED', 'CONTROLLING',
        'ERROR'
      };

      final msgs = await _collect(nc, _testSubject, count: 3);
      expect(msgs, isNotEmpty);

      for (final p in msgs) {
        expect(validRideStates, contains(p['rideState']),
            reason: 'Unexpected rideState: ${p['rideState']}');

        expect(validWifiStates, contains(p['wifiState']),
            reason: 'Unexpected wifiState: ${p['wifiState']}');

        expect(validNatsStates, contains(p['natsState']),
            reason: 'Unexpected natsState: ${p['natsState']}');

        expect(validTrainerStates, contains(p['trainerState']),
            reason: 'Unexpected trainerState: ${p['trainerState']}');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('natsState is CONNECTED — publisher is live', () async {
      _requireKaroo();

      // The Karoo NatsPublisher updates natsState → CONNECTED once it connects
      // to the local nats-server. This verifies the publisher side of things.
      final msgs = await _collect(nc, _testSubject, count: 3);
      expect(msgs, isNotEmpty);

      final firstConnected =
          msgs.firstWhere((p) => p['natsState'] == 'CONNECTED', orElse: () {
        return <String, dynamic>{};
      });

      expect(
        firstConnected,
        isNotEmpty,
        reason: 'Expected at least one message with natsState=CONNECTED. '
            'Received natsState values: ${msgs.map((p) => p['natsState']).toList()}',
      );
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Message delivery
  // ───────────────────────────────────────────────────────────────────────────

  group('Message delivery', () {
    late NatsConnection nc;

    setUp(() async {
      nc = await _connect();
    });

    tearDown(() async {
      try { await nc.close(); } catch (_) {}
    });

    test('messages arrive at approximately 1 Hz', () async {
      _requireKaroo();

      // Collect 6 messages and measure the elapsed wall time.
      // At 1Hz: 5 intervals ≈ 5s.
      // Allow generous tolerance: 0.3–3 Hz, i.e. 1.7s–16.7s for 5 intervals.
      const sampleCount = 6;
      final sub = await nc.subscribe(_testSubject);
      final timestamps = <DateTime>[];

      final listener = sub.messages.listen((_) {
        if (timestamps.length < sampleCount) {
          timestamps.add(DateTime.now());
        }
      });

      final deadline =
          DateTime.now().add(const Duration(seconds: 20));
      while (timestamps.length < sampleCount &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await listener.cancel();
      await nc.unsubscribe(sub);

      expect(timestamps.length, greaterThanOrEqualTo(sampleCount),
          reason: 'Only received ${timestamps.length}/$sampleCount messages '
              'within the observation window');

      // Measure intervals between consecutive messages
      final intervals = <Duration>[];
      for (int i = 1; i < timestamps.length; i++) {
        intervals.add(timestamps[i].difference(timestamps[i - 1]));
      }

      final totalMs =
          timestamps.last.difference(timestamps.first).inMilliseconds;
      final rateHz =
          (sampleCount - 1) / (totalMs / 1000.0);

      print('[Rate] ${sampleCount - 1} intervals over ${totalMs}ms '
          '→ ${rateHz.toStringAsFixed(2)} Hz');

      for (int i = 0; i < intervals.length; i++) {
        final ms = intervals[i].inMilliseconds;
        print('[Rate] interval[$i] = ${ms}ms');
        expect(ms, greaterThan(300),
            reason: 'Inter-message interval[$i] = ${ms}ms is implausibly short '
                '(publisher runs at 1 Hz, expect >= 300ms)');
        expect(ms, lessThan(5000),
            reason: 'Inter-message interval[$i] = ${ms}ms is too long '
                '(publisher appears stuck)');
      }

      expect(rateHz, greaterThan(0.3),
          reason: 'Effective rate ${rateHz.toStringAsFixed(2)} Hz is below '
              '0.3 Hz — messages are arriving too slowly');
      expect(rateHz, lessThan(3.0),
          reason: 'Effective rate ${rateHz.toStringAsFixed(2)} Hz exceeds '
              '3 Hz — publisher may have been misconfigured');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('timestamps in payload are non-decreasing across consecutive messages',
        () async {
      _requireKaroo();

      final msgs = await _collect(nc, _testSubject, count: 5);
      expect(msgs.length, greaterThanOrEqualTo(2),
          reason: 'Need at least 2 messages for monotonicity check');

      for (int i = 1; i < msgs.length; i++) {
        final prev = msgs[i - 1]['timestamp'] as int;
        final curr = msgs[i]['timestamp'] as int;
        expect(curr, greaterThanOrEqualTo(prev),
            reason: 'Timestamp went backwards at msg $i: '
                '${msgs[i - 1]['timestamp']} → ${msgs[i]['timestamp']}');
        // Timestamps should also advance: no two consecutive messages from
        // a 1Hz publisher should have the same unix-ms timestamp.
        expect(curr, greaterThan(prev - 1),
            reason: 'Timestamps not advancing — clock may be frozen');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        'payload is valid UTF-8 JSON (not binary) and under 4 KB per message',
        () async {
      _requireKaroo();

      final sub = await nc.subscribe(_testSubject);
      NatsMessage? rawMsg;

      final listener = sub.messages.listen((msg) => rawMsg ??= msg);
      final deadline = DateTime.now().add(const Duration(seconds: 10));

      while (rawMsg == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await listener.cancel();
      await nc.unsubscribe(sub);

      expect(rawMsg, isNotNull, reason: 'No message received');

      final payload = rawMsg!.payload!;
      print('[Payload] size = ${payload.lengthInBytes} bytes');

      // Size < 4 KB (spec says ~820 bytes)
      expect(payload.lengthInBytes, lessThan(4096),
          reason: 'Payload is suspiciously large — possible encoding issue');
      expect(payload.lengthInBytes, greaterThan(100),
          reason: 'Payload is suspiciously small — may be truncated');

      // Valid UTF-8
      String decoded;
      expect(
        () => decoded = utf8.decode(payload),
        returnsNormally,
        reason: 'Payload is not valid UTF-8',
      );

      // Valid JSON object
      decoded = utf8.decode(payload);
      Object? parsed;
      expect(
        () => parsed = jsonDecode(decoded),
        returnsNormally,
        reason: 'Payload is not valid JSON: $decoded',
      );
      expect(parsed, isA<Map<String, dynamic>>(),
          reason: 'JSON root should be an object, got ${parsed.runtimeType}');
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. Multi-subscriber fan-out
  // ───────────────────────────────────────────────────────────────────────────

  group('Multi-subscriber fan-out', () {
    test('two independent connections both receive messages on TESTS.karoo',
        () async {
      _requireKaroo();

      // Open two separate WebSocket connections to the same nats-server.
      final nc1 = await _connect();
      final nc2 = await _connect();

      try {
        final received1 = <Map<String, dynamic>>[];
        final received2 = <Map<String, dynamic>>[];

        final sub1 = await nc1.subscribe(_testSubject);
        final sub2 = await nc2.subscribe(_testSubject);

        final l1 = sub1.messages.listen((msg) {
          if (received1.length < 3) received1.add(_decode(msg));
        });
        final l2 = sub2.messages.listen((msg) {
          if (received2.length < 3) received2.add(_decode(msg));
        });

        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while ((received1.length < 3 || received2.length < 3) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        await l1.cancel();
        await l2.cancel();
        await nc1.unsubscribe(sub1);
        await nc2.unsubscribe(sub2);

        print('[Fan-out] nc1 received ${received1.length} msgs, '
            'nc2 received ${received2.length} msgs');

        expect(received1, isNotEmpty,
            reason: 'First subscriber received no messages');
        expect(received2, isNotEmpty,
            reason: 'Second subscriber received no messages');

        // Both got data — verify they are seeing the same subject
        expect(received1.every((p) => p.containsKey('timestamp')), isTrue);
        expect(received2.every((p) => p.containsKey('timestamp')), isTrue);

        // The payloads should be very similar in structure (same schema)
        expect(received1.first.keys.toSet(), equals(received2.first.keys.toSet()),
            reason: 'Both subscribers should see the same JSON schema');
      } finally {
        await nc1.close();
        await nc2.close();
      }
    }, timeout: const Timeout(Duration(seconds: 25)));

    test('single connection with two subscriptions on same subject both fire',
        () async {
      _requireKaroo();

      final nc = await _connect();
      try {
        final received1 = <Map<String, dynamic>>[];
        final received2 = <Map<String, dynamic>>[];

        final sub1 = await nc.subscribe(_testSubject);
        final sub2 = await nc.subscribe(_testSubject);

        final l1 = sub1.messages.listen((msg) {
          if (received1.length < 2) received1.add(_decode(msg));
        });
        final l2 = sub2.messages.listen((msg) {
          if (received2.length < 2) received2.add(_decode(msg));
        });

        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((received1.length < 2 || received2.length < 2) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        await l1.cancel();
        await l2.cancel();
        await nc.unsubscribe(sub1);
        await nc.unsubscribe(sub2);

        print('[Dual-sub] sub1=${received1.length} sub2=${received2.length}');

        expect(received1, isNotEmpty,
            reason: 'First subscription received no messages');
        expect(received2, isNotEmpty,
            reason: 'Second subscription received no messages');
      } finally {
        await nc.close();
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. Wildcard subscription
  // ───────────────────────────────────────────────────────────────────────────

  group('Wildcard subscription', () {
    late NatsConnection nc;

    setUp(() async {
      nc = await _connect();
    });

    tearDown(() async {
      try { await nc.close(); } catch (_) {}
    });

    test('TESTS.> wildcard receives TESTS.karoo messages', () async {
      _requireKaroo();

      final msgs = await _collect(nc, 'TESTS.>', count: 3);

      expect(msgs, isNotEmpty,
          reason: 'Wildcard TESTS.> received no messages — '
              'expected to match TESTS.karoo');
      expect(msgs.every((p) => p.containsKey('power')), isTrue,
          reason: 'Wildcard messages should be SessionState payloads');
      print('[Wildcard] received ${msgs.length} messages on TESTS.>');
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('TESTS.* wildcard receives TESTS.karoo messages', () async {
      _requireKaroo();

      final msgs = await _collect(nc, 'TESTS.*', count: 2);

      expect(msgs, isNotEmpty,
          reason: 'Wildcard TESTS.* received no messages — '
              'expected to match TESTS.karoo');
      print('[Wildcard] received ${msgs.length} messages on TESTS.*');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6. Connection hygiene
  // ───────────────────────────────────────────────────────────────────────────

  group('Connection hygiene', () {
    test('close() and reconnect receives fresh messages', () async {
      _requireKaroo();

      // First connection — receive a couple of messages
      final nc1 = await _connect();
      final firstBatch = await _collect(nc1, _testSubject, count: 2);
      await nc1.close();

      expect(firstBatch, isNotEmpty);

      // Second connection — should get fresh messages
      final nc2 = await _connect();
      try {
        final secondBatch =
            await _collect(nc2, _testSubject, count: 2);
        expect(secondBatch, isNotEmpty,
            reason: 'Second connection should also receive messages');

        // Timestamps from second batch should be >= first batch (time moves forward)
        final lastFirst = firstBatch.last['timestamp'] as int;
        final firstSecond = secondBatch.first['timestamp'] as int;
        print('[Reconnect] lastFirst=$lastFirst firstSecond=$firstSecond');

        expect(firstSecond, greaterThanOrEqualTo(lastFirst - 2000),
            reason: 'Second-connection timestamps should not be earlier than '
                'first-connection timestamps (allow 2s fuzz for timing)');
      } finally {
        await nc2.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('subscribing with unsubscribe stops receiving messages', () async {
      _requireKaroo();

      final nc = await _connect();
      try {
        final sub = await nc.subscribe(_testSubject);
        int count = 0;

        final listener = sub.messages.listen((_) => count++);

        // Receive at least 1 message before unsubscribing
        await Future<void>.delayed(const Duration(seconds: 3));
        final countBefore = count;

        await listener.cancel();
        await nc.unsubscribe(sub);

        // Wait another 2s — should receive no more messages
        final countAfterUnsubscribe = count;
        await Future<void>.delayed(const Duration(seconds: 2));
        final countAfterWait = count;

        print('[Unsub] before=$countBefore afterUnsub=$countAfterUnsubscribe '
            'afterWait=$countAfterWait');

        expect(countBefore, greaterThan(0),
            reason: 'Should have received messages before unsubscribe');

        // After unsubscribing, no new messages should arrive
        expect(countAfterWait, equals(countAfterUnsubscribe),
            reason: 'Messages should stop after unsubscribe');
      } finally {
        await nc.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
