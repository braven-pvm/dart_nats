import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/protocol/message.dart';
import 'package:nats_dart/src/protocol/parser.dart';

void main() {
  group('MSG parsing', () {
    test('parse MSG without reply-to', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList('MSG subject 1 5\r\nHello\r\n'.codeUnits),
      );

      final msg = await msgFuture;
      expect(msg.subject, equals('subject'));
      expect(msg.sid, equals('1'));
      expect(msg.replyTo, isNull);
      expect(msg.type, equals(MessageType.msg));
      expect(String.fromCharCodes(msg.payload!), equals('Hello'));
      parser.close();
    });

    test('parse MSG with reply-to', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'MSG subject 2 reply.inbox 12\r\nHello, NATS!\r\n'.codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.subject, equals('subject'));
      expect(msg.sid, equals('2'));
      expect(msg.replyTo, equals('reply.inbox'));
      expect(String.fromCharCodes(msg.payload!), equals('Hello, NATS!'));
      parser.close();
    });

    test('parse MSG with empty payload', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList('MSG empty.sid 3 0\r\n\r\n'.codeUnits),
      );

      final msg = await msgFuture;
      expect(msg.subject, equals('empty.sid'));
      expect(msg.payload, isEmpty);
      parser.close();
    });

    test('parse multiple MSG commands in sequence', () async {
      final parser = NatsParser();
      final future = parser.messages.take(2).toList();

      parser.addBytes(
        Uint8List.fromList(
          'MSG subj1 1 5\r\nHello\r\nMSG subj2 2 5\r\nWorld\r\n'.codeUnits,
        ),
      );

      final messages = await future;
      expect(messages, hasLength(2));
      expect(messages[0].subject, equals('subj1'));
      expect(messages[1].subject, equals('subj2'));
      parser.close();
    });
  });

  group('HMSG parsing', () {
    test('parse HMSG with headers without status', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid1 12 13\r\n'
                  'NATS/1.0\r\n'
                  '\r\n'
                  'X\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.subject, equals('subj'));
      expect(msg.sid, equals('sid1'));
      expect(msg.type, equals(MessageType.hmsg));
      expect(msg.statusCode, isNull);
      expect(msg.headers, isNotNull);
      expect(String.fromCharCodes(msg.payload!), equals('X'));
      parser.close();
    });

    test('parse HMSG with headers and status code', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid2 36 37\r\n'
                  'NATS/1.0 100 FlowControl Request\r\n'
                  '\r\n'
                  'D\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.statusCode, equals(100));
      expect(msg.statusDesc, equals('FlowControl Request'));
      expect(msg.isFlowCtrl, isTrue);
      expect(String.fromCharCodes(msg.payload!), equals('D'));
      parser.close();
    });

    test('parse HMSG with custom headers', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid3 66 77\r\n'
                  'NATS/1.0\r\n'
                  'Content-Type: application/json\r\n'
                  'X-Request-Id: abc123\r\n'
                  '\r\n'
                  'PayloadData\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.headers, isNotNull);
      expect(msg.header('Content-Type'), equals('application/json'));
      expect(msg.header('X-Request-Id'), equals('abc123'));
      expect(String.fromCharCodes(msg.payload!), equals('PayloadData'));
      parser.close();
    });

    test('parse HMSG with reply-to', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid4 reply.box 12 13\r\n'
                  'NATS/1.0\r\n'
                  '\r\n'
                  'X\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.replyTo, equals('reply.box'));
      parser.close();
    });

    test('resolve flow control status', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid 36 37\r\n'
                  'NATS/1.0 100 FlowControl Request\r\n'
                  '\r\n'
                  'X\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.isFlowCtrl, isTrue);
      expect(msg.isHeartbeat, isFalse);
      parser.close();
    });

    test('resolve idle heartbeat status', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid 31 32\r\n'
                  'NATS/1.0 100 Idle Heartbeat\r\n'
                  '\r\n'
                  'X\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.isHeartbeat, isTrue);
      expect(msg.isFlowCtrl, isFalse);
      parser.close();
    });

    test('resolve 404 no messages status', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid 16 17\r\n'
                  'NATS/1.0 404\r\n'
                  '\r\n'
                  'X\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.isNoMsg, isTrue);
      parser.close();
    });

    test('resolve 408 timeout status', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'HMSG subj sid 16 17\r\n'
                  'NATS/1.0 408\r\n'
                  '\r\n'
                  'X\r\n'
              .codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.isTimeout, isTrue);
      parser.close();
    });
  });

  group('partial frame handling', () {
    test('split MSG across multiple addBytes calls', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      // 'Hello, NATS!' is 12 bytes
      parser.addBytes(Uint8List.fromList('MSG subj 1 12\r\nHello'.codeUnits));
      parser.addBytes(Uint8List.fromList(', NATS!\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(String.fromCharCodes(msg.payload!), equals('Hello, NATS!'));
      parser.close();
    });

    test('handle incomplete multi-byte characters', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      // 'Hello' is 5 bytes
      parser.addBytes(Uint8List.fromList('MSG subj 1 5\r\nHel'.codeUnits));
      parser.addBytes(Uint8List.fromList('lo\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(String.fromCharCodes(msg.payload!), equals('Hello'));
      parser.close();
    });

    test('wait for complete HMSG with headers', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList('HMSG subj sid 12 13\r\nNATS/1.0\r\n'.codeUnits),
      );
      parser.addBytes(Uint8List.fromList('\r\nX\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.hmsg));
      expect(String.fromCharCodes(msg.payload!), equals('X'));
      parser.close();
    });
  });

  group('INFO parsing', () {
    test('parse INFO command', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList(
          'INFO {"server_id":"test","version":"2.10.0"}\r\n'.codeUnits,
        ),
      );

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.info));
      final payloadStr = String.fromCharCodes(msg.payload!);
      expect(payloadStr, contains('"server_id":"test"'));
      expect(payloadStr, contains('"version":"2.10.0"'));
      parser.close();
    });
  });

  group('PING/PONG parsing', () {
    test('parse PING', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(Uint8List.fromList('PING\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.ping));
      parser.close();
    });

    test('parse PONG', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(Uint8List.fromList('PONG\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.pong));
      parser.close();
    });

    test('parse multiple PING/PONG commands', () async {
      final parser = NatsParser();
      final future = parser.messages.take(3).toList();

      parser.addBytes(
        Uint8List.fromList('PING\r\nPONG\r\nPING\r\n'.codeUnits),
      );

      final messages = await future;
      expect(messages, hasLength(3));
      expect(messages[0].type, equals(MessageType.ping));
      expect(messages[1].type, equals(MessageType.pong));
      expect(messages[2].type, equals(MessageType.ping));
      parser.close();
    });
  });

  group('+OK and -ERR parsing', () {
    test('parse +OK', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(Uint8List.fromList('+OK\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.ok));
      parser.close();
    });

    test('parse -ERR with message', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList('-ERR Permissions Violation\r\n'.codeUnits),
      );

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.err));
      expect(msg.statusDesc, equals('Permissions Violation'));
      parser.close();
    });

    test('parse -ERR without message', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(Uint8List.fromList('-ERR\r\n'.codeUnits));

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.err));
      expect(msg.statusDesc, isEmpty);
      parser.close();
    });
  });

  group('error handling', () {
    test('skip unknown commands', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      parser.addBytes(
        Uint8List.fromList('UNKNOWN command\r\nPING\r\n'.codeUnits),
      );

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.ping));
      parser.close();
    });

    test('skip malformed MSG commands', () async {
      final parser = NatsParser();
      final msgFuture = parser.messages.first;

      // Missing payload size — parser should skip and still parse PING
      parser.addBytes(
        Uint8List.fromList('MSG subj sid\r\nPING\r\n'.codeUnits),
      );

      final msg = await msgFuture;
      expect(msg.type, equals(MessageType.ping));
      parser.close();
    });
  });

  group('mixed protocol commands', () {
    test('parse sequence of different message types', () async {
      final parser = NatsParser();
      final future = parser.messages.take(7).toList();

      parser.addBytes(
        Uint8List.fromList(
          'INFO {"server_id":"test"}\r\n'
                  'PING\r\n'
                  'PONG\r\n'
                  'MSG subj 1 4\r\nTest\r\n'
                  '+OK\r\n'
                  'HMSG subj2 sid2 12 13\r\nNATS/1.0\r\n\r\nX\r\n'
                  '-ERR Test error\r\n'
              .codeUnits,
        ),
      );

      final messages = await future;
      expect(messages, hasLength(7));
      expect(messages[0].type, equals(MessageType.info));
      expect(messages[1].type, equals(MessageType.ping));
      expect(messages[2].type, equals(MessageType.pong));
      expect(messages[3].type, equals(MessageType.msg));
      expect(messages[3].subject, equals('subj'));
      expect(messages[4].type, equals(MessageType.ok));
      expect(messages[5].type, equals(MessageType.hmsg));
      expect(messages[6].type, equals(MessageType.err));
      expect(messages[6].statusDesc, equals('Test error'));
      parser.close();
    });
  });
}
