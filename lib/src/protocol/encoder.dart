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
  static Uint8List hpub(
    String subject,
    Uint8List payload, {
    String? replyTo,
    Map<String, String>? headers,
  }) {
    // Build header section
    final headerLines = <String>['NATS/1.0'];
    if (headers != null && headers.isNotEmpty) {
      headers.forEach((key, value) {
        headerLines.add('$key: $value');
      });
    }
    headerLines.add(''); // Blank line to end headers
    final headerSection = headerLines.join('\r\n').codeUnits;
    final hdrBytes = headerSection.length + 2; // +2 for final \r\n

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
    return Uint8List.fromList(line.codeUnits + [13, 10]); // \r\n
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
      ..add(line.codeUnits)
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
    // <line>\r\n<headerSection>\r\n<payload>\r\n
    final result = BytesBuilder(copy: false);
    result.add(line.codeUnits);
    result.add([13, 10]); // \r\n
    result.add(headerSection);
    result.add([13, 10]); // \r\n (end of headers)
    result.add(payload);
    result.add([13, 10]); // \r\n (end of message)
    return result.toBytes();
  }
}
