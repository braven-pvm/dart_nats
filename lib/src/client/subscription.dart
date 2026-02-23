import 'package:nats_dart/src/protocol/message.dart';

/// Represents an active subscription to a subject.
class Subscription {
  /// Unique subscription identifier (server-assigned SID).
  final String sid;

  /// Subject subscribed to (may include wildcard).
  final String subject;

  /// Optional queue group (for load balancing).
  final String? queueGroup;

  /// Stream of incoming messages.
  final Stream<NatsMessage> messages;

  /// Whether this subscription has been unsubscribed.
  bool _isUnsubscribed = false;

  Subscription({
    required this.sid,
    required this.subject,
    required this.messages,
    this.queueGroup,
  });

  /// Whether this subscription is active.
  bool get isActive => !_isUnsubscribed;

  @override
  String toString() =>
      'Subscription(subject=$subject, sid=$sid, queueGroup=$queueGroup)';
}
