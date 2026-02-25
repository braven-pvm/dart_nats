import 'dart:convert';
import 'dart:typed_data';

/// Encodes NATS wire protocol commands.
class NatsEncoder {
  /// Encode CONNECT command.
  static Uint8List connect({
    required String version,
    required String lang,
    bool headers = true,
    String? user,
    String? pass,
    String? token,
    String? jwt,
    String? nkey,
    String? sig,
    bool verbose = false,
    bool pedantic = false,
    bool noEcho = false,
    bool noResponders = true,
    String? name,
  }) {
    final json = <String, dynamic>{
      'verbose': verbose,
      'pedantic': pedantic,
      'headers': headers,
      'lang': lang,
      'version': version,
      // noEcho maps to 'no_echo' in the NATS protocol JSON.
      // When noEcho=true, the server will not echo back messages published
      // by this client on subjects this client also subscribes to.
      // noEcho=false (default) means the server WILL echo, so we omit the
      // field entirely to keep the CONNECT payload minimal.
      if (noEcho) 'no_echo': noEcho,
      if (noResponders) 'no_responders': noResponders,
      if (name != null) 'name': name,
      if (user != null) 'user': user,
      if (pass != null) 'pass': pass,
      if (token != null) 'auth_token': token,
      if (jwt != null) 'jwt': jwt,
      if (nkey != null) 'nkey': nkey,
      if (sig != null) 'sig': sig,
    };

    final encoded = jsonEncode(json);
    return _encodeCommand('CONNECT', encoded);
  }

  /// Encode PUB (Publish without headers).
  static Uint8List pub(
    String subject,
    Uint8List payload, {
    String? replyTo,
  }) {
    final line = _buildPubLine('PUB', subject, replyTo, payload.length);
    return _buildPayloadCommand(line, payload);
  }

  /// Encode HPUB (Publish with headers).
  ///
  /// Headers map is automatically formatted with NATS/1.0 header and closing blank line.
  /// Supports multi-value headers via Map<String, List<String>>.
  /// All header values are properly UTF-8 encoded for multi-byte characters.
  static Uint8List hpub(
    String subject,
    Uint8List payload, {
    String? replyTo,
    Map<String, dynamic>? headers,
  }) {
    // Build header section with NATS/1.0 header block format
    //
    // Format (byte-perfect):
    // NATS/1.0\r\n
    // [Key: Value\r\n]...
    // \r\n  <-- blank line ends headers
    //
    // hdrBytes = entire header section length INCLUDING final \r\n\r\n
    // totalBytes = hdrBytes + payload.length

    final headerSegment = BytesBuilder(copy: false);

    // Start with NATS/1.0\r\n
    headerSegment.add(utf8.encode('NATS/1.0\r\n'));

    // Add headers (supports Map<String, String> or Map<String, List<String>>)
    // Use utf8.encode() to properly handle multi-byte Unicode characters
    if (headers != null && headers.isNotEmpty) {
      headers.forEach((key, value) {
        if (value is String) {
          headerSegment.add(utf8.encode('$key: $value\r\n'));
        } else if (value is List<String>) {
          for (final val in value) {
            headerSegment.add(utf8.encode('$key: $val\r\n'));
          }
        }
      });
    }

    // End header section with blank line (\r\n)
    headerSegment.add(utf8.encode('\r\n'));
    final headerSection = headerSegment.toBytes();
    final hdrBytes = headerSection.length; // Already includes final \r\n\r\n

    final totalBytes = hdrBytes + payload.length;
    final line = _buildPubLine('HPUB', subject, replyTo, hdrBytes, totalBytes);

    return _buildHpubPayloadCommand(line, headerSection, payload);
  }

  /// Encode SUB (Subscribe).
  static Uint8List sub(
    String subject,
    String sid, {
    String? queueGroup,
  }) {
    if (queueGroup != null) {
      return _encodeCommand('SUB', '$subject $queueGroup $sid');
    }
    return _encodeCommand('SUB', '$subject $sid');
  }

  /// Encode UNSUB (Unsubscribe).
  static Uint8List unsub(
    String sid, {
    int? maxMsgs,
  }) {
    if (maxMsgs != null) {
      return _encodeCommand('UNSUB', '$sid $maxMsgs');
    }
    return _encodeCommand('UNSUB', sid);
  }

  /// Encode PING command.
  static Uint8List ping() => _encodeCommand('PING', '');

  /// Encode PONG command.
  static Uint8List pong() => _encodeCommand('PONG', '');

  static Uint8List _encodeCommand(String op, String args) {
    String line;
    if (args.isEmpty) {
      line = op;
    } else {
      line = '$op $args';
    }
    // Use utf8.encode() to handle potential Unicode in subjects or args
    return Uint8List.fromList(utf8.encode(line) + [13, 10]); // \r\n
  }

  static String _buildPubLine(
    String op,
    String subject,
    String? replyTo,
    int bytes1, [
    int? bytes2,
  ]) {
    if (op == 'PUB') {
      // PUB <subject> [reply] <bytes>
      if (replyTo != null) {
        return '$op $subject $replyTo $bytes1';
      }
      return '$op $subject $bytes1';
    } else {
      // HPUB <subject> [reply] <hdrBytes> <totalBytes>
      if (replyTo != null) {
        return '$op $subject $replyTo $bytes1 $bytes2';
      }
      return '$op $subject $bytes1 $bytes2';
    }
  }

  static Uint8List _buildPayloadCommand(String line, Uint8List payload) {
    // <line>\r\n<payload>\r\n
    final result = BytesBuilder(copy: false)
      ..add(utf8.encode(line)) // Handle Unicode in command lines
      ..add([13, 10]) // \r\n
      ..add(payload)
      ..add([13, 10]); // \r\n
    return result.toBytes();
  }

  static Uint8List _buildHpubPayloadCommand(
    String line,
    List<int> headerSection,
    Uint8List payload,
  ) {
    // HPUB format: <line>\r\n<headerSection><payload>\r\n
    // where headerSection already ends with \r\n\r\n
    final result = BytesBuilder(copy: false);
    result.add(utf8.encode(line)); // Handle Unicode in command lines
    result.add([13, 10]); // \r\n after command line
    result.add(headerSection);
    result.add(payload);
    result.add([13, 10]); // \r\n after payload
    return result.toBytes();
  }
}
