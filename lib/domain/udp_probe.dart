import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Результат проверки UDP через прокси/туннель.
class UdpProbeResult {
  const UdpProbeResult({
    required this.ok,
    required this.sent,
    required this.received,
    this.rttMs,
    this.error,
  });

  const UdpProbeResult.failed(String message)
      : ok = false,
        sent = 0,
        received = 0,
        rttMs = null,
        error = message;

  /// Хотя бы один STUN-ответ вернулся через туннель.
  final bool ok;
  final int sent;
  final int received;

  /// Медиана RTT по полученным ответам, мс.
  final int? rttMs;
  final String? error;

  /// Готовая строка для тоста/лога.
  String get summary {
    if (error != null && sent == 0) return 'Проверка UDP не удалась: $error';
    if (!ok) return 'UDP не проходит — голос Discord работать не будет';
    final quality = received == sent
        ? 'голос Discord пойдёт'
        : 'есть потери, голос может прерываться';
    return 'UDP работает: $received/$sent, $rttMs мс — $quality';
  }

  @override
  String toString() => summary;
}

/// Проверка UDP: STUN Binding Request через SOCKS5 UDP ASSOCIATE.
///
/// Работает с любым локальным SOCKS5, умеющим UDP: mixed-inbound sing-box
/// (Windows-туннель и Deep Probe) и socks-inbound Xray на Android. STUN-ответ
/// означает, что UDP-датаграмма дошла до интернета через туннель и вернулась —
/// ровно то, что нужно голосу Discord (WebRTC/UDP).
class UdpProbe {
  const UdpProbe._();

  /// Один адресат на всю проверку: при смене адресата внутри одной
  /// UDP-ассоциации часть ответов терялась (проверено на sing-box 1.14.4),
  /// и проба врала о «потерях». Голосу Discord это не мешает: у него
  /// один voice-сервер на соединение.
  static const stunServers = <(String, int)>[
    ('stun.l.google.com', 19302),
  ];

  static const _magicCookie = 0x2112A442;

  static Future<UdpProbeResult> viaSocks5(
    int socksPort, {
    int attempts = 5,
    Duration timeout = const Duration(seconds: 3),
    String socksHost = '127.0.0.1',
  }) async {
    Socket? control;
    RawDatagramSocket? udp;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      control = await Socket.connect(socksHost, socksPort,
          timeout: const Duration(seconds: 3));
      final reader = _ByteReader(control);

      // Приветствие: версия 5, 1 метод, «без аутентификации».
      control.add([5, 1, 0]);
      final hello = await reader.read(2).timeout(timeout);
      if (hello[0] != 5 || hello[1] != 0) {
        return const UdpProbeResult.failed('SOCKS5: метод не принят');
      }

      // UDP ASSOCIATE с адресом 0.0.0.0:0 — «пришлю откуда угодно».
      control.add([5, 3, 0, 1, 0, 0, 0, 0, 0, 0]);
      final head = await reader.read(4).timeout(timeout);
      if (head[1] != 0) {
        return UdpProbeResult.failed('SOCKS5: UDP ASSOCIATE отклонён (код ${head[1]})');
      }
      final atyp = head[3];
      final addrLen = switch (atyp) {
        1 => 4,
        4 => 16,
        3 => (await reader.read(1).timeout(timeout))[0],
        _ => -1,
      };
      if (addrLen < 0) return const UdpProbeResult.failed('SOCKS5: неизвестный тип адреса');
      final addrBytes = await reader.read(addrLen).timeout(timeout);
      final portBytes = await reader.read(2).timeout(timeout);
      var relayHost = atyp == 3
          ? utf8.decode(addrBytes)
          : InternetAddress.fromRawAddress(Uint8List.fromList(addrBytes)).address;
      if (relayHost == '0.0.0.0' || relayHost == '::') relayHost = socksHost;
      final relayPort = (portBytes[0] << 8) | portBytes[1];
      final relayAddr = InternetAddress(relayHost);

      udp = await RawDatagramSocket.bind(
        relayAddr.type == InternetAddressType.IPv6
            ? InternetAddress.loopbackIPv6
            : InternetAddress.loopbackIPv4,
        0,
      );

      final rnd = Random.secure();
      final pending = <String, Stopwatch>{};
      final rtts = <int>[];
      final done = Completer<void>();

      sub = udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = udp!.receive();
        if (dg == null) return;
        final payload = decodeSocksUdp(dg.data);
        if (payload == null) return;
        final tx = parseStunResponse(payload);
        if (tx == null) return;
        final sw = pending.remove(tx);
        if (sw == null) return;
        rtts.add(sw.elapsedMilliseconds);
        if (rtts.length == attempts && !done.isCompleted) done.complete();
      });

      for (var i = 0; i < attempts; i++) {
        final (host, port) = stunServers[i % stunServers.length];
        final txId = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
        pending[_hex(txId)] = Stopwatch()..start();
        udp.send(encodeSocksUdp(host, port, buildStunRequest(txId)), relayAddr, relayPort);
        await Future.delayed(const Duration(milliseconds: 150));
      }

      await done.future.timeout(timeout, onTimeout: () {});
      rtts.sort();
      return UdpProbeResult(
        ok: rtts.isNotEmpty,
        sent: attempts,
        received: rtts.length,
        rttMs: rtts.isEmpty ? null : rtts[rtts.length ~/ 2],
      );
    } on TimeoutException {
      return const UdpProbeResult.failed('таймаут SOCKS5');
    } catch (e) {
      return UdpProbeResult.failed(e.toString());
    } finally {
      await sub?.cancel();
      udp?.close();
      control?.destroy();
    }
  }

  // ── Чистые функции (покрыты тестами) ─────────────────────────────────────

  /// STUN Binding Request (RFC 5389): 20 байт заголовка без атрибутов.
  static Uint8List buildStunRequest(Uint8List txId) {
    assert(txId.length == 12);
    final b = BytesBuilder();
    b.add([0x00, 0x01, 0x00, 0x00]); // type=Binding Request, length=0
    b.add(_u32(_magicCookie));
    b.add(txId);
    return b.toBytes();
  }

  /// Transaction ID (hex) успешного Binding Response или null.
  static String? parseStunResponse(Uint8List data) {
    if (data.length < 20) return null;
    final type = (data[0] << 8) | data[1];
    if (type != 0x0101) return null; // Binding Success Response
    final cookie = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
    if (cookie != _magicCookie) return null;
    return _hex(data.sublist(8, 20));
  }

  /// SOCKS5 UDP-заголовок (RFC 1928 §7) с доменным адресом + payload.
  static Uint8List encodeSocksUdp(String host, int port, Uint8List payload) {
    final hostBytes = utf8.encode(host);
    final b = BytesBuilder();
    b.add([0, 0, 0, 3, hostBytes.length]);
    b.add(hostBytes);
    b.add([(port >> 8) & 0xff, port & 0xff]);
    b.add(payload);
    return b.toBytes();
  }

  /// Payload из SOCKS5 UDP-датаграммы или null (фрагменты не поддерживаем).
  static Uint8List? decodeSocksUdp(Uint8List data) {
    if (data.length < 4 || data[2] != 0) return null;
    final int addrLen;
    var offset = 4;
    switch (data[3]) {
      case 1:
        addrLen = 4;
      case 4:
        addrLen = 16;
      case 3:
        if (data.length < 5) return null;
        addrLen = data[4];
        offset = 5;
      default:
        return null;
    }
    final start = offset + addrLen + 2;
    if (data.length < start) return null;
    return Uint8List.sublistView(data, start);
  }

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Последовательное чтение N байт из TCP-сокета.
class _ByteReader {
  _ByteReader(Socket socket) {
    _sub = socket.listen(
      (chunk) {
        _buf.addAll(chunk);
        _pump();
      },
      onError: (Object e) => _fail(e),
      onDone: () => _fail(const SocketException('соединение закрыто')),
      cancelOnError: true,
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final _buf = <int>[];
  int _want = 0;
  Completer<List<int>>? _waiter;

  Future<List<int>> read(int n) {
    _want = n;
    final c = Completer<List<int>>();
    _waiter = c;
    _pump(); // может завершить c синхронно, если байты уже в буфере
    return c.future;
  }

  void _pump() {
    final w = _waiter;
    if (w == null || w.isCompleted || _buf.length < _want) return;
    final out = _buf.sublist(0, _want);
    _buf.removeRange(0, _want);
    _waiter = null;
    w.complete(out);
  }

  void _fail(Object e) {
    final w = _waiter;
    if (w != null && !w.isCompleted) w.completeError(e);
    _waiter = null;
    _sub.cancel();
  }
}
