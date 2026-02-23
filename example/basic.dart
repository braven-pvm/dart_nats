import 'dart:typed_data';

import 'package:nats_dart/nats_dart.dart';

void main() async {
  // Basic example: connect, pub/sub, request/reply
  final nc = await NatsConnection.connect('nats://localhost:4222');

  // Subscribe
  final sub = nc.subscribe('hello');
  sub.messages.listen((msg) {
    print('Received message: ${msg.subject}');
  });

  // Publish
  await nc.publish('hello', 'World'.codeUnits as Uint8List);

  // Request/reply
  final response = await nc.request('help', 'need data'.codeUnits as Uint8List);
  print('Response: ${response.payload}');

  await nc.close();
}
