import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:nats_dart/src/transport/tcp_transport.dart';
import 'package:nats_dart/src/transport/transport.dart';
import 'package:nats_dart/src/transport/transport_factory.dart'
    show createTransport;
import 'package:nats_dart/src/transport/transport_factory_io.dart'
    as io_factory;
import 'package:nats_dart/src/transport/transport_factory_web.dart'
    as web_factory;
import 'package:nats_dart/src/transport/websocket_transport.dart';

void main() {
  group('createTransport (active factory via conditional import)', () {
    // On native platforms, the active factory is the IO factory
    // These tests verify the conditional import mechanism works

    test('nats://localhost:4222 creates TcpTransport', () {
      final transport = createTransport(Uri.parse('nats://localhost:4222'));
      expect(transport, isA<TcpTransport>());
    });

    test(
        'nats://example.com (no port) creates TcpTransport with default port 4222',
        () {
      final transport = createTransport(Uri.parse('nats://example.com'));
      expect(transport, isA<TcpTransport>());
      final tcp = transport as TcpTransport;
      expect(tcp.port, equals(4222));
      expect(tcp.host, equals('example.com'));
    });

    test('ws://host:9222 creates WebSocketTransport', () {
      final transport = createTransport(Uri.parse('ws://host:9222'));
      expect(transport, isA<WebSocketTransport>());
    });
  });

  group('transport_factory_io.dart (IO factory direct tests)', () {
    test(
        'nats://localhost:4222 creates TcpTransport with correct host and port',
        () {
      final transport =
          io_factory.createTransport(Uri.parse('nats://localhost:4222'));
      expect(transport, isA<TcpTransport>());
      final tcp = transport as TcpTransport;
      expect(tcp.host, equals('localhost'));
      expect(tcp.port, equals(4222));
    });

    test('nats://example.com (no port) defaults to port 4222', () {
      final transport =
          io_factory.createTransport(Uri.parse('nats://example.com'));
      expect(transport, isA<TcpTransport>());
      final tcp = transport as TcpTransport;
      expect(tcp.host, equals('example.com'));
      expect(tcp.port, equals(4222));
    });

    test('nats://host:8222 with explicit port uses that port', () {
      final transport =
          io_factory.createTransport(Uri.parse('nats://host:8222'));
      expect(transport, isA<TcpTransport>());
      final tcp = transport as TcpTransport;
      expect(tcp.port, equals(8222));
    });

    test('nats+tls://host:4222 creates TcpTransport with useTls=true', () {
      final transport =
          io_factory.createTransport(Uri.parse('nats+tls://host:4222'));
      expect(transport, isA<TcpTransport>());
      // Note: useTls is a private field, but we verify the transport was created
      // The TLS behavior is tested in integration tests
    });

    test('ws://host:9222 creates WebSocketTransport on native', () {
      final transport = io_factory.createTransport(Uri.parse('ws://host:9222'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('ws'));
      expect(ws.uri.host, equals('host'));
      expect(ws.uri.port, equals(9222));
    });

    test('wss://host:443 creates WebSocketTransport', () {
      final transport = io_factory.createTransport(Uri.parse('wss://host:443'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('wss'));
    });
  });

  group('transport_factory_web.dart (Web factory direct tests)', () {
    test('nats://host:4222 coerces to ws://host:4222', () {
      final transport =
          web_factory.createTransport(Uri.parse('nats://host:4222'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('ws'));
      expect(ws.uri.host, equals('host'));
      expect(ws.uri.port, equals(4222));
    });

    test('nats+tls://host:4222 coerces to wss://host:4222', () {
      final transport =
          web_factory.createTransport(Uri.parse('nats+tls://host:4222'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('wss'));
      expect(ws.uri.host, equals('host'));
      expect(ws.uri.port, equals(4222));
    });

    test('nats://host:9222 preserves port (NOT changed to 4222)', () {
      final transport =
          web_factory.createTransport(Uri.parse('nats://host:9222'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.port, equals(9222));
    });

    test('ws://host:4222 passes through unchanged', () {
      final transport =
          web_factory.createTransport(Uri.parse('ws://host:4222'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('ws'));
      expect(ws.uri.port, equals(4222));
    });

    test('wss://host:443 passes through unchanged', () {
      final transport =
          web_factory.createTransport(Uri.parse('wss://host:443'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('wss'));
      expect(ws.uri.port, equals(443));
    });

    test('tls://host:4222 coerces to wss://host:4222', () {
      final transport =
          web_factory.createTransport(Uri.parse('tls://host:4222'));
      expect(transport, isA<WebSocketTransport>());
      final ws = transport as WebSocketTransport;
      expect(ws.uri.scheme, equals('wss'));
      expect(ws.uri.port, equals(4222));
    });
  });

  group('TcpTransport (named constructor parameters)', () {
    test('requires named parameters host and port', () {
      // This test verifies the constructor signature
      final transport = TcpTransport(
        host: 'localhost',
        port: 4222,
      );
      expect(transport.host, equals('localhost'));
      expect(transport.port, equals(4222));
    });

    test('accepts optional useTls parameter', () {
      final transport = TcpTransport(
        host: 'localhost',
        port: 4222,
        useTls: true,
      );
      expect(transport.host, equals('localhost'));
      expect(transport.port, equals(4222));
    });

    test('accepts optional connectTimeout parameter', () {
      final transport = TcpTransport(
        host: 'localhost',
        port: 4222,
        connectTimeout: Duration(seconds: 30),
      );
      expect(transport.host, equals('localhost'));
    });
  });

  group('WebSocketTransport', () {
    test('accepts Uri constructor parameter', () {
      final uri = Uri.parse('ws://localhost:8080');
      final transport = WebSocketTransport(uri);
      expect(transport.uri, equals(uri));
    });

    test('accepts optional connectTimeout parameter', () {
      final uri = Uri.parse('ws://localhost:8080');
      final transport = WebSocketTransport(
        uri,
        connectTimeout: Duration(seconds: 30),
      );
      expect(transport.uri, equals(uri));
    });
  });

  group('Transport interface', () {
    test('TcpTransport implements Transport', () {
      final transport = TcpTransport(host: 'localhost', port: 4222);
      expect(transport, isA<Transport>());
    });

    test('WebSocketTransport implements Transport', () {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      expect(transport, isA<Transport>());
    });

    test('TcpTransport incoming stream exists before connect', () {
      final transport = TcpTransport(host: 'localhost', port: 4222);
      expect(transport.incoming, isA<Stream<Uint8List>>());
    });

    test('WebSocketTransport incoming stream exists before connect', () {
      final transport = WebSocketTransport(Uri.parse('ws://localhost:8080'));
      expect(transport.incoming, isA<Stream<Uint8List>>());
    });
  });
}
