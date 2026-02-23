import 'transport.dart';

/// Stub implementation for unsupported platforms.
Transport createTransport(Uri uri) {
  throw UnsupportedError('NATS transport is not supported on this platform. '
      'Use dart:io (native) or dart:html (browser) platforms.');
}
