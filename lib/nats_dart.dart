/// A native Dart/Flutter NATS client with full JetStream and KeyValue support.
///
/// This package provides a complete, platform-agnostic NATS client that works on:
/// - Flutter native (iOS, Android, macOS, Windows, Linux) via TCP
/// - Flutter Web via WebSocket
/// - Dart servers via TCP or WebSocket
///
/// ## Quick Start
///
/// ```dart
/// import 'package:nats_dart/nats_dart.dart';
///
/// void main() async {
///   final nc = await NatsConnection.connect('nats://localhost:4222');
///   await nc.publish('subject', 'Hello, NATS!');
///   nc.subscribe('subject').messages.listen((msg) {
///     print('Received: ${String.fromCharCodes(msg.payload)}');
///   });
///   await nc.close();
/// }
/// ```
///
/// ## JetStream
///
/// ```dart
/// final js = nc.jetStream();
/// final ack = await js.publish('STREAM_SUBJECT', 'data');
/// final consumer = await js.consumer('MY_STREAM', 'my-consumer');
/// final msgs = await consumer.fetch(10);
/// ```
///
/// ## KeyValue Store
///
/// ```dart
/// final kv = await js.keyValue('bucket-name');
/// await kv.put('key', 'value');
/// final entry = await kv.get('key');
/// kv.watch('key').listen((entry) => print(entry.value));
/// ```

library nats_dart;

export 'src/client/connection.dart';
export 'src/client/options.dart';
export 'src/client/subscription.dart';
export 'src/protocol/message.dart';
export 'src/jetstream/jetstream.dart';
export 'src/jetstream/stream_manager.dart';
export 'src/jetstream/consumer_manager.dart';
export 'src/jetstream/pull_consumer.dart';
export 'src/jetstream/js_msg.dart';
export 'src/kv/kv.dart';
export 'src/kv/kv_entry.dart';
