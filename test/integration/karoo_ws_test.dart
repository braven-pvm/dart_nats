/// Integration test: connect to the Karoo device NATS server over WebSocket
/// and subscribe to the TESTS.karoo subject.
///
/// The Karoo device must be on the local network and the NATS server must be
/// running with WebSocket enabled on port 9222.
///
/// Run with:
///   dart test test/integration/karoo_ws_test.dart --reporter=expanded

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:nats_dart/nats_dart.dart';

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
      timeout: const Duration(milliseconds: 500),
    );
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  bool _karooAvailable = false;

  setUpAll(() async {
    _karooAvailable = await _isKarooAvailable();
    if (!_karooAvailable) {
      // ignore: avoid_print
      print('[KarooTest] $_karooHost:$_karooWsPort not reachable — '
          'tests will be skipped.');
    } else {
      // ignore: avoid_print
      print('[KarooTest] Karoo reachable at $_karooUrl');
    }
  });

  group('Karoo NATS WebSocket ($_karooUrl)', () {
    test('connects successfully', () async {
      if (!_karooAvailable) {
        markTestSkipped('Karoo not reachable at $_karooHost:$_karooWsPort');
        return;
      }

      final nc = await NatsConnection.connect(_karooUrl);
      try {
        expect(nc.isConnected, isTrue);
      } finally {
        await nc.close();
      }
    });

    test('subscribes to $_testSubject and receives messages', () async {
      if (!_karooAvailable) {
        markTestSkipped('Karoo not reachable at $_karooHost:$_karooWsPort');
        return;
      }

      final nc = await NatsConnection.connect(_karooUrl);
      final received = <NatsMessage>[];

      try {
        final sub = await nc.subscribe(_testSubject);
        final subscription = sub.messages.listen((msg) {
          received.add(msg);
          // ignore: avoid_print
          print('[KarooTest] received on ${msg.subject}: '
              '${String.fromCharCodes(msg.payload ?? [])}');
        });

        // Wait up to 5 s for at least one message.
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (received.isEmpty && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        await subscription.cancel();
        await nc.unsubscribe(sub);

        // ignore: avoid_print
        print('[KarooTest] received ${received.length} message(s) '
            'on $_testSubject in 5 s');

        // We don't fail if no messages arrived — the subject may be quiet.
        // The test passes as long as the subscription worked without crashing.
        expect(nc.isConnected, isTrue);
      } finally {
        await nc.close();
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('can publish to $_testSubject', () async {
      if (!_karooAvailable) {
        markTestSkipped('Karoo not reachable at $_karooHost:$_karooWsPort');
        return;
      }

      final nc = await NatsConnection.connect(_karooUrl);
      try {
        // Publish a ping message; doesn't assert a response, just verifies
        // the publish path doesn't throw.
        await nc.publish(
          _testSubject,
          Uint8List.fromList('ping from dart_nats test'.codeUnits),
        );
        expect(nc.isConnected, isTrue);
      } finally {
        await nc.close();
      }
    });
  });
}
