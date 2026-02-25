import 'dart:async';
import '../protocol/message.dart';

/// Represents an active subscription to a subject.
class Subscription {
  /// Unique subscription identifier (server-assigned SID).
  final String sid;

  /// Subject subscribed to (may include wildcard).
  final String subject;

  /// Optional queue group (for load balancing).
  final String? queueGroup;

  /// Internal controller when this subscription owns its stream.
  /// Null for externally-managed subscriptions (backward compatibility).
  late final StreamController<NatsMessage>? _internalController;

  /// Whether this subscription has been unsubscribed.
  bool _isUnsubscribed = false;

  /// Maximum number of messages before auto-unsubscribe (client-side enforcement).
  final int? _maxMsgs;

  /// Count of messages received so far.
  int _messageCount = 0;

  /// Backing messages stream.
  late final Stream<NatsMessage> _messages;

  /// Constructor for backward compatibility (tests).
  ///
  /// Accepts an external stream that the subscription does NOT own.
  Subscription({
    required this.sid,
    required this.subject,
    this.queueGroup,
    required Stream<NatsMessage> messages,
  }) : _maxMsgs = null {
    _internalController = null;
    _messages = messages;
  }

  /// Named constructor for NatsConnection-owned subscriptions.
  ///
  /// Creates an internal StreamController that NatsConnection can route
  /// messages to via [addMessage].
  ///
  /// [maxMsgs] - optional maximum messages before auto-unsubscribing
  Subscription.owned({
    required this.sid,
    required this.subject,
    this.queueGroup,
    int? maxMsgs,
  }) : _maxMsgs = maxMsgs {
    _internalController = StreamController<NatsMessage>.broadcast(sync: true);
    _messages = _internalController!.stream;
  }

  /// Stream of incoming messages for this subscription.
  Stream<NatsMessage> get messages => _messages;

  /// Whether this subscription is active.
  bool get isActive => !_isUnsubscribed;

  /// Internal: Add a routed message to this subscription's stream.
  ///
  /// Called by NatsConnection when a MSG/HMSG with matching SID is received.
  /// Only works for subscriptions created via [Subscription.owned].
  void addMessage(NatsMessage msg) {
    if (!_isUnsubscribed &&
        _internalController != null &&
        !_internalController!.isClosed) {
      _internalController!.add(msg);

      // Client-side auto-unsub enforcement
      _messageCount++;
      if (_maxMsgs != null && _messageCount >= _maxMsgs!) {
        close();
      }
    }
  }

  /// Internal: Mark subscription as unsubscribed and close the stream.
  ///
  /// Called by NatsConnection.unsubscribe().
  void close() {
    _isUnsubscribed = true;
    _internalController?.close();
  }

  @override
  String toString() =>
      'Subscription(subject=$subject, sid=$sid, queueGroup=$queueGroup)';
}
