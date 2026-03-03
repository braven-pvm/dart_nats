/// Latency benchmarks against real NATS server.
///
/// Requires a running NATS server via Docker:
/// ```bash
/// docker run -p 4222:4222 nats:latest
/// ```
///
/// Measures request/reply latency and asserts p50 < 5ms for TCP transport.

import 'dart:typed_data';

import 'package:nats_dart/src/client/connection.dart';
import 'package:test/test.dart';

void main() {
  group('Latency Benchmarks', () {
    test('1,000 request/reply cycles p50 < 5ms', () async {
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
        // Set up responder service
        final responderSub = await conn.subscribe('latency.echo');
        final responderFuture = responderSub.messages.listen((req) async {
          if (req.replyTo != null) {
            // Echo back the payload immediately
            await conn.publish(req.replyTo!, req.payload ?? Uint8List(0));
          }
        }).asFuture<void>();
        // Warm-up: 20 request/reply cycles
        for (int i = 0; i < 20; i++) {
          await conn.request(
            'latency.echo',
            Uint8List.fromList('warmup'.codeUnits),
            timeout: const Duration(seconds: 1),
          );
        }

        // Benchmark: 1,000 request/reply cycles
        const cycleCount = 1000;
        final latencies = <int>[];

        for (int i = 0; i < cycleCount; i++) {
          final stopwatch = Stopwatch()..start();

          await conn.request(
            'latency.echo',
            Uint8List.fromList('benchmark-$i'.codeUnits),
            timeout: const Duration(seconds: 1),
          );

          stopwatch.stop();
          latencies.add(stopwatch.elapsedMicroseconds);
        }

        // Calculate percentiles
        latencies.sort();

        final p50index = (cycleCount * 0.50).floor();
        final p99index = (cycleCount * 0.99).floor();

        final p50Microseconds = latencies[p50index];
        final p99Microseconds = latencies[p99index];

        final p50ms = p50Microseconds / 1000.0;
        final p99ms = p99Microseconds / 1000.0;

        // ignore: avoid_print
        print('Latency p50: ${p50ms.toStringAsFixed(2)}ms');
        // ignore: avoid_print
        print('Latency p99: ${p99ms.toStringAsFixed(2)}ms');

        // Assert p50 threshold: < 5ms
        expect(p50ms, lessThan(5.0),
            reason: 'TCP transport p50 latency should be < 5ms. '
                'Actual: ${p50ms.toStringAsFixed(2)}ms');

        // Report p99 for informational purposes
        // ignore: avoid_print
        print('p99 latency: ${p99ms.toStringAsFixed(2)}ms');

        // Clean up responder
        await responderFuture;
      } finally {
        await conn.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
