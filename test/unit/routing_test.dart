import 'dart:async';

import 'package:test/test.dart';
import 'package:nats_dart/src/client/connection.dart';
import 'package:nats_dart/src/client/subscription.dart';
import 'package:nats_dart/src/protocol/message.dart';

void main() {
  group('matchesSubject - exact match', () {
    test('identical pattern and subject match', () {
      expect(matchesSubject('foo.bar', 'foo.bar'), isTrue);
    });

    test('different patterns do not match', () {
      expect(matchesSubject('foo.bar', 'foo.baz'), isFalse);
    });

    test('single token exact match', () {
      expect(matchesSubject('foo', 'foo'), isTrue);
    });

    test('single token mismatch', () {
      expect(matchesSubject('foo', 'bar'), isFalse);
    });

    test('multi-token exact match', () {
      expect(matchesSubject('a.b.c.d', 'a.b.c.d'), isTrue);
    });

    test('multi-token with different length', () {
      expect(matchesSubject('a.b', 'a.b.c'), isFalse);
    });
  });

  group('matchesSubject - single token wildcard (*)', () {
    test('* matches single token at end', () {
      expect(matchesSubject('foo.*', 'foo.bar'), isTrue);
    });

    test('* matches single token in middle', () {
      expect(matchesSubject('foo.*.baz', 'foo.bar.baz'), isTrue);
    });

    test('* does NOT match multiple tokens', () {
      expect(matchesSubject('foo.*', 'foo.bar.baz'), isFalse);
    });

    test('* does NOT match zero tokens', () {
      expect(matchesSubject('foo.*', 'foo'), isFalse);
    });

    test('multiple * wildcards work correctly', () {
      expect(matchesSubject('*.*', 'foo.bar'), isTrue);
      expect(matchesSubject('*.*.*', 'foo.bar.baz'), isTrue);
    });

    test('* wildcard in various positions', () {
      expect(matchesSubject('*.bar', 'foo.bar'), isTrue);
      expect(matchesSubject('*.bar.baz', 'foo.bar.baz'), isTrue);
      expect(matchesSubject('*.*.baz', 'foo.bar.baz'), isTrue);
    });

    test('* with different token counts fails', () {
      expect(matchesSubject('foo.*.baz', 'foo.x.y.z'), isFalse);
    });
  });

  group('matchesSubject - multi-token wildcard (>)', () {
    test('> matches single trailing token', () {
      expect(matchesSubject('foo.>', 'foo.bar'), isTrue);
    });

    test('> matches multiple trailing tokens', () {
      expect(matchesSubject('foo.>', 'foo.bar.baz'), isTrue);
      expect(matchesSubject('foo.>', 'foo.a.b.c.d'), isTrue);
    });

    test('> does NOT match the prefix alone', () {
      expect(matchesSubject('foo.>', 'foo'), isFalse);
    });

    test('> must be the last token in pattern', () {
      // Invalid pattern: > must be last
      expect(matchesSubject('>.bar', 'foo.bar'), isFalse);
    });

    test('> at beginning matches any subject with at least one token', () {
      expect(matchesSubject('>', 'foo'), isTrue);
      expect(matchesSubject('>', 'foo.bar'), isTrue);
      expect(matchesSubject('>', 'a.b.c.d.e'), isTrue);
    });

    test('combination of prefix and >', () {
      expect(matchesSubject('a.b.>', 'a.b.c'), isTrue);
      expect(matchesSubject('a.b.>', 'a.b.c.d'), isTrue);
      expect(matchesSubject('a.b.>', 'a.b'), isFalse);
      expect(matchesSubject('a.b.>', 'a.x.c'), isFalse);
    });
  });

  group('matchesSubject - edge cases', () {
    test('no wildcards returns false for non-exact match', () {
      expect(matchesSubject('foo.bar', 'foo.baz'), isFalse);
    });

    test('empty pattern and subject', () {
      expect(matchesSubject('', ''), isTrue);
    });

    test('pattern with > and no dots', () {
      expect(matchesSubject('>', 'foo'), isTrue);
    });

    test('pattern ending with > matches any depth', () {
      expect(matchesSubject('app.>', 'app.events.user.created'), isTrue);
      expect(matchesSubject('app.>', 'app.logs'), isTrue);
    });

    test('complex real-world patterns', () {
      // Common NATS patterns
      expect(matchesSubject('_INBOX.>', '_INBOX.abc123'), isTrue);
      expect(matchesSubject('_INBOX.>', '_INBOX.xyz.456'), isTrue);
      expect(matchesSubject('*.events', 'user.events'), isTrue);
      expect(matchesSubject('*.events', 'order.events'), isTrue);
      expect(matchesSubject('*.events', 'user.events.extra'), isFalse);
    });
  });

  group('Subscription - auto-unsub with maxMsgs', () {
    test('Subscription.owned accepts maxMsgs parameter', () {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
        maxMsgs: 5,
      );

      expect(sub.sid, equals('test-sid'));
      expect(sub.subject, equals('test.subject'));
      expect(sub.isActive, isTrue);
    });

    test('messages are delivered up to max count', () async {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
        maxMsgs: 3,
      );

      final msg1 = NatsMessage(subject: 'test.subject', sid: 'test-sid');
      final msg2 = NatsMessage(subject: 'test.subject', sid: 'test-sid');
      final msg3 = NatsMessage(subject: 'test.subject', sid: 'test-sid');

      // Set up listener first
      final receivedFuture = sub.messages.take(3).toList();

      sub.addMessage(msg1);
      sub.addMessage(msg2);
      sub.addMessage(msg3);

      final received = await receivedFuture;
      expect(received.length, equals(3));
    });
    test('stream closes after max messages reached', () async {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
        maxMsgs: 2,
      );

      final msg1 = NatsMessage(subject: 'test.subject', sid: 'test-sid');
      final msg2 = NatsMessage(subject: 'test.subject', sid: 'test-sid');

      sub.addMessage(msg1);
      sub.addMessage(msg2);

      // Wait for messages to be processed
      await Future<void>.delayed(Duration(milliseconds: 10));
      // Stream should be closed
      expect(sub.isActive, isFalse);
    });
    test('messages beyond max are not delivered', () async {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
        maxMsgs: 2,
      );

      final msg1 = NatsMessage(subject: 'test.subject', sid: 'test-sid');
      final msg2 = NatsMessage(subject: 'test.subject', sid: 'test-sid');
      final msg3 = NatsMessage(subject: 'test.subject', sid: 'test-sid');

      // Set up listener first - request more than will arrive
      final receivedFuture = sub.messages.take(3).toList().timeout(
            Duration(milliseconds: 100),
            onTimeout: () => <NatsMessage>[],
          );

      sub.addMessage(msg1);
      sub.addMessage(msg2);
      sub.addMessage(msg3); // Should not be delivered

      final received = await receivedFuture;

      expect(received.length, equals(2));
    });
    test('no maxMsgs means no auto-unsubscribe', () {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
      );

      final msg1 = NatsMessage(subject: 'test.subject', sid: 'test-sid');
      final msg2 = NatsMessage(subject: 'test.subject', sid: 'test-sid');

      sub.addMessage(msg1);
      sub.addMessage(msg2);

      expect(sub.isActive, isTrue);
    });
  });

  group('Subscription - queue group handling', () {
    test('Subscription.owned stores queueGroup correctly', () {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
        queueGroup: 'workers',
      );

      expect(sub.queueGroup, equals('workers'));
    });

    test('Subscription.owned without queueGroup is null', () {
      final sub = Subscription.owned(
        sid: 'test-sid',
        subject: 'test.subject',
      );

      expect(sub.queueGroup, isNull);
    });

    test('multiple subscriptions can have same queue group', () {
      final sub1 = Subscription.owned(
        sid: 'sid1',
        subject: 'test.subject',
        queueGroup: 'workers',
      );

      final sub2 = Subscription.owned(
        sid: 'sid2',
        subject: 'test.subject',
        queueGroup: 'workers',
      );

      expect(sub1.queueGroup, equals('workers'));
      expect(sub2.queueGroup, equals('workers'));
    });

    test('different subjects with same queue group', () {
      final sub1 = Subscription.owned(
        sid: 'sid1',
        subject: 'orders.created',
        queueGroup: 'order-processor',
      );

      final sub2 = Subscription.owned(
        sid: 'sid2',
        subject: 'orders.updated',
        queueGroup: 'order-processor',
      );

      expect(sub1.queueGroup, equals('order-processor'));
      expect(sub2.queueGroup, equals('order-processor'));
    });
  });

  group('NatsMessage - status code getters', () {
    test('isFlowCtrl returns true for statusCode 100 with Flow in desc', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Flow Control Request',
      );
      expect(msg.isFlowCtrl, isTrue);
    });

    test('isFlowCtrl returns true for statusDesc containing Flow only', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Flow',
      );
      expect(msg.isFlowCtrl, isTrue);
    });

    test('isFlowCtrl returns false for other status codes', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'Flow Control',
      );
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isFlowCtrl returns false when statusDesc does not contain Flow', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Something Else',
      );
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isFlowCtrl returns false when statusCode is null', () {
      final msg = NatsMessage(
        statusDesc: 'Flow Control',
      );
      expect(msg.isFlowCtrl, isFalse);
    });

    test('isHeartbeat returns true for statusCode 100 with Idle in desc', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Idle Heartbeat',
      );
      expect(msg.isHeartbeat, isTrue);
    });

    test('isHeartbeat returns true for statusDesc containing Idle only', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Idle',
      );
      expect(msg.isHeartbeat, isTrue);
    });

    test('isHeartbeat returns false for other status codes', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'Idle Heartbeat',
      );
      expect(msg.isHeartbeat, isFalse);
    });

    test('isHeartbeat returns false when statusDesc does not contain Idle', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Something Else',
      );
      expect(msg.isHeartbeat, isFalse);
    });

    test('isHeartbeat returns false when statusCode is null', () {
      final msg = NatsMessage(
        statusDesc: 'Idle Heartbeat',
      );
      expect(msg.isHeartbeat, isFalse);
    });

    test('isNoMsg returns true for statusCode 404', () {
      final msg = NatsMessage(
        statusCode: 404,
        statusDesc: 'No Messages',
      );
      expect(msg.isNoMsg, isTrue);
    });

    test('isNoMsg returns false for other status codes', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'No Messages',
      );
      expect(msg.isNoMsg, isFalse);
    });

    test('isNoMsg returns false when statusCode is null', () {
      final msg = NatsMessage(
        statusDesc: 'No Messages',
      );
      expect(msg.isNoMsg, isFalse);
    });

    test('isTimeout returns true for statusCode 408', () {
      final msg = NatsMessage(
        statusCode: 408,
        statusDesc: 'Request Timeout',
      );
      expect(msg.isTimeout, isTrue);
    });

    test('isTimeout returns false for other status codes', () {
      final msg = NatsMessage(
        statusCode: 200,
        statusDesc: 'Request Timeout',
      );
      expect(msg.isTimeout, isFalse);
    });

    test('isTimeout returns false when statusCode is null', () {
      final msg = NatsMessage(
        statusDesc: 'Request Timeout',
      );
      expect(msg.isTimeout, isFalse);
    });

    test('100 Flow is flow ctrl but not heartbeat', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Flow Control',
      );
      expect(msg.isFlowCtrl, isTrue);
      expect(msg.isHeartbeat, isFalse);
    });

    test('100 Idle is heartbeat but not flow ctrl', () {
      final msg = NatsMessage(
        statusCode: 100,
        statusDesc: 'Idle Heartbeat',
      );
      expect(msg.isHeartbeat, isTrue);
      expect(msg.isFlowCtrl, isFalse);
    });

    test('other status codes are not special', () {
      final msg = NatsMessage(
        statusCode: 409,
        statusDesc: 'Consumer Deleted',
      );
      expect(msg.isFlowCtrl, isFalse);
      expect(msg.isHeartbeat, isFalse);
      expect(msg.isNoMsg, isFalse);
      expect(msg.isTimeout, isFalse);
    });
  });

  group('NatsMessage - header accessors', () {
    test('header returns value with exact match', () {
      const headers = {
        'Content-Type': ['text/plain']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.header('Content-Type'), equals('text/plain'));
    });

    test('header is case-insensitive', () {
      const headers = {
        'Content-Type': ['text/plain']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.header('content-type'), equals('text/plain'));
      expect(msg.header('CONTENT-TYPE'), equals('text/plain'));
      expect(msg.header('content-TYPE'), equals('text/plain'));
    });

    test('header returns first value for multi-value header', () {
      const headers = {
        'X-Custom': ['value1', 'value2', 'value3']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.header('X-Custom'), equals('value1'));
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

      expect(msg.header('X-Not-Found'), isNull);
    });

    test('header returns null when no headers', () {
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
      );

      expect(msg.header('Content-Type'), isNull);
    });

    test('header returns null when header value list is empty', () {
      const headers = {'Content-Type': <String>[]};
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.header('Content-Type'), isNull);
    });

    test('headerAll returns all values with exact match', () {
      const headers = {
        'X-Custom': ['value1', 'value2', 'value3']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.headerAll('X-Custom'), equals(['value1', 'value2', 'value3']));
    });

    test('headerAll is case-insensitive', () {
      const headers = {
        'X-Custom': ['value1', 'value2']
      };
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
        headers: headers,
      );

      expect(msg.headerAll('x-custom'), equals(['value1', 'value2']));
      expect(msg.headerAll('X-CUSTOM'), equals(['value1', 'value2']));
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

      expect(msg.headerAll('X-Not-Found'), isNull);
    });

    test('headerAll returns null when no headers', () {
      final msg = NatsMessage(
        subject: 'test',
        sid: '1',
      );

      expect(msg.headerAll('Content-Type'), isNull);
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
}
