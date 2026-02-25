/// Chaos engineering tests for reconnection resilience.
///
/// Requires a NATS Docker container named "nats":
/// ```bash
/// docker run -d --name nats -p 4222:4222 nats:latest
/// ```
///
/// Tests client reconnection by killing/restarting the server 100 times.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nats_dart/src/client/connection.dart';
import 'package:test/test.dart';

void main() {
  group('Chaos Engineering', () {
    test('100 cycles of kill/restart >= 99% reconnection success', () async {
      // Check if Docker is available
      ProcessResult? dockerCheck;
      try {
        dockerCheck = await Process.run('docker', ['--version']);
      } catch (e) {
        markTestSkipped('Docker not available');
        return;
      }

      if (dockerCheck.exitCode != 0) {
        markTestSkipped('Docker not available');
        return;
      }

      // Check if NATS container exists
      final containerCheck = await Process.run(
        'docker',
        ['ps', '-a', '--filter', 'name=nats', '--format', '{{.Names}}'],
      );

      final containerNames = (containerCheck.stdout as String).trim();
      if (!containerNames.contains('nats')) {
        markTestSkipped('NATS Docker container named "nats" not found. '
            'Run: docker run -d --name nats -p 4222:4222 nats:latest');
        return;
      }

      const cycleCount = 100;
      var successCount = 0;
      // Initial connection
      NatsConnection? nc;
      try {
        nc = await NatsConnection.connect(
          'nats://localhost:4222',
        ).timeout(const Duration(seconds: 3));
      } catch (e) {
        markTestSkipped(
            'Initial connection failed - NATS server not available');
        return;
      }

      // Chaos loop: kill and restart 100 times
      for (int i = 0; i < cycleCount; i++) {
        try {
          // 1. Kill the NATS container
          await Process.run('docker', ['kill', 'nats']);

          // 2. Wait briefly for client to detect disconnect
          await Future<void>.delayed(const Duration(milliseconds: 200));
          // 3. Restart the container
          final restartResult = await Process.run('docker', ['start', 'nats']);

          if (restartResult.exitCode != 0) {
            continue;
          }
          // 4. Wait for server to become ready
          await Future<void>.delayed(const Duration(milliseconds: 500));
          // 5. Verify client reconnects (check if connection is alive)
          // Try to publish - if reconnection worked, this should succeed
          try {
            await nc
                .publish(
                  'chaos.test.$i',
                  Uint8List.fromList('cycle-$i'.codeUnits),
                )
                .timeout(const Duration(seconds: 2));
            successCount++;
          } catch (e) {
            // Reconnection failed
          }
        } catch (e) {
          // Error in this cycle
        }
      }

      // Calculate success rate
      final successRate = successCount / cycleCount;

      // ignore: avoid_print
      print(
          'Reconnection success rate: ${(successRate * 100).toStringAsFixed(1)}%');
      // ignore: avoid_print
      print('Successful reconnects: $successCount / $cycleCount');

      // Clean up
      await nc.close();

      // Ensure container is running after test
      await Process.run('docker', ['start', 'nats']);

      // Assert >= 99% reconnection success
      expect(successRate, greaterThanOrEqualTo(0.99),
          reason: 'Reconnection success rate should be >= 99%. '
              'Actual: ${(successRate * 100).toStringAsFixed(1)}%');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
