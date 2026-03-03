import 'dart:typed_data';

/// Represents a NATS wire protocol message.
///
/// Can be a MSG, HMSG, INFO, PING, +OK, or -ERR command.
class NatsMessage {
  final String? subject;
  final String? sid;
  final String? replyTo;
  final Uint8List? payload;
  final Map<String, List<String>>? headers;
  final int? statusCode;
  final String? statusDesc;
  final MessageType type;

  const NatsMessage({
    this.subject,
    this.sid,
    this.replyTo,
    this.payload,
    this.headers,
    this.statusCode,
    this.statusDesc,
    this.type = MessageType.msg,
  });

  factory NatsMessage.info(String infoJson) => NatsMessage(
        type: MessageType.info,
        payload: Uint8List.fromList(infoJson.codeUnits),
      );

  factory NatsMessage.ping() => const NatsMessage(type: MessageType.ping);
  factory NatsMessage.pong() => const NatsMessage(type: MessageType.pong);
  factory NatsMessage.ok() => const NatsMessage(type: MessageType.ok);
  factory NatsMessage.err(String message) => NatsMessage(
        type: MessageType.err,
        statusDesc: message,
      );

  /// Whether this is a flow control request (100 FlowControl Request).
  ///
  /// Returns true if statusCode is 100 and statusDesc contains 'Flow'.
  /// Used in JetStream for backpressure management.
  bool get isFlowCtrl =>
      statusCode == 100 && (statusDesc?.contains('Flow') ?? false);

  /// Whether this is an idle heartbeat (100 Idle Heartbeat).
  ///
  /// Returns true if statusCode is 100 and statusDesc contains 'Idle'.
  /// Sent by server to keep connection alive during periods of inactivity.
  bool get isHeartbeat =>
      statusCode == 100 && (statusDesc?.contains('Idle') ?? false);

  /// Whether this is a "no messages" response (404).
  ///
  /// Returns true if statusCode is 404.
  /// Indicates no messages available for pull consumer fetch.
  bool get isNoMsg => statusCode == 404;

  /// Whether this is a timeout response (408).
  ///
  /// Returns true if statusCode is 408.
  /// Indicates a request timed out waiting for a response.
  bool get isTimeout => statusCode == 408;

  /// Get first value of a header by name (case-insensitive).
  String? header(String name) {
    if (headers == null) return null;
    // Case-insensitive lookup
    for (final entry in headers!.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value.isNotEmpty ? entry.value.first : null;
      }
    }
    return null;
  }

  /// Get all values for a header by name (case-insensitive).
  List<String>? headerAll(String name) {
    if (headers == null) return null;
    for (final entry in headers!.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'NatsMessage(subject=$subject, type=$type, statusCode=$statusCode)';
}

enum MessageType {
  msg, // MSG: regular message
  hmsg, // HMSG: message with headers
  info, // INFO: server info
  ping, // PING: ping
  pong, // PONG: pong
  ok, // +OK: acknowledgement
  err, // -ERR: error
}
