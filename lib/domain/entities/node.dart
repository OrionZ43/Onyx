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
    this.realityPbk = '',
    this.realitySid = '',
    this.latencyMs,
    this.udpSupported = false,
    this.isAlive = false,
    this.isTrulyWorking = false, // ← прошёл реальную HTTP-проверку
    this.muxEnabled = false,
    this.muxProtocol = 'smux',
    this.muxMaxStreams = 32,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String uuid;
  final String flow; // после санитайзера всегда "" для WS/gRPC
  final String security; // tls | reality | none
  final String fingerprint; // uTLS → всегда "chrome" после санитайзера
  final String sni; // НЕ ТРОГАТЬ — ключ обхода ТСПУ
  final String path;
  final String network; // tcp | ws | grpc | h2

  // Reality-специфичные поля
  final String realityPbk; // public key (pbk= параметр URI)
  final String realitySid; // short id   (sid= параметр URI)

  // Probe results
  final int? latencyMs;
  final bool udpSupported;
  final bool isAlive;

  /// true = нода прошла реальную HTTP-проверку через sing-box SOCKS5.
  /// Является приоритетным критерием для bestNode и quality.
  final bool isTrulyWorking;

  // Mux (применяется санитайзером)
  final bool muxEnabled;
  final String muxProtocol;
  final int muxMaxStreams;

  Node copyWith({
    int? latencyMs,
    bool? udpSupported,
    bool? isAlive,
    bool? isTrulyWorking,
    String? fingerprint,
    String? flow,
    bool? muxEnabled,
    String? muxProtocol,
    int? muxMaxStreams,
  }) {
    return Node(
      id: id,
      name: name,
      host: host,
      port: port,
      uuid: uuid,
      flow: flow ?? this.flow,
      security: security,
      fingerprint: fingerprint ?? this.fingerprint,
      sni: sni,
      path: path,
      network: network,
      realityPbk: realityPbk,
      realitySid: realitySid,
      latencyMs: latencyMs ?? this.latencyMs,
      udpSupported: udpSupported ?? this.udpSupported,
      isAlive: isAlive ?? this.isAlive,
      isTrulyWorking: isTrulyWorking ?? this.isTrulyWorking,
      muxEnabled: muxEnabled ?? this.muxEnabled,
      muxProtocol: muxProtocol ?? this.muxProtocol,
      muxMaxStreams: muxMaxStreams ?? this.muxMaxStreams,
    );
  }

  /// ИСПРАВЛЕНО: quality теперь учитывает isTrulyWorking, а не только
  /// latencyMs. Раньше нода, провалившая HTTP deep-probe (isTrulyWorking
  /// == false, например VLESS-порт открыт, но сервер не проксирует
  /// реальный трафик), могла всё равно получить NodeQuality.excellent
  /// если у неё был низкий TCP-ping. Пользователь видел "отличный сервер"
  /// у ноды, которая на деле не работает.
  ///
  /// Приоритет:
  ///   1. isAlive == false || latencyMs == null → dead (не прошла даже TCP)
  ///   2. isTrulyWorking == false → poor (TCP жив, но HTTP-проверка не
  ///      прошла — эта нода реально не работает, вне зависимости от пинга)
  ///   3. иначе — обычная градация по latency
  NodeQuality get quality {
    if (!isAlive || latencyMs == null) return NodeQuality.dead;
    if (!isTrulyWorking) return NodeQuality.poor;
    if (latencyMs! < 150) return NodeQuality.excellent;
    if (latencyMs! < 400) return NodeQuality.good;
    return NodeQuality.poor;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'uuid': uuid,
    'flow': flow,
    'security': security,
    'fingerprint': fingerprint,
    'sni': sni,
    'path': path,
    'network': network,
    'realityPbk': realityPbk,
    'realitySid': realitySid,
    'latencyMs': latencyMs,
    'udpSupported': udpSupported,
    'isAlive': isAlive,
    'isTrulyWorking': isTrulyWorking,
    'muxEnabled': muxEnabled,
    'muxProtocol': muxProtocol,
    'muxMaxStreams': muxMaxStreams,
  };

  factory Node.fromJson(Map<String, dynamic> json) => Node(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    host: json['host'] as String? ?? '',
    port: json['port'] as int? ?? 443,
    uuid: json['uuid'] as String? ?? '',
    flow: json['flow'] as String? ?? '',
    security: json['security'] as String? ?? '',
    fingerprint: json['fingerprint'] as String? ?? '',
    sni: json['sni'] as String? ?? '',
    path: json['path'] as String? ?? '',
    network: json['network'] as String? ?? '',
    realityPbk: json['realityPbk'] as String? ?? '',
    realitySid: json['realitySid'] as String? ?? '',
    latencyMs: json['latencyMs'] as int?,
    udpSupported: json['udpSupported'] as bool? ?? false,
    isAlive: json['isAlive'] as bool? ?? false,
    isTrulyWorking: json['isTrulyWorking'] as bool? ?? false,
    muxEnabled: json['muxEnabled'] as bool? ?? false,
    muxProtocol: json['muxProtocol'] as String? ?? 'smux',
    muxMaxStreams: json['muxMaxStreams'] as int? ?? 32,
  );

  /// Generates a vless:// share link for use with flutter_v2ray
  String toShareLink() {
    final params = <String, String>{};
    params['encryption'] = 'none';
    params['type'] = network.isEmpty ? 'tcp' : network;
    params['security'] = security.isEmpty ? 'none' : security;

    if (security == 'tls' || security == 'reality') {
      if (sni.isNotEmpty) params['sni'] = sni;
      if (fingerprint.isNotEmpty) params['fp'] = fingerprint;
    }

    if (security == 'reality') {
      if (realityPbk.isNotEmpty) params['pbk'] = realityPbk;
      if (realitySid.isNotEmpty) params['sid'] = realitySid;
    }

    if (flow.isNotEmpty) params['flow'] = flow;

    if (network == 'ws') {
      if (path.isNotEmpty) params['path'] = path;
      if (sni.isNotEmpty) params['host'] = sni;
    } else if (network == 'grpc') {
      if (path.isNotEmpty) {
        params['serviceName'] = path.replaceAll('/', '');
      }
      params['mode'] = 'gun';
    } else if (network == 'h2') {
      if (path.isNotEmpty) params['path'] = path;
      if (sni.isNotEmpty) params['host'] = sni;
    }

    final queryString = params.entries
        .map((e) =>
    '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'vless://$uuid@$host:$port?$queryString#${Uri.encodeComponent(name)}';
  }

  @override
  String toString() => 'Node($name, $host:$port, ${latencyMs}ms, sni=$sni, '
      'working=$isTrulyWorking)';
}

enum NodeQuality { excellent, good, poor, dead }