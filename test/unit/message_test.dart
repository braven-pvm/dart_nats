import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/protocol/message.dart';

void main() {
  group('NatsMessage construction', () {
    test('construct with all fields', () {
      final payload = Uint8List.fromList('Hello'.codeUnits);
      const headers = {
        'Content-Type': ['text/plain']
      };

      final msg = NatsMessage(
        subject: 'test.subject',
        sid: '123',
        replyTo: 'reply.subject',
        payload: payload,
        headers: headers,
        statusCode: 200,
        statusDesc: 'OK',
        type: MessageType.msg,
      );

      expect(msg.subject, equals('test.subject'));
      expect(msg.sid, equals('123'));
      expect(msg.replyTo, equals('reply.subject'));
      expect(msg.payload, equals(payload));
      expect(msg.headers, equals(headers));
      expect(msg.statusCode, equals(200));
      expect(msg.statusDesc, equals('OK'));
      expect(msg.type, equals(MessageType.msg));
    });

    test('construct with minimal fields', () {
      final msg = NatsMessage(
        subject: 'test.subject',
        sid: '123',
      );

      expect(msg.subject, equals('test.subject'));
      expect(msg.sid, equals('123'));
      expect(msg.replyTo, isNull);
      expect(msg.payload, isNull);
      expect(msg.headers, isNull);
      expect(msg.statusCode, isNull);
      expect(msg.statusDesc, isNull);
      expect(msg.type, equals(MessageType.msg)); // default
    });

    test('default type is MessageType.msg', () {
      final msg = NatsMessage(subject: 'test', sid: '1');
      expect(msg.type, equals(MessageType.msg));
    });
  });

  group('Status getters', () {
    test('isFlowCtrl true when statusCode=100 and desc contains "Flow"', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'FlowControl',
      );
      expect(msg.isFlowCtrl, isTrue);
      expect(msg.isHeartbeat, isFalse);
    });

    test('isFlowCtrl false when statusCode != 100', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'FlowControl',
      );
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isFlowCtrl false when desc does not contain "Flow"', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Something else',
      );
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isFlowCtrl false when statusCode is null', () {
      final msg = NatsMessage(
        statusDesc: 'FlowControl',
      );
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isHeartbeat true when statusCode=100 and desc contains "Idle"', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Idle Heartbeat',
      );
      expect(msg.isHeartbeat, isTrue);
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isHeartbeat false when statusCode != 100', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'Idle',
      );
      expect(msg.isHeartbeat, isFalse);
    });

    test('isHeartbeat false when desc does not contain "Idle"', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Something else',
      );
      expect(msg.isHeartbeat, isFalse);
    });

    test('isNoMsg true when statusCode=404', () {
      final msg = NatsMessage(
        statusCode: 404,
        statusDesc: 'No Messages',
      );
      expect(msg.isNoMsg, isTrue);
    });

    test('isNoMsg false when statusCode != 404', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'No Messages',
      );
      expect(msg.isNoMsg, isFalse);
    });

    test('isTimeout true when statusCode=408', () {
      final msg = NatsMessage(
        statusCode: 408,
        statusDesc: 'Request Timeout',
      );
      expect(msg.isTimeout, isTrue);
    });

    test('isTimeout false when statusCode != 408', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'Timeout',
      );
      expect(msg.isTimeout, isFalse);
    });

    test(
        'isConsumerDeleted true when statusCode=409 and desc contains "Consumer Deleted"',
        () {
      final msg = NatsMessage(
        statusCode: 409,
        statusDesc: 'Consumer Deleted',
      );
      expect(msg.isConsumerDeleted, isTrue);
    });

    test('isConsumerDeleted false when statusCode != 409', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'Consumer Deleted',
      );
      expect(msg.isConsumerDeleted, isFalse);
    });
  });

  group('Header accessors', () {
    test('header returns null when no headers', () {
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: null,
      );

      expect(msg.header('Content-Type'), isNull);
    });

    test('header returns null when header not found', () {
      const headers = {
        'Content-Type': ['text/plain']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.header('X-Custom-Header'), isNull);
    });

    test('header returns first value case-insensitively', () {
      const headers = {
        'Content-Type': ['text/plain'],
        'X-Custom': ['value1', 'value2'],
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      // Exact match
      expect(msg.header('Content-Type'), equals('text/plain'));

      // Case-insensitive match
      expect(msg.header('content-type'), equals('text/plain'));
      expect(msg.header('CONTENT-TYPE'), equals('text/plain'));
      expect(msg.header('content-type'), equals('text/plain'));
    });

    test('header returns null when header has empty list', () {
      const headers = {'Content-Type': <String>[]};
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.header('Content-Type'), isNull);
    });

    test('headerAll returns null when no headers', () {
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: null,
      );

      expect(msg.headerAll('Content-Type'), isNull);
    });

    test('headerAll returns null when header not found', () {
      const headers = {
        'Content-Type': ['text/plain']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.headerAll('X-Custom-Header'), isNull);
    });

    test('headerAll returns all values case-insensitively', () {
      const headers = {
        'X-Custom': ['value1', 'value2', 'value3'],
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.headerAll('X-Custom'), equals(['value1', 'value2', 'value3']));
      expect(msg.headerAll('x-custom'), equals(['value1', 'value2', 'value3']));
      expect(msg.headerAll('X-CUSTOM'), equals(['value1', 'value2', 'value3']));
    });

    test('headerAll returns list with single value', () {
      const headers = {
        'Content-Type': ['text/plain']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.headerAll('Content-Type'), equals(['text/plain']));
    });
  });

  group('Factory constructors', () {
    test('info factory stores JSON as payload bytes', () {
      final infoJson = '{"server_id":"test"}';
      final msg = NatsMessage.info(infoJson);

      expect(msg.type, equals(MessageType.info));
      expect(msg.payload, isNotNull);
      expect(msg.payload, equals(Uint8List.fromList(infoJson.codeUnits)));
      expect(String.fromCharCodes(msg.payload!), equals(infoJson));
    });

    test('ping factory sets correct type', () {
      final msg = NatsMessage.ping();

      expect(msg.type, equals(MessageType.ping));
    });

    test('pong factory sets correct type', () {
      final msg = NatsMessage.pong();

      expect(msg.type, equals(MessageType.pong));
    });

    test('ok factory sets correct type', () {
      final msg = NatsMessage.ok();

      expect(msg.type, equals(MessageType.ok));
    });

    test('err factory stores message in statusDesc', () {
      const errorMsg = 'Invalid subscription';
      final msg = NatsMessage.err(errorMsg);

      expect(msg.type, equals(MessageType.err));
      expect(msg.statusDesc, equals(errorMsg));
    });
  });

  group('MessageType enum', () {
    test('MessageType has all expected values', () {
      expect(MessageType.msg, isNotNull);
      expect(MessageType.hmsg, isNotNull);
      expect(MessageType.info, isNotNull);
      expect(MessageType.ping, isNotNull);
      expect(MessageType.pong, isNotNull);
      expect(MessageType.ok, isNotNull);
      expect(MessageType.err, isNotNull);
    });
  });

  group('toString', () {
    test('toString includes subject and type', () {
      final msg = NatsMessage(
        subject: 'test.subject',
        sid: '123',
      );

      final str = msg.toString();
      expect(str, contains('test.subject'));
      expect(str, contains('MessageType.msg'));
    });

    test('toString includes statusCode when present', () {
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        statusCode: 408,
      );

      final str = msg.toString();
      expect(str, contains('408'));
    });

    test('toString handles null statusCode', () {
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
      );

      final str = msg.toString();
      expect(str, contains('statusCode=null'));
    });
  });

  group('Combined status scenarios', () {
    test('message can be both flow control and have proper statusCode', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Flow Control Request',
      );

      expect(msg.statusCode, equals(100));
      expect(msg.isFlowCtrl, isTrue);
      expect(msg.isHeartbeat, isFalse);
    });

    test('message can be both heartbeat and have proper statusCode', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Idle Heartbeat',
      );

      expect(msg.statusCode, equals(100));
      expect(msg.isHeartbeat, isTrue);
      expect(msg.isFlowCtrl, isFalse);
    });
  });
}
