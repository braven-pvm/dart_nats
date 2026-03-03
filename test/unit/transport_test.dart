import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:nats_dart/src/transport/mock_transport.dart';
import 'package:nats_dart/src/transport/transport.dart';

void main() {
  group('MockTransport', () {
    late MockTransport transport;

    setUp(() {
      transport = MockTransport();
    });

    tearDown(() async {
      await transport.close();
    });

    group('Transport interface implementation', () {
      test('implements Transport interface', () {
        expect(transport, isA<Transport>());
      });

      test('incoming stream is a Stream<Uint8List>', () {
        expect(transport.incoming, isA<Stream<Uint8List>>());
      });

      test('errors stream is a Stream<Object>', () {
        expect(transport.errors, isA<Stream<Object>>());
      });

      test('isConnected returns false initially', () {
        expect(transport.isConnected, isFalse);
      });

      test('connect() sets isConnected to true', () async {
        await transport.connect();
        expect(transport.isConnected, isTrue);
      });

      test('close() sets isConnected to false', () async {
        await transport.connect();
        expect(transport.isConnected, isTrue);

        await transport.close();
        expect(transport.isConnected, isFalse);
      });
    });

    group('pumpData functionality', () {
      test('pumpData() adds data to incoming stream', () async {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final future = transport.incoming.first;

        transport.pumpData(data);

        final received = await future;
        expect(received, equals(data));
      });

      test('pumpData() can be called multiple times', () async {
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);
        final data3 = Uint8List.fromList([7, 8, 9]);

        final future = transport.incoming.take(3).toList();

        transport.pumpData(data1);
        transport.pumpData(data2);
        transport.pumpData(data3);

        final received = await future;
        expect(received, hasLength(3));
        expect(received[0], equals(data1));
        expect(received[1], equals(data2));
        expect(received[2], equals(data3));
      });

      test('pumpData() after close does not throw', () async {
        await transport.close();

        // Should not throw
        transport.pumpData(Uint8List.fromList([1, 2, 3]));
      });

      test('pumpData() with empty Uint8List', () async {
        final data = Uint8List(0);
        final future = transport.incoming.first;

        transport.pumpData(data);

        final received = await future;
        expect(received, isEmpty);
      });

      test('pumpData() with large payload', () async {
        // 1MB payload
        final data = Uint8List(1024 * 1024);
        for (int i = 0; i < data.length; i++) {
          data[i] = i % 256;
        }

        final future = transport.incoming.first;

        transport.pumpData(data);

        final received = await future;
        expect(received, hasLength(1024 * 1024));
        expect(received[0], equals(0));
        expect(received[1023], equals(255));
        expect(received[1024], equals(0));
      });
    });

    group('pumpError functionality', () {
      test('pumpError() adds error to errors stream', () async {
        final error = Exception('Test network error');
        final future = transport.errors.first;

        transport.pumpError(error);

        final received = await future;
        expect(received, equals(error));
      });

      test('pumpError() with different error types', () async {
        final errors = [
          Exception('Network failure'),
          StateError('Invalid state'),
          ArgumentError('Invalid argument'),
          'String error',
          42,
        ];

        final future = transport.errors.take(errors.length).toList();

        for (final error in errors) {
          transport.pumpError(error);
        }

        final received = await future;
        expect(received, hasLength(errors.length));
        for (int i = 0; i < errors.length; i++) {
          expect(received[i], equals(errors[i]));
        }
      });

      test('pumpError() after close does not throw', () async {
        await transport.close();

        // Should not throw
        transport.pumpError(Exception('Error after close'));
      });

      test('pumpError() can be called multiple times', () async {
        final future = transport.errors.take(3).toList();

        transport.pumpError(Exception('Error 1'));
        transport.pumpError(Exception('Error 2'));
        transport.pumpError(Exception('Error 3'));

        final received = await future;
        expect(received, hasLength(3));
      });
    });

    group('write functionality', () {
      test('write() throws when not connected', () async {
        final data = Uint8List.fromList([1, 2, 3]);

        expect(
          () => transport.write(data),
          throwsA(isA<StateError>()),
        );
      });

      test('write() records data when connected', () async {
        await transport.connect();
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);

        await transport.write(data);

        expect(transport.writtenBytes, hasLength(1));
        expect(transport.writtenBytes[0], equals(data));
      });

      test('write() can be called multiple times', () async {
        await transport.connect();
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);
        final data3 = Uint8List.fromList([7, 8, 9]);

        await transport.write(data1);
        await transport.write(data2);
        await transport.write(data3);

        expect(transport.writtenBytes, hasLength(3));
        expect(transport.writtenBytes[0], equals(data1));
        expect(transport.writtenBytes[1], equals(data2));
        expect(transport.writtenBytes[2], equals(data3));
      });

      test('write() stores a copy of the data', () async {
        await transport.connect();
        final data = Uint8List.fromList([1, 2, 3]);

        await transport.write(data);

        // Modify original
        data[0] = 99;

        // Should not affect recorded data
        expect(transport.writtenBytes[0][0], equals(1));
      });

      test('write() with empty Uint8List', () async {
        await transport.connect();
        final data = Uint8List(0);

        await transport.write(data);

        expect(transport.writtenBytes, hasLength(1));
        expect(transport.writtenBytes[0], isEmpty);
      });

      test('write() with large payload', () async {
        await transport.connect();
        // 100KB payload
        final data = Uint8List(100 * 1024);
        for (int i = 0; i < data.length; i++) {
          data[i] = i % 256;
        }

        await transport.write(data);

        expect(transport.writtenBytes, hasLength(1));
        expect(transport.writtenBytes[0], hasLength(100 * 1024));
      });

      test('write() throws after disconnect', () async {
        await transport.connect();
        await transport.close();

        expect(
          () => transport.write(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('isConnected control', () {
      test('setConnected(true) enables write', () async {
        transport.setConnected(true);

        expect(transport.isConnected, isTrue);

        final data = Uint8List.fromList([1, 2, 3]);
        await transport.write(data);

        expect(transport.writtenBytes, hasLength(1));
      });

      test('setConnected(false) prevents write', () async {
        transport.setConnected(true);
        transport.setConnected(false);

        expect(transport.isConnected, isFalse);

        expect(
          () => transport.write(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<StateError>()),
        );
      });

      test('setConnected can toggle state multiple times', () async {
        transport.setConnected(true);
        expect(transport.isConnected, isTrue);

        transport.setConnected(false);
        expect(transport.isConnected, isFalse);

        transport.setConnected(true);
        expect(transport.isConnected, isTrue);

        transport.setConnected(false);
        expect(transport.isConnected, isFalse);
      });

      test('setConnected(false) simulates disconnect during operation',
          () async {
        await transport.connect();

        await transport.write(Uint8List.fromList([1, 2, 3]));
        expect(transport.writtenBytes, hasLength(1));

        // Simulate disconnect
        transport.setConnected(false);

        expect(
          () => transport.write(Uint8List.fromList([4, 5, 6])),
          throwsA(isA<StateError>()),
        );

        // Previous write still recorded
        expect(transport.writtenBytes, hasLength(1));
      });
    });

    group('writtenBytes getter', () {
      test('writtenBytes returns empty list initially', () {
        expect(transport.writtenBytes, isEmpty);
      });

      test('writtenBytes is unmodifiable', () async {
        await transport.connect();
        await transport.write(Uint8List.fromList([1, 2, 3]));

        expect(
          () => transport.writtenBytes.add(Uint8List.fromList([4, 5, 6])),
          throwsA(anything),
        );
      });

      test('clearWrittenBytes() removes all recorded bytes', () async {
        await transport.connect();
        await transport.write(Uint8List.fromList([1, 2, 3]));
        await transport.write(Uint8List.fromList([4, 5, 6]));

        expect(transport.writtenBytes, hasLength(2));

        transport.clearWrittenBytes();

        expect(transport.writtenBytes, isEmpty);
      });

      test('clearWrittenBytes() allows recording new writes', () async {
        await transport.connect();
        await transport.write(Uint8List.fromList([1, 2, 3]));
        transport.clearWrittenBytes();
        await transport.write(Uint8List.fromList([4, 5, 6]));

        expect(transport.writtenBytes, hasLength(1));
        expect(transport.writtenBytes[0], equals([4, 5, 6]));
      });
    });

    group('close functionality', () {
      test('close() closes incoming stream', () async {
        final completer = Completer<bool>();

        transport.incoming.listen(
          (_) {},
          onDone: () => completer.complete(true),
        );

        await transport.close();

        final closed = await completer.future;
        expect(closed, isTrue);
      });

      test('close() closes errors stream', () async {
        final completer = Completer<bool>();

        transport.errors.listen(
          (_) {},
          onDone: () => completer.complete(true),
        );

        await transport.close();

        final closed = await completer.future;
        expect(closed, isTrue);
      });

      test('close() can be called multiple times', () async {
        await transport.close();
        await transport.close();
        await transport.close();

        // Should not throw
      });
    });

    group('integration with parser-like workflows', () {
      test('pumpData simulates NATS server INFO response', () async {
        final infoResponse = 'INFO {"server_id":"test","version":"2.10.0"}\r\n';

        final receivedData = <Uint8List>[];
        transport.incoming.listen((data) {
          receivedData.add(data);
        });

        transport.pumpData(Uint8List.fromList(infoResponse.codeUnits));

        await Future<void>.delayed(Duration(milliseconds: 10));
        expect(receivedData, hasLength(1));
        expect(String.fromCharCodes(receivedData[0]), equals(infoResponse));
      });

      test('pumpData simulates fragmented MSG delivery', () async {
        final receivedChunks = <Uint8List>[];
        transport.incoming.listen((data) {
          receivedChunks.add(data);
        });

        // Simulate MSG arriving in fragments
        transport.pumpData(Uint8List.fromList('MSG subj 1 5\r\n'.codeUnits));
        transport.pumpData(Uint8List.fromList('Hel'.codeUnits));
        transport.pumpData(Uint8List.fromList('lo\r\n'.codeUnits));

        await Future<void>.delayed(Duration(milliseconds: 10));
        expect(receivedChunks, hasLength(3));
        final fullMessage = receivedChunks.map(String.fromCharCodes).join();
        expect(fullMessage, equals('MSG subj 1 5\r\nHello\r\n'));
      });

      test('write then pumpData simulates request-response', () async {
        await transport.connect();

        // Start listening BEFORE pumping data (broadcast stream doesn't buffer)
        final responseFuture = transport.incoming.first;

        // Client sends PING
        await transport.write(Uint8List.fromList('PING\r\n'.codeUnits));

        // Server responds with PONG
        final pongResponse = 'PONG\r\n';
        transport.pumpData(Uint8List.fromList(pongResponse.codeUnits));

        final response = await responseFuture;
        expect(String.fromCharCodes(response), equals(pongResponse));
        expect(transport.writtenBytes, hasLength(1));
      });
      test('pumpError simulates connection failure', () async {
        Object? receivedError;
        transport.errors.listen((error) {
          receivedError = error;
        });

        transport.pumpError(Exception('Connection lost'));

        await Future<void>.delayed(Duration(milliseconds: 10));
        expect(receivedError, isNotNull);
        expect(receivedError, isA<Exception>());
      });
    });
  });
}
