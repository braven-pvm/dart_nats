import 'dart:typed_data';

/// Entry in a KeyValue store.
class KvEntry {
  /// The bucket name.
  final String bucket;

  /// The key.
  final String key;

  /// The value.
  final Uint8List value;

  /// Revision number (JetStream sequence).
  final int revision;

  const KvEntry({
    required this.bucket,
    required this.key,
    required this.value,
    required this.revision,
  });
}
