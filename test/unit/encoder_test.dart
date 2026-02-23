import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/protocol/encoder.dart';

void main() {
  group('PUB encoding', () {
    test('encode PUB without reply', () {
      final payload = Uint8List.fromList('Hello, NATS!'.codeUnits);
      final result = NatsEncoder.pub('test.subject', payload);

      final expected = 'PUB test.subject 12\r\nHello, NATS!\r\n';
      expect(String.fromCharCodes(result), equals(expected));
    });

    test('encode PUB with reply-to', () {
      final payload = Uint8List.fromList('Reply data'.codeUnits);
      const replyTo = 'inbox.123';
      final result = NatsEncoder.pub('test.subject', payload, replyTo: replyTo);

      final expected = 'PUB test.subject $replyTo 10\r\nReply data\r\n';
      expect(String.fromCharCodes(result), equals(expected));
    });

    test('encode PUB with empty payload', () {
      final payload = Uint8List(0);
      final result = NatsEncoder.pub('test.subject', payload);

      final expected = 'PUB test.subject 0\r\n\r\n';
      expect(String.fromCharCodes(result), equals(expected));
    });
  });

  group('HPUB encoding', () {
    test('encode HPUB with headers', () {
      final payload = Uint8List.fromList('Message'.codeUnits);
      final headers = {'Content-Type': 'text/plain', 'X-Request-Id': 'abc123'};
      final result =
          NatsEncoder.hpub('test.subject', payload, headers: headers);

      final resultStr = String.fromCharCodes(result);
      expect(resultStr, startsWith('HPUB test.subject '));
      expect(resultStr, contains('NATS/1.0\r\n'));
      expect(resultStr, contains('Content-Type: text/plain\r\n'));
      expect(resultStr, contains('X-Request-Id: abc123\r\n'));
      expect(resultStr, endsWith('\r\n\r\nMessage\r\n'));
    });

    test('encode HPUB with headers and reply-to', () {
      final payload = Uint8List.fromList('Data'.codeUnits);
      final headers = {'Key': 'Value'};
      const replyTo = 'reply.subject';
      final result = NatsEncoder.hpub(
        'test.subject',
        payload,
        replyTo: replyTo,
        headers: headers,
      );

      final resultStr = String.fromCharCodes(result);
      expect(resultStr, startsWith('HPUB test.subject $replyTo '));
      expect(resultStr, contains('NATS/1.0\r\n'));
      expect(resultStr, contains('Key: Value\r\n'));
    });

    test('HPUB byte counting accuracy', () {
      // Header section: NATS/1.0 + blank line = 10 bytes
      // +2 for final \r\nn = 12 header bytes
      final payload = Uint8List.fromList('X'.codeUnits); // 1 byte
      final headers = <String, String>{}; // No custom headers
      final result =
          NatsEncoder.hpub('test.subject', payload, headers: headers);

      final resultStr = String.fromCharCodes(result);
      // Extract header byte count from HPUB command
      final match =
          RegExp(r'HPUB test\.subject (\d+) (\d+)').firstMatch(resultStr);
      expect(match, isNotNull);
      final headerBytes = int.parse(match!.group(1)!);
      final totalBytes = int.parse(match.group(2)!);

      expect(headerBytes, equals(12)); // 10 + 2 for final \r\nn
      expect(totalBytes, equals(13)); // 12 header + 1 payload
    });

    test('encode HPUB with empty headers and payload', () {
      final payload = Uint8List(0);
      final headers = <String, String>{};
      final result =
          NatsEncoder.hpub('test.subject', payload, headers: headers);

      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('NATS/1.0\r\n'));
      expect(resultStr,
          contains('\r\n\r\n\r\n')); // end of headers and empty payload
    });
  });

  group('SUB/UNSUB encoding', () {
    test('encode SUB without queue group', () {
      final result = NatsEncoder.sub('test.*', 'sid1');
      expect(String.fromCharCodes(result), equals('SUB test.* sid1\r\n'));
    });

    test('encode SUB with queue group', () {
      final result = NatsEncoder.sub('test.*', 'sid1', queueGroup: 'workers');
      expect(
        String.fromCharCodes(result),
        equals('SUB test.* workers sid1\r\n'),
      );
    });
  });

  group('CONNECT/CMD encoding', () {
    test('encode PING', () {
      final result = NatsEncoder.ping();
      expect(String.fromCharCodes(result), equals('PING\r\n'));
    });

    test('encode PONG', () {
      final result = NatsEncoder.pong();
      expect(String.fromCharCodes(result), equals('PONG\r\n'));
    });

    test('encode CONNECT with basic params', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, startsWith('CONNECT '));
      expect(resultStr, contains('"version":"0.1.0"'));
      expect(resultStr, contains('"lang":"dart"'));
      expect(resultStr, contains('"headers":true'));
      expect(resultStr, endsWith('\r\n'));
    });

    test('encode CONNECT with auth token', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        token: 'my-token',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('"auth_token":"my-token"'));
    });

    test('encode CONNECT with user/password', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        user: 'alice',
        pass: 'secret',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('"user":"alice"'));
      expect(resultStr, contains('"pass":"secret"'));
    });
  });

  group('UNSUB encoding', () {
    test('encode UNSUB without max messages', () {
      final result = NatsEncoder.unsub('sid1');
      expect(String.fromCharCodes(result), equals('UNSUB sid1\r\n'));
    });

    test('encode UNSUB with max messages', () {
      final result = NatsEncoder.unsub('sid1', maxMsgs: 100);
      expect(String.fromCharCodes(result), equals('UNSUB sid1 100\r\n'));
    });
  });
}
