/// Represents a single VLESS server node parsed from a subscription URL.
class Node {
  const Node({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.uuid,
    required this.flow,
    required this.security,
    required this.fingerprint,
    required this.sni,
    required this.path,
    required this.network,
    this.realityPbk    = '',
    this.realitySid    = '',
    this.latencyMs,
    this.udpSupported  = false,
    this.isAlive       = false,
    this.isTrulyWorking = false,   // ← NEW: прошёл реальную HTTP-проверку
    this.muxEnabled    = false,
    this.muxProtocol   = 'smux',
    this.muxMaxStreams  = 32,
  });

  final String id;
  final String name;
  final String host;
  final int    port;
  final String uuid;
  final String flow;          // после санитайзера всегда "" для WS/gRPC
  final String security;      // tls | reality | none
  final String fingerprint;   // uTLS → всегда "chrome" после санитайзера
  final String sni;           // НЕ ТРОГАТЬ — ключ обхода ТСПУ
  final String path;
  final String network;       // tcp | ws | grpc | h2

  // Reality-специфичные поля
  final String realityPbk;    // public key (pbk= параметр URI)
  final String realitySid;    // short id   (sid= параметр URI)

  // Probe results
  final int?   latencyMs;
  final bool   udpSupported;
  final bool   isAlive;

  /// true = нода прошла реальную HTTP-проверку через sing-box SOCKS5.
  /// Является приоритетным критерием для bestNode.
  final bool   isTrulyWorking;

  // Mux (применяется санитайзером)
  final bool   muxEnabled;
  final String muxProtocol;
  final int    muxMaxStreams;

  Node copyWith({
    int?    latencyMs,
    bool?   udpSupported,
    bool?   isAlive,
    bool?   isTrulyWorking,
    String? fingerprint,
    String? flow,
    bool?   muxEnabled,
    String? muxProtocol,
    int?    muxMaxStreams,
  }) {
    return Node(
      id:             id,
      name:           name,
      host:           host,
      port:           port,
      uuid:           uuid,
      flow:           flow           ?? this.flow,
      security:       security,
      fingerprint:    fingerprint    ?? this.fingerprint,
      sni:            sni,
      path:           path,
      network:        network,
      realityPbk:     realityPbk,
      realitySid:     realitySid,
      latencyMs:      latencyMs      ?? this.latencyMs,
      udpSupported:   udpSupported   ?? this.udpSupported,
      isAlive:        isAlive        ?? this.isAlive,
      isTrulyWorking: isTrulyWorking ?? this.isTrulyWorking,
      muxEnabled:     muxEnabled     ?? this.muxEnabled,
      muxProtocol:    muxProtocol    ?? this.muxProtocol,
      muxMaxStreams:  muxMaxStreams   ?? this.muxMaxStreams,
    );
  }

  NodeQuality get quality {
    if (!isAlive || latencyMs == null) return NodeQuality.dead;
    if (latencyMs! < 150) return NodeQuality.excellent;
    if (latencyMs! < 400) return NodeQuality.good;
    return NodeQuality.poor;
  }

  @override
  String toString() =>
      'Node($name, $host:$port, ${latencyMs}ms, sni=$sni, '
          'working=$isTrulyWorking)';
}

enum NodeQuality { excellent, good, poor, dead }