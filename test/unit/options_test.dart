import 'package:flutter_test/flutter_test.dart';
import 'package:nats_dart/src/client/options.dart';

void main() {
  group('ConnectOptions default values', () {
    test('default maxReconnectAttempts is -1', () {
      final opts = const ConnectOptions();
      expect(opts.maxReconnectAttempts, equals(-1));
    });

    test('default reconnectDelay is 2 seconds', () {
      final opts = const ConnectOptions();
      expect(opts.reconnectDelay, equals(const Duration(seconds: 2)));
    });

    test('default pingInterval is 2 minutes', () {
      final opts = const ConnectOptions();
      expect(opts.pingInterval, equals(const Duration(minutes: 2)));
    });

    test('default maxPingOut is 2', () {
      final opts = const ConnectOptions();
      expect(opts.maxPingOut, equals(2));
    });

    test('default noEcho is false', () {
      final opts = const ConnectOptions();
      expect(opts.noEcho, isFalse);
    });

    test('default inboxPrefix is "_INBOX"', () {
      final opts = const ConnectOptions();
      expect(opts.inboxPrefix, equals('_INBOX'));
    });

    test('all auth fields default to null', () {
      final opts = const ConnectOptions();
      expect(opts.authToken, isNull);
      expect(opts.user, isNull);
      expect(opts.pass, isNull);
      expect(opts.jwt, isNull);
      expect(opts.nkeyPath, isNull);
    });

    test('name defaults to null', () {
      final opts = const ConnectOptions();
      expect(opts.name, isNull);
    });
  });

  group('ConnectOptions custom construction', () {
    test('construct with custom values', () {
      final opts = ConnectOptions(
        name: 'test-client',
        maxReconnectAttempts: 10,
        reconnectDelay: const Duration(seconds: 5),
        pingInterval: const Duration(seconds: 30),
        maxPingOut: 5,
        noEcho: true,
        inboxPrefix: 'CUSTOM',
        authToken: 'token123',
      );

      expect(opts.name, equals('test-client'));
      expect(opts.maxReconnectAttempts, equals(10));
      expect(opts.reconnectDelay, equals(const Duration(seconds: 5)));
      expect(opts.pingInterval, equals(const Duration(seconds: 30)));
      expect(opts.maxPingOut, equals(5));
      expect(opts.noEcho, isTrue);
      expect(opts.inboxPrefix, equals('CUSTOM'));
      expect(opts.authToken, equals('token123'));
    });

    test('construct with user/password auth', () {
      final opts = ConnectOptions(
        user: 'admin',
        pass: 'secret',
      );

      expect(opts.user, equals('admin'));
      expect(opts.pass, equals('secret'));
    });

    test('construct with JWT auth', () {
      final opts = ConnectOptions(
        jwt: 'jwt-token',
        nkeyPath: '/path/to/nkey',
      );

      expect(opts.jwt, equals('jwt-token'));
      expect(opts.nkeyPath, equals('/path/to/nkey'));
    });
  });

  group('ConnectOptions validate', () {
    test(
        'validate does NOT throw when authToken and user alone (user needs pass to count)',
        () {
      final opts = ConnectOptions(
        authToken: 'token',
        user: 'admin',
      );

      // Only authToken counts as an auth method because user alone is incomplete
      expect(() => opts.validate(), returnsNormally);
    });

    test('validate throws when both authToken and user+pass are set', () {
      final opts = ConnectOptions(
        authToken: 'token',
        user: 'admin',
        pass: 'secret',
      );

      // Two auth methods: authToken and (user+pass)
      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('validate throws when both token and user/pass are set', () {
      final opts = ConnectOptions(
        authToken: 'token',
        user: 'admin',
        pass: 'secret',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when both jwt and authToken are set', () {
      final opts = ConnectOptions(
        jwt: 'jwt-token',
        authToken: 'token',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when both jwt and authToken are set (reverse order)',
        () {
      final opts = ConnectOptions(
        authToken: 'token',
        jwt: 'jwt-token',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when both jwt and nkeyPath are set', () {
      final opts = ConnectOptions(
        jwt: 'jwt-token',
        nkeyPath: '/path/to/key',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when both nkeyPath and authToken are set', () {
      final opts = ConnectOptions(
        nkeyPath: '/path/to/key',
        authToken: 'token',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when both user/pass and jwt are set', () {
      final opts = ConnectOptions(
        user: 'admin',
        pass: 'secret',
        jwt: 'jwt-token',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when both user/pass and nkeyPath are set', () {
      final opts = ConnectOptions(
        user: 'admin',
        pass: 'secret',
        nkeyPath: '/path/to/key',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate throws when three auth methods are set', () {
      final opts = ConnectOptions(
        authToken: 'token',
        user: 'admin',
        jwt: 'jwt-token',
      );

      expect(
        () => opts.validate(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validate succeeds with only authToken', () {
      final opts = ConnectOptions(
        authToken: 'token123',
      );

      expect(() => opts.validate(), returnsNormally);
    });

    test('validate succeeds with only user+pass', () {
      final opts = ConnectOptions(
        user: 'admin',
        pass: 'secret',
      );

      expect(() => opts.validate(), returnsNormally);
    });

    test('validate succeeds with only user (missing pass)', () {
      final opts = ConnectOptions(
        user: 'admin',
      );

      // This should NOT throw - only user is set (not both user AND pass)
      // According to the implementation, it checks (user != null && pass != null) as one auth method
      expect(() => opts.validate(), returnsNormally);
    });

    test('validate succeeds with only pass (missing user)', () {
      final opts = ConnectOptions(
        pass: 'secret',
      );

      // This should NOT throw - only pass is set (not both user AND pass)
      expect(() => opts.validate(), returnsNormally);
    });

    test('validate succeeds with only jwt', () {
      final opts = ConnectOptions(
        jwt: 'jwt-token',
      );

      expect(() => opts.validate(), returnsNormally);
    });

    test('validate succeeds with only nkeyPath', () {
      final opts = ConnectOptions(
        nkeyPath: '/path/to/key',
      );

      expect(() => opts.validate(), returnsNormally);
    });

    test('validate succeeds with no auth', () {
      final opts = const ConnectOptions();

      expect(() => opts.validate(), returnsNormally);
    });
  });

  group('ConnectOptions copyWith', () {
    test('copyWith returns new instance with updated name', () {
      final opts1 = const ConnectOptions(name: 'original');
      final opts2 = opts1.copyWith(name: 'updated');

      expect(opts1.name, equals('original'));
      expect(opts2.name, equals('updated'));
    });

    test('copyWith preserves unspecified fields', () {
      final opts1 = ConnectOptions(
        name: 'test',
        maxReconnectAttempts: 10,
        authToken: 'token',
      );

      final opts2 = opts1.copyWith(name: 'updated');

      expect(opts2.name, equals('updated'));
      expect(opts2.maxReconnectAttempts, equals(10));
      expect(opts2.authToken, equals('token'));
      expect(opts2.reconnectDelay,
          equals(const Duration(seconds: 2))); // default preserved
    });

    test('copyWith updates multiple fields', () {
      final opts1 = const ConnectOptions(
        name: 'test',
        maxReconnectAttempts: 10,
      );

      final opts2 = opts1.copyWith(
        name: 'updated',
        maxReconnectAttempts: 20,
        noEcho: true,
      );

      expect(opts2.name, equals('updated'));
      expect(opts2.maxReconnectAttempts, equals(20));
      expect(opts2.noEcho, isTrue);
      expect(
          opts2.reconnectDelay, equals(const Duration(seconds: 2))); // default
    });

    test('copyWith preserves ConnectionStatus (not in options)', () {
      // ConnectionStatus is not part of ConnectOptions, so this verifies
      // copyWith doesn't affect anything unrelated
      final opts1 = const ConnectOptions();
      final opts2 = opts1.copyWith(maxReconnectAttempts: 5);

      expect(opts2.maxReconnectAttempts, equals(5));
      expect(opts2.name, isNull); // preserved default
    });
  });

  group('ConnectionStatus enum', () {
    test('ConnectionStatus has connecting value', () {
      expect(ConnectionStatus.connecting, isNotNull);
    });

    test('ConnectionStatus has connected value', () {
      expect(ConnectionStatus.connected, isNotNull);
    });

    test('ConnectionStatus has reconnecting value', () {
      expect(ConnectionStatus.reconnecting, isNotNull);
    });

    test('ConnectionStatus has closed value', () {
      expect(ConnectionStatus.closed, isNotNull);
    });

    test('ConnectionStatus enum values are distinct', () {
      final values = ConnectionStatus.values;
      expect(values.length, equals(4));
      expect(values, contains(ConnectionStatus.connecting));
      expect(values, contains(ConnectionStatus.connected));
      expect(values, contains(ConnectionStatus.reconnecting));
      expect(values, contains(ConnectionStatus.closed));
    });

    test('ConnectionStatus enum does not have error value', () {
      final values = ConnectionStatus.values;

      // Check that none of the values contain "error"
      for (final status in values) {
        expect(status.toString().toLowerCase(), isNot(contains('error')));
      }
    });
  });
}
