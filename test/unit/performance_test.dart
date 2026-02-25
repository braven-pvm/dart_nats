import 'dart:typed_data';

import 'package:nats_dart/src/protocol/encoder.dart';
import 'package:nats_dart/src/protocol/parser.dart';
import 'package:test/test.dart';

void main() {
  group('Parser performance', () {
    test('parses 10,000 simple MSG commands under 2000ms', () {
      final parser = NatsParser();
      final stopwatch = Stopwatch()..start();

      // Generate and parse 10,000 MSG commands
      for (int i = 0; i < 10000; i++) {
        final subject = 'test.subject.$i';
        final payload = Uint8List.fromList('Message $i'.codeUnits);

        // Encode using the encoder
        final msgBytes = NatsEncoder.pub(subject, payload, replyTo: 'reply.$i');

        // Feed to parser
        parser.addBytes(msgBytes);
      }
      stopwatch.stop();

      // Assert performance threshold
      expect(stopwatch.elapsedMilliseconds, lessThan(2000),
          reason: 'Parser should process 10,000 messages in under 2000ms');

      // ignore: avoid_print
      print('Parsed 10,000 messages in ${stopwatch.elapsedMilliseconds}ms');
    });

    test('parses 10,000 HMSG commands with headers under 2000ms', () {
      final parser = NatsParser();
      final stopwatch = Stopwatch()..start();

      // Generate and parse 10,000 HMSG commands
      for (int i = 0; i < 10000; i++) {
        final subject = 'test.stream.$i';
        final payload = Uint8List.fromList('{"id":$i}'.codeUnits);
        final headers = <String, dynamic>{
          'Nats-Msg-Id': 'msg-$i',
          'Content-Type': 'application/json',
        };

        // Encode using HPUB
        final hmsgBytes = NatsEncoder.hpub(subject, payload, headers: headers);

        // Feed to parser
        parser.addBytes(hmsgBytes);
      }
      stopwatch.stop();
      stopwatch.stop();

      // Assert performance threshold
      expect(stopwatch.elapsedMilliseconds, lessThan(2000),
          reason: 'Parser should process 10,000 HMSG messages in under 2000ms');

      // ignore: avoid_print
      print(
          'Parsed 10,000 HMSG messages in ${stopwatch.elapsedMilliseconds}ms');
    });

    test('encoder HPUB performance: 10,000 encodes under 1000ms', () {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 10000; i++) {
        final subject = 'bench.subject.$i';
        final payload =
            Uint8List.fromList('Data payload $i with some content'.codeUnits);
        final headers = <String, dynamic>{
          'Nats-Msg-Id': 'bench-$i',
          'X-Request-Id': 'req-$i',
        };

        NatsEncoder.hpub(subject, payload, headers: headers);
      }

      stopwatch.stop();

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason:
              'Encoder should generate 10,000 HPUB commands in under 1000ms');

      // ignore: avoid_print
      print(
          'Encoded 10,000 HPUB commands in ${stopwatch.elapsedMilliseconds}ms');
    });
  });
}
