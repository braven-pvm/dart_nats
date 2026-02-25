/// JetStream context for a NATS connection.
///
/// Provides access to stream management, consumer management, and publish/subscribe
/// operations specific to JetStream.
///
/// Example usage:
/// ```dart
/// final js = nc.jetStream();
///
/// // Publish with deduplication
/// final ack = await js.publish('ORDERS.new', data, msgId: 'order-123');
/// print('Published to ${ack.stream}, sequence ${ack.sequence}');
///
/// // Future: stream and consumer management (Phase 2)
/// // final consumer = await js.consumer('MY_STREAM', 'my-durable');
/// // final messages = await consumer.fetch(10);
/// ```
class JetStreamContext {
  /// Create a JetStream context for a connection.
  ///
  /// Typically accessed via `NatsConnection.jetStream()` rather than directly.
  ///
  /// Parameters:
  /// - `connection`: The NATS connection
  /// - `domain`: Optional JetStream domain (for multi-domain setups)
  /// - `timeout`: Default timeout for JetStream operations
  const JetStreamContext(
    dynamic connection, {
    String? domain,
    Duration timeout = const Duration(seconds: 5),
  });
}

/// Result of a JetStream publish operation.
///
/// Returned when a message is successfully
/// stored in a JetStream stream.
///
/// Example:
/// ```dart
/// final ack = await js.publish('ORDERS.new', data, msgId: 'order-123');
/// print('Stream: ${ack.stream}, Sequence: ${ack.sequence}');
/// if (ack.duplicate) {
///   print('Duplicate message detected');
/// }
/// ```
class PubAck {
  /// Name of the stream that stored the message.
  final String stream;

  /// Sequence number assigned by the stream.
  ///
  /// Monotonically increasing for each message in the stream.
  final int sequence;

  /// Whether this was a duplicate (same Nats-Msg-Id within duplicate_window).
  ///
  /// True if a message with the same `msgId` was already stored in the
  /// stream's duplicate window.
  final bool duplicate;

  /// Create a publish acknowledgment.
  ///
  /// Parameters:
  /// - `stream`: The stream name
  /// - `sequence`: The sequence number
  /// - `duplicate`: Whether this was a duplicate (default: false)
  PubAck({
    required this.stream,
    required this.sequence,
    this.duplicate = false,
  });
}
