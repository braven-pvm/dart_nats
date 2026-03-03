/// Throughput benchmarks against real NATS server.
///
/// Requires a running NATS server via Docker:
/// ```bash
/// docker run -p 4222:4222 nats:latest
/// ```
///
/// Measures publish throughput and asserts >= 50,000 msgs/sec for TCP transport.

import 'dart:async';
import 'dart:typed_data';

import 'package:nats_dart/src/client/connection.dart';
import 'package:test/test.dart';

void main() {
  group('Throughput Benchmarks', () {
    test('publish 10,000 1KB messages >= 50,000 msgs/sec', () async {
      NatsConnection? nc;

      // Try to connect to NATS server
      try {
        nc = await NatsConnection.connect(
          'nats://localhost:4222',
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        markTestSkipped('NATS server not available on localhost:4222');
        return;
      }

      final conn = nc;
      try {
        // Prepare 1KB message payload
        final payload = Uint8List(1024); // 1KB
        for (int i = 0; i < 1024; i++) {
          payload[i] = i % 256;
        }

        // Warm-up: publish 100 messages
        for (int i = 0; i < 100; i++) {
          await conn.publish('benchmark.warmup', payload);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // Benchmark: publish 10,000 messages
        const messageCount = 10000;
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < messageCount; i++) {
          await conn.publish('benchmark.throughput.$i', payload);
        }

        stopwatch.stop();

        // Calculate throughput
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        final msgsPerSec = messageCount / seconds;

        // ignore: avoid_print
        print('Throughput: ${msgsPerSec.toStringAsFixed(0)} msgs/sec');
        // ignore: avoid_print
        print(
            'Total time: ${stopwatch.elapsedMilliseconds}ms for $messageCount messages');

        // Assert threshold: >= 50,000 msgs/sec
        expect(msgsPerSec, greaterThanOrEqualTo(50000),
            reason: 'TCP transport should achieve >= 50,000 msgs/sec. '
                'Actual: ${msgsPerSec.toStringAsFixed(0)} msgs/sec');
      } finally {
        await conn.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
