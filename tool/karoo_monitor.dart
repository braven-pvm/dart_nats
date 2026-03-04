// Live monitor for Karoo telemetry via NATS WebSocket.
// Usage: dart run tool/karoo_monitor.dart [ws://192.168.0.137:9222] [TESTS.karoo]
//
// Connects to the Karoo nats-server and prints every message as it arrives.
// Press Ctrl+C to exit.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

String _fmtTime(int? seconds) {
  if (seconds == null) return '?';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m${s.toString().padLeft(2, '0')}s';
  return '${m}m${s.toString().padLeft(2, '0')}s';
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'ws://192.168.0.137:9222';
  final subject = args.length > 1 ? args[1] : 'TESTS.karoo';

  int count = 0;
  var backoff = const Duration(seconds: 2);
  const maxBackoff = Duration(seconds: 30);

  while (true) {
    NatsConnection? nc;
    StreamSubscription<NatsMessage>? listener;
    Timer? watchdog;
    final done = Completer<String>(); // completes with reason string

    try {
      print('[karoo_monitor] Connecting to $url ...');
      nc = await NatsConnection.connect(url)
          .timeout(const Duration(seconds: 10));
      print('[karoo_monitor] Connected. Subscribing to "$subject" ...\n');
      backoff = const Duration(seconds: 2); // reset on success

      final sub = await nc.subscribe(subject);

      void resetWatchdog() {
        watchdog?.cancel();
        watchdog = Timer(const Duration(seconds: 5), () {
          if (!done.isCompleted) done.complete('timeout');
        });
      }

      resetWatchdog();

      listener = sub.messages.listen(
        (msg) {
          resetWatchdog();
          count++;
          final raw = String.fromCharCodes(msg.payload ?? Uint8List(0));
          final Map<String, dynamic> p;
          try {
            p = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            print('[$count] RAW: $raw');
            return;
          }

          final ts = p['timestamp'] ?? '?';
          final power = p['power'] ?? '?';
          final hr = p['heartRate'] ?? '?';
          final speed = p['speed'] ?? '?';
          final cadence = p['cadence'] ?? '?';
          final battery = p['batteryPercent'] ?? '?';
          final ride = p['rideState'] ?? '?';
          final natsState = p['natsState'] ?? '?';
          final lap = p['lapNumber'] ?? '?';
          final lapTime = _fmtTime(p['lapTime'] as int?);
          final totalTime = _fmtTime(p['elapsedTime'] as int?);

          final bytes = msg.payload?.length ?? 0;
          print('[$count] ts=$ts  power=${power}W  hr=$hr  speed=$speed  '
              'cadence=$cadence  battery=$battery%  '
              'lap=$lap  lapTime=$lapTime  totalTime=$totalTime  '
              'ride=$ride  nats=$natsState  (${bytes}B)');
        },
        onDone: () { if (!done.isCompleted) done.complete('stream closed'); },
        onError: (Object e) { if (!done.isCompleted) done.complete('error: $e'); },
        cancelOnError: false,
      );

      final reason = await done.future;
      if (reason == 'timeout') {
        print('[karoo_monitor] No message for 5s — connection lost.');
      } else {
        print('[karoo_monitor] Disconnected ($reason).');
      }
    } on TimeoutException {
      print('[karoo_monitor] Connect timed out.');
    } catch (e) {
      print('[karoo_monitor] Error: $e');
    } finally {
      watchdog?.cancel();
      await listener?.cancel();
      try { await nc?.close(); } catch (_) {}
    }

    print('[karoo_monitor] Reconnecting in ${backoff.inSeconds}s ...');
    await Future<void>.delayed(backoff);
    backoff = Duration(
      seconds: (backoff.inSeconds * 2).clamp(0, maxBackoff.inSeconds),
    );
  }
}
