import 'dart:typed_data';

/// JetStream context for a NATS connection.
///
/// Provides access to stream management, consumer management, and publish/subscribe
/// operations specific to JetStream.
class JetStreamContext {
  // TODO: Implement full JetStream functionality
  const JetStreamContext(
    dynamic connection, {
    String? domain,
    Duration timeout = const Duration(seconds: 5),
  });
}

/// Result of a JetStream publish operation.
class PubAck {
  /// Name of the stream.
  final String stream;

  /// Sequence number assigned by the stream.
  final int sequence;

  /// Whether this was a duplicate (same Nats-Msg-Id within duplicate_window).
  final bool duplicate;

  PubAck({
    required this.stream,
    required this.sequence,
    this.duplicate = false,
  });
}
