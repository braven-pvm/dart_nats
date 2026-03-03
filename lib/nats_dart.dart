/// A native Dart/Flutter NATS client with full JetStream and KeyValue support.
///
/// This package provides a complete, platform-agnostic NATS client that works on:
/// - Flutter native (iOS, Android, macOS, Windows, Linux) via TCP
/// - Flutter Web via WebSocket
/// - Dart servers via TCP or WebSocket
///
/// ## Features
///
/// - **Pure Dart**: Protocol logic is 100% platform-agnostic
/// - **Cross-Platform**: Same code runs on all Flutter platforms
/// - **JetStream Ready**: Publish to streams with deduplication
/// - **Reconnection**: Automatic reconnect with subscription replay
/// - **Authentication**: Token, user/pass, JWT, and NKey support
///
/// ## Quick Start
///
/// ```dart
/// import 'dart:typed_data';
/// import 'package:nats_dart/nats_dart.dart';
///
/// void main() async {
///   // Connect to NATS server
///   final nc = await NatsConnection.connect('nats://localhost:4222');
///
///   // Subscribe to messages
///   final sub = await nc.subscribe('updates.>');
///   sub.messages.listen((msg) {
///     print('Received on ${msg.subject}: ${String.fromCharCodes(msg.payload)}');
///   });
///
///   // Publish a message
///   await nc.publish(
///     'updates.user.123',
///     Uint8List.fromList('User updated'.codeUnits),
///   );
///
///   // Request/reply
///   final reply = await nc.request(
///     'user.get',
///     Uint8List.fromList('123'.codeUnits),
///     timeout: Duration(seconds: 2),
///   );
///   print('Reply: ${String.fromCharCodes(reply.payload)}');
///
///   await nc.close();
/// }
/// ```
///
/// ## JetStream
///
/// ```dart
/// final js = nc.jetStream();
///
/// // Publish with deduplication
/// final ack = await js.publish(
///   'ORDERS.new',
///   Uint8List.fromList('{"orderId":"123"}'.codeUnits),
///   msgId: 'order-123-001',
/// );
/// print('Published to ${ack.stream}, sequence ${ack.sequence}');
///
/// // Fetch messages from consumer (Phase 2 - API planned)
/// // final consumer = await js.consumer('MY_STREAM', 'my-durable');
/// // final msgs = await consumer.fetch(10);
/// // for (final msg in msgs) {
/// //   print('Message: ${msg.subject}');
/// //   await msg.ack();
/// // }
/// ```
///
/// ## KeyValue Store
///
/// ```dart
/// final js = nc.jetStream();
///
/// // Access KV bucket (Phase 3 - API planned)
/// // final kv = await js.keyValue('my-bucket');
/// //
/// // await kv.put('session:123', Uint8List.fromList('{"user":"alice"}'.codeUnits));
/// // final entry = await kv.get('session:123');
/// // print('Value: ${String.fromCharCodes(entry.value)}');
/// //
/// // kv.watch('session:123').listen((entry) {
/// //   print('Updated: ${entry.key}');
/// // });
/// ```
///
/// ## Authentication
///
/// ```dart
/// // Token
/// final nc = await NatsConnection.connect(
///   'nats://localhost:4222',
///   options: ConnectOptions(authToken: 'my-token'),
/// );
///
/// // Username/password
/// final nc = await NatsConnection.connect(
///   'nats://localhost:4222',
///   options: ConnectOptions(user: 'alice', pass: 'password'),
/// );
///
/// // JWT + NKey
/// final nc = await NatsConnection.connect(
///   'nats://localhost:4222',
///   options: ConnectOptions(
///     jwt: 'eyJhbGciOiJIUzI1NiIs...',
///     nkeyPath: '/path/to/nkey.nk',
///   ),
/// );
/// ```
///
/// ## Connection Lifecycle
///
/// ```dart
/// // Monitor connection status
/// nc.status.listen((status) {
///   print('Status: $status');
/// });
///
/// // Graceful shutdown
/// await nc.drain();  // Wait for pending messages
///
/// // Immediate close
/// await nc.close();
/// ```
///
/// ## Platform Support
///
/// | Platform     | Transport | Status |
/// |--------------|-----------|--------|
/// | Flutter Web  | WebSocket | ✅      |
/// | Flutter iOS  | TCP       | ✅      |
/// | Flutter Android | TCP    | ✅      |
/// | Flutter macOS | TCP      | ✅      |
/// | Flutter Windows | TCP    | ✅      |
/// | Flutter Linux | TCP      | ✅      |
/// | Dart VM      | TCP/WS    | ✅      |
///
/// For more information, see the [documentation](https://github.com/your-repo/nats_dart/tree/main/docs).

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
// export 'src/kv/kv_entry.dart';
