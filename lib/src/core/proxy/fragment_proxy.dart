import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A tiny loopback HTTP `CONNECT` proxy that fragments the TLS ClientHello
/// across TCP segments so a DPI box can't match the SNI (e.g. `workers.dev`) in
/// a single packet.
///
/// It works *below* TLS: the real handshake still runs end to end between the
/// caller's [HttpClient] and the origin, so the origin certificate validates
/// normally. This only chops the first upstream packet (the ClientHello) so the
/// server name straddles a segment boundary, which is the same anti-DPI trick
/// the proxy tunnel itself uses, applied here to the pre-tunnel fetches (the
/// subscription download and the Cloudflare trace) that would otherwise hit a
/// plaintext-SNI block before any tunnel exists.
///
/// Usage:
/// ```dart
/// final fp = await FragmentProxy.start();
/// final client = HttpClient()..findProxy = (_) => 'PROXY ${fp.authority}';
/// try { /* ... use client ... */ } finally { await fp.stop(); }
/// ```
class FragmentProxy {
  FragmentProxy._(this._server) {
    _server.listen(_handle, onError: (_) {});
  }

  final ServerSocket _server;

  /// The `host:port` a proxy-aware [HttpClient] should target.
  String get authority => '127.0.0.1:${_server.port}';

  /// Binds to an ephemeral loopback port and starts accepting connections.
  static Future<FragmentProxy> start() async {
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return FragmentProxy._(server);
  }

  Future<void> stop() => _server.close();

  void _handle(Socket client) {
    client.setOption(SocketOption.tcpNoDelay, true);
    final BytesBuilder header = BytesBuilder();
    Socket? upstream;
    // 0 = reading the CONNECT header, 1 = awaiting the ClientHello, 2 = relay.
    int phase = 0;
    bool closed = false;
    late StreamSubscription<Uint8List> sub;

    void closeAll() {
      if (closed) return;
      closed = true;
      sub.cancel();
      client.destroy();
      upstream?.destroy();
    }

    sub = client.listen((Uint8List data) async {
      try {
        if (phase == 2) {
          upstream!.add(data);
          return;
        }
        if (phase == 1) {
          // First payload after the tunnel is established is the ClientHello.
          phase = 2;
          sub.pause();
          await _writeFragmented(upstream!, data);
          sub.resume();
          return;
        }
        // phase 0: accumulate until the blank line ending the CONNECT header.
        header.add(data);
        final Uint8List buf = header.toBytes();
        final int end = _endOfHeaders(buf);
        if (end < 0) return; // need more bytes
        final String reqLine =
            ascii.decode(buf.sublist(0, end)).split('\r\n').first;
        if (!reqLine.startsWith('CONNECT ')) {
          closeAll();
          return;
        }
        final String target = reqLine.split(' ')[1];
        final int c = target.lastIndexOf(':');
        final String host = c > 0 ? target.substring(0, c) : target;
        final int port = c > 0 ? (int.tryParse(target.substring(c + 1)) ?? 443) : 443;
        // Anything past the blank line is the start of the TLS stream (rare;
        // most clients wait for the 200 first).
        final Uint8List leftover = buf.sublist(end + 4);

        sub.pause();
        upstream = await Socket.connect(host, port,
            timeout: const Duration(seconds: 15));
        upstream!.setOption(SocketOption.tcpNoDelay, true);
        upstream!.listen(
          (Uint8List up) {
            if (!closed) client.add(up);
          },
          onError: (_) => closeAll(),
          onDone: closeAll,
        );
        client.add(
            ascii.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
        await client.flush();

        if (leftover.isNotEmpty) {
          await _writeFragmented(upstream!, leftover);
          phase = 2;
        } else {
          phase = 1;
        }
        sub.resume();
      } catch (_) {
        closeAll();
      }
    }, onError: (_) => closeAll(), onDone: closeAll);
  }

  /// Writes [hello] to [up] split into two TCP segments cutting through the SNI
  /// hostname, so a DPI box can't see the whole name in one packet.
  Future<void> _writeFragmented(Socket up, Uint8List hello) async {
    final int split = _sniSplitOffset(hello);
    if (split <= 0 || split >= hello.length) {
      up.add(hello);
      await up.flush();
      return;
    }
    up.add(Uint8List.sublistView(hello, 0, split));
    await up.flush();
    // A short gap (with Nagle off) makes the two writes land in separate
    // segments rather than being coalesced by the OS.
    await Future<void>.delayed(const Duration(milliseconds: 12));
    up.add(Uint8List.sublistView(hello, split));
    await up.flush();
  }
}

/// Index of the `\r\n\r\n` that ends an HTTP header block, or -1.
int _endOfHeaders(Uint8List b) {
  for (int i = 0; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

/// Parses a TLS ClientHello and returns a byte offset in the middle of the SNI
/// hostname to split at. Falls back to an early split (or -1) when the SNI can't
/// be located, so a malformed or SNI-less hello degrades gracefully.
int _sniSplitOffset(Uint8List b) {
  try {
    // TLS record: type(1)=0x16, version(2), length(2); handshake starts at 5.
    if (b.length < 45 || b[0] != 0x16) return _fallbackSplit(b);
    int p = 5;
    if (b[p] != 0x01) return _fallbackSplit(b); // ClientHello handshake type
    p += 4; // handshake type(1) + length(3)
    p += 2; // client_version
    p += 32; // random
    if (p >= b.length) return _fallbackSplit(b);
    final int sessionLen = b[p];
    p += 1 + sessionLen;
    if (p + 2 > b.length) return _fallbackSplit(b);
    final int cipherLen = (b[p] << 8) | b[p + 1];
    p += 2 + cipherLen;
    if (p + 1 > b.length) return _fallbackSplit(b);
    final int compLen = b[p];
    p += 1 + compLen;
    if (p + 2 > b.length) return _fallbackSplit(b);
    final int extEnd = p + 2 + ((b[p] << 8) | b[p + 1]);
    p += 2;
    while (p + 4 <= b.length && p + 4 <= extEnd) {
      final int type = (b[p] << 8) | b[p + 1];
      final int len = (b[p + 2] << 8) | b[p + 3];
      final int data = p + 4;
      if (type == 0x0000) {
        // server_name extension: list_len(2), name_type(1), name_len(2), name.
        int q = data + 2 + 1; // skip list length + name type
        if (q + 2 > b.length) break;
        final int nameLen = (b[q] << 8) | b[q + 1];
        q += 2;
        if (q + nameLen > b.length) break;
        return q + (nameLen ~/ 2); // middle of the hostname
      }
      p = data + len;
    }
    return _fallbackSplit(b);
  } catch (_) {
    return _fallbackSplit(b);
  }
}

int _fallbackSplit(Uint8List b) => b.length > 40 ? 20 : -1;
