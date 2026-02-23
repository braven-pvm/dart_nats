import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/client/subscription.dart';
import 'package:nats_dart/src/protocol/message.dart';

void main() {
  group('Subscription construction', () {
    test('construction requires sid, subject, and messages stream', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      expect(sub.sid, equals('123'));
      expect(sub.subject, equals('test.subject'));
      expect(sub.messages, isNotNull);
      expect(sub.queueGroup, isNull);

      controller.close();
    });

    test('construction fails without sid', () {
      final controller = StreamController<NatsMessage>();

      expect(
        () => Subscription(
          sid: '',
          subject: 'test.subject',
          messages: controller.stream,
        ),
        returnsNormally,
      ); // Empty sid is allowed

      controller.close();
    });

    test('construction with all fields including queueGroup', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        queueGroup: 'workers',
        messages: controller.stream,
      );

      expect(sub.sid, equals('123'));
      expect(sub.subject, equals('test.subject'));
      expect(sub.queueGroup, equals('workers'));
      expect(sub.messages, isNotNull);

      controller.close();
    });

    test('queueGroup defaults to null when not provided', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      expect(sub.queueGroup, isNull);

      controller.close();
    });

    test('messages stream is accessible', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      expect(sub.messages, isA<Stream<NatsMessage>>());

      controller.close();
    });
  });

  group('Subscription isActive', () {
    test('isActive is true after construction', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      expect(sub.isActive, isTrue);

      controller.close();
    });

    test('isActive is true initially for all subscriptions', () {
      final controller = StreamController<NatsMessage>();

      final sub1 = Subscription(
        sid: '1',
        subject: 'subject.1',
        messages: controller.stream,
      );

      final sub2 = Subscription(
        sid: '2',
        subject: 'subject.2',
        queueGroup: 'workers',
        messages: controller.stream,
      );

      expect(sub1.isActive, isTrue);
      expect(sub2.isActive, isTrue);

      controller.close();
    });
  });

  group('Subscription messages stream', () {
    test('messages stream yields submitted messages', () async {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      final msg = NatsMessage(
        subject: 'test.subject',
        sid: '123',
        payload: null,
      );

      final future = sub.messages.first;

      controller.add(msg);

      final received = await future;
      expect(received.subject, equals('test.subject'));
      expect(received.sid, equals('123'));

      await controller.close();
    });

    test('messages stream can receive multiple messages', () async {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      final msg1 = NatsMessage(subject: 'test.subject', sid: '123');
      final msg2 = NatsMessage(subject: 'test.subject', sid: '123');
      final msg3 = NatsMessage(subject: 'test.subject', sid: '123');

      final messagesFuture = sub.messages.take(3).toList();

      controller.add(msg1);
      controller.add(msg2);
      controller.add(msg3);

      final received = await messagesFuture;
      expect(received.length, equals(3));

      await controller.close();
    });

    test('messages stream from different subscriptions are independent',
        () async {
      final controller1 = StreamController<NatsMessage>();
      final controller2 = StreamController<NatsMessage>();

      final sub1 = Subscription(
        sid: '1',
        subject: 'subject.1',
        messages: controller1.stream,
      );

      final sub2 = Subscription(
        sid: '2',
        subject: 'subject.2',
        messages: controller2.stream,
      );

      final msg1 = NatsMessage(subject: 'subject.1', sid: '1');
      final msg2 = NatsMessage(subject: 'subject.2', sid: '2');

      controller1.add(msg1);
      controller2.add(msg2);

      final received1 = await sub1.messages.first;
      final received2 = await sub2.messages.first;

      expect(received1.subject, equals('subject.1'));
      expect(received2.subject, equals('subject.2'));

      await controller1.close();
      await controller2.close();
    });
  });

  group('Subscription toString', () {
    test('toString contains subject', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      final str = sub.toString();
      expect(str, contains('test.subject'));

      controller.close();
    });

    test('toString contains sid', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: 'abc123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      final str = sub.toString();
      expect(str, contains('abc123'));

      controller.close();
    });

    test('toString contains queueGroup when present', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        queueGroup: 'workers',
        messages: controller.stream,
      );

      final str = sub.toString();
      expect(str, contains('workers'));

      controller.close();
    });

    test('toString handles null queueGroup', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'test.subject',
        messages: controller.stream,
      );

      final str = sub.toString();
      expect(str, contains('queueGroup=null'));

      controller.close();
    });

    test('toString output format is consistent', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: 'SID123',
        subject: 'my.subject',
        queueGroup: 'myQueue',
        messages: controller.stream,
      );

      final str = sub.toString();
      expect(str, startsWith('Subscription('));
      expect(str, endsWith(')'));
      expect(str, contains('subject=my.subject'));
      expect(str, contains('sid=SID123'));
      expect(str, contains('queueGroup=myQueue'));

      controller.close();
    });
  });

  group('Subscription lifecycle', () {
    test('multiple subscriptions can coexist', () {
      final controller1 = StreamController<NatsMessage>();
      final controller2 = StreamController<NatsMessage>();

      final sub1 = Subscription(
        sid: '1',
        subject: 'subject.1',
        messages: controller1.stream,
      );

      final sub2 = Subscription(
        sid: '2',
        subject: 'subject.2',
        messages: controller2.stream,
      );

      expect(sub1.isActive, isTrue);
      expect(sub2.isActive, isTrue);
      expect(sub1.sid, isNot(equals(sub2.sid)));
      expect(sub1.subject, isNot(equals(sub2.subject)));

      controller1.close();
      controller2.close();
    });

    test('subscription with wildcard subject works', () {
      final controller = StreamController<NatsMessage>();
      final sub = Subscription(
        sid: '123',
        subject: 'foo.*.bar',
        queueGroup: 'workers',
        messages: controller.stream,
      );

      expect(sub.subject, equals('foo.*.bar'));
      expect(sub.isActive, isTrue);

      controller.close();
    });
  });
}
