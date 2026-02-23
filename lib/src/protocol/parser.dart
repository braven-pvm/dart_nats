import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'message.dart';

/// Stateful NATS wire protocol parser.
///
/// Handles MSG, HMSG, INFO, PING, PONG, +OK, and -ERR commands.
/// Multi-frame message assembly is handled internally via buffering.
class NatsParser {
  final _buffer = BytesBuilder();
  final _controller = StreamController<NatsMessage>.broadcast(sync: true);

  Stream<NatsMessage> get messages => _controller.stream;

  /// Add incoming bytes to the parsing buffer.
  void addBytes(Uint8List data) {
    _buffer.add(data);
    _tryParse();
  }

  void _tryParse() {
    while (true) {
      final bytes = _buffer.toBytes();
      final crlfIdx = _findCRLF(bytes);

      // Incomplete line — wait for more bytes
      if (crlfIdx == -1) return;

      final controlLine = utf8.decode(bytes.sublist(0, crlfIdx));
      final op = controlLine.split(' ')[0].toUpperCase();

      try {
        switch (op) {
          case 'MSG':
            if (!_parseMsgOrHmsg(controlLine, bytes, false)) return;
            break;
          case 'HMSG':
            if (!_parseMsgOrHmsg(controlLine, bytes, true)) return;
            break;
          case 'INFO':
            _emitInfo(controlLine);
            _advance(crlfIdx + 2);
            break;
          case 'PING':
            _emit(NatsMessage.ping());
            _advance(crlfIdx + 2);
            break;
          case 'PONG':
            _emit(NatsMessage.pong());
            _advance(crlfIdx + 2);
            break;
          case '+OK':
            _emit(NatsMessage.ok());
            _advance(crlfIdx + 2);
            break;
          case '-ERR':
            _emitErr(controlLine);
            _advance(crlfIdx + 2);
            break;
          default:
            // Unknown op — skip line
            _advance(crlfIdx + 2);
        }
      } catch (e) {
        // Parse error — skip this line and continue
        _advance(crlfIdx + 2);
      }
    }
  }

  /// Returns true if a complete message was consumed, false if more bytes are needed.
  bool _parseMsgOrHmsg(String line, Uint8List buf, bool hasHeaders) {
    final parts = line.split(' ')..removeWhere((e) => e.isEmpty);

    String subject;
    String sid;
    String? replyTo;
    int hdrBytes = 0;
    late int totalBytes;

    final isHmsg = parts[0].toUpperCase() == 'HMSG';

    if (isHmsg) {
      // HMSG <subject> <sid> [reply] <hdrBytes> <totalBytes>
      subject = parts[1];
      sid = parts[2];

      if (parts.length == 6) {
        // With reply-to
        replyTo = parts[3];
        hdrBytes = int.parse(parts[4]);
        totalBytes = int.parse(parts[5]);
      } else if (parts.length == 5) {
        // No reply-to
        hdrBytes = int.parse(parts[3]);
        totalBytes = int.parse(parts[4]);
      } else {
        throw FormatException('Invalid HMSG format: $line');
      }
    } else {
      // MSG <subject> <sid> [reply] <totalBytes>
      subject = parts[1];
      sid = parts[2];

      if (parts.length == 5) {
        // With reply-to
        replyTo = parts[3];
        totalBytes = int.parse(parts[4]);
      } else if (parts.length == 4) {
        // No reply-to
        totalBytes = int.parse(parts[3]);
      } else {
        throw FormatException('Invalid MSG format: $line');
      }
    }

    final ctrlLen = line.length + 2; // +2 for \r\n
    final requiredLen = ctrlLen + totalBytes + 2; // +2 for trailing \r\n

    if (buf.length < requiredLen) {
      // Incomplete message — wait for more bytes
      return false;
    }

    Map<String, List<String>>? headers;
    int? statusCode;
    String? statusDesc;
    late Uint8List payload;

    if (isHmsg) {
      final hdrSection = buf.sublist(ctrlLen, ctrlLen + hdrBytes);
      final parsed = _parseHeaderSection(hdrSection);
      headers = parsed.headers;
      statusCode = parsed.statusCode;
      statusDesc = parsed.description;
      payload = buf.sublist(ctrlLen + hdrBytes, ctrlLen + totalBytes);
    } else {
      payload = buf.sublist(ctrlLen, ctrlLen + totalBytes);
    }

    _emit(NatsMessage(
      subject: subject,
      sid: sid,
      replyTo: replyTo,
      payload: payload,
      headers: headers,
      statusCode: statusCode,
      statusDesc: statusDesc,
      type: isHmsg ? MessageType.hmsg : MessageType.msg,
    ));

    _advance(requiredLen);
    return true;
  }

  ({
    int? statusCode,
    String? description,
    Map<String, List<String>> headers,
  }) _parseHeaderSection(Uint8List headerBytes) {
    final text = utf8.decode(headerBytes);
    final lines = text.split('\r\n');

    int? statusCode;
    String? description;

    // First line: 'NATS/1.0' or 'NATS/1.0 100 FlowControl Request'
    if (lines.isNotEmpty && lines[0].startsWith('NATS/1.0')) {
      final rest = lines[0].substring(8).trim();
      if (rest.isNotEmpty) {
        final spaceIdx = rest.indexOf(' ');
        if (spaceIdx != -1) {
          statusCode = int.tryParse(rest.substring(0, spaceIdx));
          description = rest.substring(spaceIdx + 1);
        } else {
          statusCode = int.tryParse(rest);
        }
      }
    }

    // Parse header lines until blank line
    final headers = <String, List<String>>{};
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].isEmpty) break;
      final colonIdx = lines[i].indexOf(':');
      if (colonIdx == -1) continue;

      final key = lines[i].substring(0, colonIdx).trim();
      final value = lines[i].substring(colonIdx + 1).trim();
      headers.putIfAbsent(key, () => []).add(value);
    }

    return (
      statusCode: statusCode,
      description: description,
      headers: headers,
    );
  }

  void _emitInfo(String line) {
    // INFO {...json...}
    final jsonStart = line.indexOf('{');
    if (jsonStart == -1) return;

    final jsonStr = line.substring(jsonStart);
    _emit(NatsMessage.info(jsonStr));
  }

  void _emitErr(String line) {
    // -ERR <message>
    final message = line.length > 5 ? line.substring(5).trim() : '';
    _emit(NatsMessage.err(message));
  }

  void _emit(NatsMessage msg) {
    if (!_controller.isClosed) {
      _controller.add(msg);
    }
  }

  void _advance(int count) {
    final current = _buffer.toBytes();
    _buffer.clear();
    if (count < current.length) {
      _buffer.add(current.sublist(count));
    }
  }

  int _findCRLF(Uint8List bytes) {
    for (int i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10) {
        // \r\n
        return i;
      }
    }
    return -1;
  }

  Future<void> close() => _controller.close();
}
