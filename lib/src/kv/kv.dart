import 'dart:typed_data';

/// KeyValue store for JetStream.///
/// A distributed key-value store built on NATS JetStream. Keys are strings,
/// values are byte arrays. Supports watching for changes and revision tracking.
///
/// Example usage:
/// ```dart
/// final js = nc.jetStream();
/// final kv = await js.keyValue('my-bucket');
///
/// // Store a value
/// final revision = await kv.put('session:123', Uint8List.fromList('data'.codeUnits));
///
/// // Retrieve a value
/// final entry = await kv.get('session:123');
/// print('Value: ${entry?.value}');
///
/// // Watch for changes
/// kv.watch('session:123').listen((entry) {
///   print('Updated: ${entry.key} at revision ${entry.revision}');
/// });
/// ```
class KeyValue {
  /// Store a value for a key.
  ///
  /// Returns the revision number (stream sequence) of the stored entry.
  /// If the key already exists, it is updated with a new revision.
  ///
  /// Parameters:
  /// - `key`: The key name (e.g., 'session:123', 'config:theme')
  /// - `value`: The value as bytes
  ///
  /// Example:
  /// ```dart
  /// final rev = await kv.put('user:alice', Uint8List.fromList('{"name":"Alice"}'.codeUnits));
  /// print('Stored at revision $rev');
  /// ```
  Future<int> put(String key, Uint8List value) async {
    throw UnimplementedError('KeyValue.put() - Phase 3');
  }

  /// Retrieve a value for a key.
  ///
  /// Returns a [KvEntry] containing the value and metadata, or `null` if the
  /// key does not exist or has been deleted.
  ///
  /// Parameters:
  /// - `key`: The key name to retrieve
  ///
  /// Example:
  /// ```dart
  /// final entry = await kv.get('user:alice');
  /// if (entry != null) {
  ///   print('Value: ${String.fromCharCodes(entry.value)}');
  ///   print('Revision: ${entry.revision}');
  /// }
  /// ```
  Future<KvEntry?> get(String key) async {
    throw UnimplementedError('KeyValue.get() - Phase 3');
  }

  /// Delete a key from the bucket.
  ///
  /// Creates a tombstone marker for the key. Subsequent [get] calls will
  /// return `null`, but [watch] will emit an entry with `isDeleted: true`.
  ///
  /// Parameters:
  /// - `key`: The key name to delete
  ///
  /// Example:
  /// ```dart
  /// await kv.delete('session:123');
  /// ```
  Future<void> delete(String key) async {
    throw UnimplementedError('KeyValue.delete() - Phase 3');
  }

  /// Watch a specific key for changes.
  ///
  /// Returns a stream that emits a [KvEntry] whenever the key is updated
  /// or deleted. The stream remains open until cancelled.
  ///
  /// Parameters:
  /// - `key`: The key name to watch
  ///
  /// Example:
  /// ```dart
  /// kv.watch('config:theme').listen((entry) {
  ///   if (entry.isDeleted) {
  ///     print('Key deleted');
  ///   } else {
  ///     print('Updated: ${entry.valueString}');
  ///   }
  /// });
  /// ```
  Stream<KvEntry> watch(String key) {
    throw UnimplementedError('KeyValue.watch() - Phase 3');
  }

  /// Watch all keys in the bucket for changes.
  ///
  /// Returns a stream that emits a [KvEntry] for every key update, creation,
  /// or deletion in the bucket.
  ///
  /// Example:
  /// ```dart
  /// kv.watchAll().listen((entry) {
  ///   print('Key ${entry.key} changed at revision ${entry.revision}');
  /// });
  /// ```
  Stream<KvEntry> watchAll() {
    throw UnimplementedError('KeyValue.watchAll() - Phase 3');
  }
}

/// An entry in a KeyValue bucket.///
/// Contains the key, value, revision number, creation timestamp, and
/// operation type (put, delete, purge).
class KvEntry {
  /// The bucket name.
  final String bucket;

  /// The key name.
  final String key;

  /// The value as bytes.
  final Uint8List value;

  /// The JetStream stream sequence (revision) for this entry.
  final int revision;

  /// When this entry was created.
  final DateTime created;

  /// The operation type (put, del, purge).
  final KvOp operation;

  KvEntry({
    required this.bucket,
    required this.key,
    required this.value,
    required this.revision,
    required this.created,
    required this.operation,
  });

  /// Decode value as UTF-8 string.
  String get valueString => String.fromCharCodes(value);

  /// True if this entry is a deletion marker.
  bool get isDeleted => operation == KvOp.del || operation == KvOp.purge;
}

/// Operation type for KeyValue entries.
enum KvOp {
  /// Key was set/updated.
  put,

  /// Key was deleted.
  del,

  /// Key was purged (hard delete).
  purge,
}
