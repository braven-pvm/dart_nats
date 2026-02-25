import 'dart:convert';
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
      final replyTo = 'inbox.123';
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

  group('HPUB encoding - reference implementations', () {
    test('reference: HPUB with dedup header from NATS spec', () {
      final payload =
          Uint8List.fromList('{\"power\":285,\"hr\":148}'.codeUnits);
      final headers = {'Nats-Msg-Id': 'session-42-001'};
      final replyTo = '_INBOX.abc123';
      final result = NatsEncoder.hpub(
        'TESTS.session_1',
        payload,
        replyTo: replyTo,
        headers: headers,
      );

      final resultStr = utf8.decode(result);

      final match = RegExp(r'HPUB TESTS\.session_1 _INBOX\.abc123 (\d+) (\d+)')
          .firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);
      final totalBytes = int.parse(match.group(2)!);

      final headerBytesOnWire =
          utf8.encode('NATS/1.0\r\nNats-Msg-Id: session-42-001\r\n\r\n').length;

      expect(hdrBytes, equals(headerBytesOnWire),
          reason: 'hdrBytes should match header section length');
      expect(totalBytes, equals(hdrBytes + payload.length),
          reason: 'totalBytes should be hdrBytes + payload length');

      expect(
          resultStr, contains('NATS/1.0\r\nNats-Msg-Id: session-42-001\r\n'));
    });

    test('reference: HPUB with multi-value header from architecture doc', () {
      final payload = Uint8List.fromList('Yum!'.codeUnits);
      final headers = <String, List<String>>{
        'BREAKFAST': ['donut', 'eggs'],
      };
      final result = NatsEncoder.hpub(
        'MORNING.MENU',
        payload,
        headers: headers,
      );

      final resultStr = utf8.decode(result);

      final match =
          RegExp(r'HPUB MORNING\.MENU (\d+) (\d+)').firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);
      final totalBytes = int.parse(match.group(2)!);

      final expectedHeaderSection =
          'NATS/1.0\r\nBREAKFAST: donut\r\nBREAKFAST: eggs\r\n\r\n';
      final headerBytesOnWire = expectedHeaderSection.codeUnits.length;

      expect(hdrBytes, equals(headerBytesOnWire),
          reason: 'hdrBytes should match header section length');
      expect(totalBytes, equals(hdrBytes + payload.length),
          reason: 'totalBytes should be hdrBytes + payload length');

      expect(resultStr, contains('BREAKFAST: donut\r\n'));
      expect(resultStr, contains('BREAKFAST: eggs\r\n'));
    });

    test('reference: HPUB header-only (no payload)', () {
      final payload = Uint8List(0);
      final headers = {'Bar': 'Baz'};
      final result = NatsEncoder.hpub('NOTIFY', payload, headers: headers);

      final resultStr = utf8.decode(result);

      final match = RegExp(r'HPUB NOTIFY (\d+) (\d+)').firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);
      final totalBytes = int.parse(match.group(2)!);

      final expectedHeaderSection = 'NATS/1.0\r\nBar: Baz\r\n\r\n';
      final headerBytesOnWire = expectedHeaderSection.codeUnits.length;

      expect(hdrBytes, equals(headerBytesOnWire),
          reason: 'hdrBytes should be 22');
      expect(totalBytes, equals(hdrBytes),
          reason: 'totalBytes should equal hdrBytes for empty payload');
      expect(resultStr, contains('NATS/1.0\r\nBar: Baz\r\n\r\n'));
    });

    test('byte-perfect: verify header section length matches hdrBytes', () {
      final payload = Uint8List.fromList('test payload'.codeUnits);
      final headers = {
        'Content-Type': 'application/json',
        'X-Custom': 'value123',
      };
      final result =
          NatsEncoder.hpub('subject.test', payload, headers: headers);

      final resultStr = utf8.decode(result);

      final headerStart = resultStr.indexOf('\r\n') + 2;
      final payloadStart = resultStr.indexOf('\r\n\r\n') + 4;

      final actualHeaderSection =
          resultStr.substring(headerStart, payloadStart);
      final actualHeaderBytes = actualHeaderSection.codeUnits.length;

      final match = RegExp(r'HPUB subject\.test (\d+)').firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);

      expect(hdrBytes, equals(actualHeaderBytes));
    });

    test('byte-perfect: verify totalBytes = hdrBytes + payload.length', () {
      final payload = Uint8List.fromList('data'.codeUnits);
      final headers = {'Key': 'Value'};
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);

      final match = RegExp(r'HPUB test (\d+) (\d+)').firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);
      final totalBytes = int.parse(match.group(2)!);

      expect(totalBytes, equals(hdrBytes + payload.length));
    });
  });

  group('HPUB encoding - multi-value headers', () {
    test('encode HPUB with multi-value header (List<String>)', () {
      final payload = Uint8List.fromList('Data'.codeUnits);
      final headers = <String, List<String>>{
        'Accept': ['application/json', 'text/plain'],
        'X-RateLimit': ['100', '60'],
      };
      final result =
          NatsEncoder.hpub('test.subject', payload, headers: headers);

      final resultStr = utf8.decode(result);

      expect(resultStr, contains('Accept: application/json\r\n'));
      expect(resultStr, contains('Accept: text/plain\r\n'));
      expect(resultStr, contains('X-RateLimit: 100\r\n'));
      expect(resultStr, contains('X-RateLimit: 60\r\n'));
    });

    test('encode HPUB with mixed single and multi-value headers', () {
      final payload = Uint8List.fromList('Mixed'.codeUnits);
      final headers = <String, dynamic>{
        'Single': 'value',
        'Multi': ['first', 'second', 'third'],
      };
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);

      expect(resultStr, contains('Single: value\r\n'));
      expect(resultStr, contains('Multi: first\r\n'));
      expect(resultStr, contains('Multi: second\r\n'));
      expect(resultStr, contains('Multi: third\r\n'));
    });

    test('multi-value header byte counting is accurate', () {
      final payload = Uint8List.fromList('X'.codeUnits);
      final headers = <String, List<String>>{
        'Key1': ['val1', 'val2'],
      };
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);
      final match = RegExp(r'HPUB test (\d+) (\d+)').firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);

      final expectedHeader = 'NATS/1.0\r\nKey1: val1\r\nKey1: val2\r\n\r\n';
      final expectedBytes = expectedHeader.codeUnits.length;

      expect(hdrBytes, equals(expectedBytes));
    });
  });

  group('HPUB encoding - JetStream headers', () {
    test('HPUB with Nats-Msg-Id for deduplication', () {
      final payload = Uint8List.fromList('session data'.codeUnits);
      final headers = {'Nats-Msg-Id': 'session-42-001'};
      final result = NatsEncoder.hpub('SESSIONS', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('Nats-Msg-Id: session-42-001\r\n'));
    });

    test('HPUB with Nats-Expected-Stream for optimistic concurrency', () {
      final payload = Uint8List.fromList('event'.codeUnits);
      final headers = {'Nats-Expected-Stream': 'EVENTS'};
      final result = NatsEncoder.hpub('events', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('Nats-Expected-Stream: EVENTS\r\n'));
    });

    test('HPUB with Nats-Expected-Last-Msg-Id for KV concurrency', () {
      final payload = Uint8List.fromList('\"new value\"'.codeUnits);
      final headers = {
        'Nats-Expected-Last-Msg-Id': 'kv-001',
      };
      final result = NatsEncoder.hpub('KV.BR.TEST', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('Nats-Expected-Last-Msg-Id: kv-001\r\n'));
    });

    test('HPUB with KV-Operation: DEL header', () {
      final payload = Uint8List(0);
      final headers = {'KV-Operation': 'DEL'};
      final result = NatsEncoder.hpub('KV.TEST.key', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('KV-Operation: DEL\r\n'));
    });
  });

  group('HPUB encoding - edge cases', () {
    test('HPUB with empty headers and empty payload', () {
      final payload = Uint8List(0);
      final result = NatsEncoder.hpub('test', payload);

      final resultStr = utf8.decode(result);

      final match = RegExp(r'HPUB test (\d+) (\d+)').firstMatch(resultStr)!;
      final hdrBytes = int.parse(match.group(1)!);

      // NATS/1.0\r\n = 10 bytes, plus blank line \r\n = 2 bytes
      expect(hdrBytes, equals(12),
          reason:
              'Empty header section should be 12 bytes (NATS/1.0 + blank line)');
      expect(resultStr, contains('NATS/1.0\r\n\r\n'));
    });

    test('HPUB with custom headers', () {
      final payload = Uint8List.fromList('Message'.codeUnits);
      final headers = {
        'Content-Type': 'application/json',
        'X-Request-Id': 'abc123',
      };
      final result =
          NatsEncoder.hpub('test.subject', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('Content-Type: application/json\r\n'));
      expect(resultStr, contains('X-Request-Id: abc123\r\n'));
    });

    test('HPUB with headers and reply-to', () {
      final payload = Uint8List.fromList('Data'.codeUnits);
      final headers = {'Key': 'Value'};
      final replyTo = 'reply.subject';
      final result = NatsEncoder.hpub(
        'test.subject',
        payload,
        replyTo: replyTo,
        headers: headers,
      );

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('NATS/1.0\r\n'));
      expect(resultStr, contains('Key: Value\r\n'));
    });

    test('HPUB with header value containing colons', () {
      final payload = Uint8List.fromList('test'.codeUnits);
      final headers = {
        'Time': '12:30:45',
        'URL': 'http://example.com:8080',
      };
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('Time: 12:30:45\r\n'));
      expect(resultStr, contains('URL: http://example.com:8080\r\n'));
    });

    test('HPUB with Unicode in header values', () {
      final payload = Uint8List.fromList('data'.codeUnits);
      final headers = {
        'User': 'José',
        'Location': 'Москва',
      };
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('User: José\r\n'));
      expect(resultStr, contains('Location: Москва\r\n'));
    });

    test('HPUB with many header keys', () {
      final headers = <String, String>{};
      for (int i = 0; i < 10; i++) {
        headers['X-Header-$i'] = 'value-$i';
      }
      final payload = Uint8List.fromList('test'.codeUnits);
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);
      for (int i = 0; i < 10; i++) {
        expect(resultStr, contains('X-Header-$i: value-$i\r\n'));
      }
    });

    test('HPUB with empty header value (edge case)', () {
      final payload = Uint8List.fromList('data'.codeUnits);
      final headers = {'Empty-Header': ''};
      final result = NatsEncoder.hpub('test', payload, headers: headers);

      final resultStr = utf8.decode(result);
      expect(resultStr, contains('Empty-Header: \r\n'));
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
      expect(resultStr, contains('\"version\":\"0.1.0\"'));
      expect(resultStr, contains('\"lang\":\"dart\"'));
      expect(resultStr, contains('\"headers\":true'));
      expect(resultStr, endsWith('\r\n'));
    });

    test('encode CONNECT with headers flag for JetStream', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        headers: true,
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('\"headers\":true'));
    });

    test('encode CONNECT with correct required fields', () {
      final result = NatsEncoder.connect(
        version: '1.0.0',
        lang: 'dart',
        verbose: false,
        pedantic: false,
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('\"verbose\":false'));
      expect(resultStr, contains('\"pedantic\":false'));
      expect(resultStr, contains('\"lang\":\"dart\"'));
      expect(resultStr, contains('\"version\":\"1.0.0\"'));
    });

    test('encode CONNECT with auth token', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        token: 'my-token',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('\"auth_token\":\"my-token\"'));
    });

    test('encode CONNECT with user/password', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        user: 'alice',
        pass: 'secret',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('\"user\":\"alice\"'));
      expect(resultStr, contains('\"pass\":\"secret\"'));
    });

    test('encode CONNECT with JWT/NKey auth', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        jwt: 'ey...',
        nkey: 'ABCDEF...',
        sig: 'signature...',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('\"jwt\":\"ey...\"'));
      expect(resultStr, contains('\"nkey\":\"ABCDEF...\"'));
      expect(resultStr, contains('\"sig\":\"signature...\"'));
    });

    test('encode CONNECT with name parameter', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        name: 'my-client',
      );
      final resultStr = String.fromCharCodes(result);
      expect(resultStr, contains('\"name\":\"my-client\"'),
          reason: 'CONNECT should include client name when provided');
    });

    test('encode CONNECT with noEcho=true sends no_echo field', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        noEcho: true,
      );
      final resultStr = String.fromCharCodes(result);
      // noEcho=true maps to 'no_echo':true in the NATS wire protocol.
      // When no_echo is true the server suppresses echo of own-published messages.
      expect(resultStr, contains('\"no_echo\":true'),
          reason: 'noEcho=true should emit no_echo:true in CONNECT JSON');
    });

    test('encode CONNECT with noEcho=false omits no_echo field', () {
      final result = NatsEncoder.connect(
        version: '0.1.0',
        lang: 'dart',
        noEcho: false,
      );
      final resultStr = String.fromCharCodes(result);
      // noEcho=false (default) — field is omitted to keep CONNECT minimal.
      expect(resultStr, isNot(contains('no_echo')),
          reason:
              'noEcho=false (default) should not include no_echo in CONNECT JSON');
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

  group('Binary payload handling', () {
    test('PUB with binary payload containing null bytes', () {
      final payload = Uint8List.fromList([0x00, 0x01, 0x02, 0xFF, 0xFE]);
      final result = NatsEncoder.pub('binary', payload);

      final resultStr = String.fromCharCodes(
          result.sublist(0, 14)); // Only decode command portion
      expect(resultStr, startsWith('PUB binary 5\r\n'));
      expect(result.length, equals('PUB binary 5\r\n'.length + 5 + 2));
    });

    test('HPUB with binary payload', () {
      final payload = Uint8List.fromList([0x00, 0xFF, 0x80, 0x7F]);
      final result = NatsEncoder.hpub('binary', payload);

      final resultBytes = Uint8List.fromList(result);
      final payloadStart = resultBytes.length - 2 - 4;
      final payloadBytes = resultBytes.sublist(payloadStart, payloadStart + 4);

      expect(payloadBytes[0], equals(0x00));
      expect(payloadBytes[1], equals(0xFF));
      expect(payloadBytes[2], equals(0x80));
      expect(payloadBytes[3], equals(0x7F));
    });
  });
}
