import 'dart:typed_data';

/// A message delivered by JetStream.
class JsMsg {
  /// The message payload.
  final Uint8List data;

  /// The subject.
  final String subject;

  const JsMsg(this.data, this.subject);

  // TODO: Implement ack(), nak(), term(), inProgress() methods
}
