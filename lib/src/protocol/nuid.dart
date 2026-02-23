import 'dart:math';

/// NATS Unique ID (NUID) generator.
///
/// Generates URL-safe base62 unique identifiers optimized for high-performance
/// id generation. Based on the Deno client implementation.
///
/// References:
/// - https://github.com/nats-io/nats.deno/blob/main/nats-base-client/nuid.ts
/// - https://github.com/nats-io/nkeys
class Nuid {
  static const String _digits =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  static const int _preLen = 12;
  static const int _seqLen = 10;
  static const int _maxSeq = 839299365868340224; // 62^10
  static const int _minInc = 33;
  static const int _maxInc = 333;

  final Random _random = Random.secure();
  late String _pre;
  late int _seq;
  late int _inc;

  Nuid() {
    _randomizePrefix();
    _seq = _random.nextInt(_maxSeq);
    _inc = _minInc + _random.nextInt(_maxInc - _minInc);
  }

  /// Generate next unique ID.
  String next() {
    _seq += _inc;
    if (_seq >= _maxSeq) {
      _randomizePrefix();
      _seq = _inc;
    }
    return _pre + _seqStr();
  }

  /// Generate unique inbox subject (for reply-to).
  String inbox([String prefix = '_INBOX']) => '$prefix.${next()}';

  void _randomizePrefix() {
    final buf = <String>[];
    for (int i = 0; i < _preLen; i++) {
      buf.add(_digits[_random.nextInt(62)]);
    }
    _pre = buf.join();
    _inc = _minInc + _random.nextInt(_maxInc - _minInc);
  }

  String _seqStr() {
    var n = _seq;
    final b = List<String>.filled(_seqLen, '0');
    for (int i = _seqLen - 1; i >= 0; i--) {
      b[i] = _digits[n % 62];
      n ~/= 62;
    }
    return b.join();
  }
}
