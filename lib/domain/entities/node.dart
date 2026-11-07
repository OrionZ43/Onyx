/// Протоколы, которые понимает Onyx.
///
/// `vless` — исторический и по умолчанию (старые сохранённые ноды без поля
/// protocol читаются как vless). Остальные добавлены для Китая: Hysteria2 и
/// TUIC (QUIC/UDP), Shadowsocks, Trojan, AnyTLS.
abstract final class NodeProtocol {
  static const vless = 'vless';
  static const hysteria2 = 'hysteria2';
  static const tuic = 'tuic';
  static const shadowsocks = 'shadowsocks';
  static const trojan = 'trojan';
  static const anytls = 'anytls';

  static const all = {vless, hysteria2, tuic, shadowsocks, trojan, anytls};

  /// Короткая метка для UI-бейджа.
  static String label(String p) => switch (p) {
        vless => 'VLESS',
        hysteria2 => 'HY2',
        tuic => 'TUIC',
        shadowsocks => 'SS',
        trojan => 'TROJAN',
        anytls => 'ANYTLS',
        _ => p.toUpperCase(),
      };
}

/// Один сервер (нода) из подписки или ссылки.
///
/// Исторически класс описывал только VLESS; поля VLESS сохранены как были,
/// для остальных протоколов добавлены необязательные поля ниже (password,
/// obfs, serverPorts и т.д.). Неиспользуемые для протокола поля пустые.
class Node {
  const Node({
    this.protocol = NodeProtocol.vless,
    this.sourceIds = const [],
    this.password = '',
    this.method = '',
    this.obfs = '',
    this.obfsPassword = '',
    this.serverPorts = '',
    this.hopInterval = '',
    this.alpn = const [],
    this.insecure = false,
    this.congestion = '',
    this.upMbps = 0,
    this.downMbps = 0,
    this.plugin = '',
    this.pluginOpts = '',
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
    this.aiReachable = false, // ← прошёл проверку доступа к ИИ-сервисам
    this.muxEnabled = false,
    this.muxProtocol = 'smux',
    this.muxMaxStreams = 32,
  });

  /// Один из [NodeProtocol]. По умолчанию vless.
  final String protocol;

  /// Источники (SubscriptionSource.id), в которых встречается нода. Дубли
  /// из разных источников склеиваются по [id], а их источники копятся здесь.
  final List<String> sourceIds;

  /// Первый (основной) источник ноды или пустая строка.
  String get sourceId => sourceIds.isEmpty ? '' : sourceIds.first;

  /// Пароль: hysteria2 / tuic / shadowsocks / trojan / anytls.
  final String password;

  /// Метод шифрования shadowsocks (например 2022-blake3-aes-128-gcm).
  final String method;

  /// Обфускация hysteria2 (сейчас только 'salamander') и её пароль.
  final String obfs;
  final String obfsPassword;

  /// Port hopping hysteria2: диапазоны через запятую, формат "20000-50000"
  /// или "443,20000-50000". Пусто = только [port].
  final String serverPorts;

  /// Интервал смены порта при hopping, например "30s". Пусто = по умолчанию.
  final String hopInterval;

  /// ALPN для TLS (hysteria2/tuic — обычно h3).
  final List<String> alpn;

  /// Не проверять сертификат (самоподписанный на своём сервере).
  final bool insecure;

  /// Контроль перегрузки TUIC (bbr/cubic/new_reno).
  final String congestion;

  /// Пропускная способность для Hysteria2 Brutal. 0 = не задана (BBR).
  final int upMbps;
  final int downMbps;

  /// Плагин shadowsocks (obfs-local / v2ray-plugin) и его опции.
  final String plugin;
  final String pluginOpts;

  /// true для протоколов поверх QUIC/UDP — у них нет TCP-порта, поэтому
  /// TCP-пинг к ним бессмысленен.
  bool get isQuic =>
      protocol == NodeProtocol.hysteria2 || protocol == NodeProtocol.tuic;

  /// Ключ «того же сервера» для автопереключения транспорта: ноды с одним
  /// host, но разными протоколами (REALITY + Hysteria2 от нашего скрипта).
  String get serverKey => host.toLowerCase();

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

  /// true = через эту ноду удалось достучаться до ИИ-сервиса (проверка
  /// на бан exit-IP со стороны Cloudflare/AI-эджей). Проставляется Deep
  /// Probe только для нод, у которых уже isTrulyWorking == true.
  ///
  /// ВНИМАНИЕ: это эвристика. Проверка бьёт по Cloudflare-фронтированному
  /// ИИ-домену; зелёный значок означает "IP не в типовых датацентр-блок-
  /// листах", но не гарантирует доступ к КАЖДОМУ ИИ (Anthropic/Google
  /// используют свои списки и иногда отдают блок как обычную 200-страницу).
  final bool aiReachable;

  // Mux (применяется санитайзером)
  final bool muxEnabled;
  final String muxProtocol;
  final int muxMaxStreams;

  Node copyWith({
    List<String>? sourceIds,
    int? latencyMs,
    bool? udpSupported,
    bool? isAlive,
    bool? isTrulyWorking,
    bool? aiReachable,
    String? fingerprint,
    String? flow,
    bool? muxEnabled,
    String? muxProtocol,
    int? muxMaxStreams,
  }) {
    return Node(
      sourceIds: sourceIds ?? this.sourceIds,
      protocol: protocol,
      password: password,
      method: method,
      obfs: obfs,
      obfsPassword: obfsPassword,
      serverPorts: serverPorts,
      hopInterval: hopInterval,
      alpn: alpn,
      insecure: insecure,
      congestion: congestion,
      upMbps: upMbps,
      downMbps: downMbps,
      plugin: plugin,
      pluginOpts: pluginOpts,
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
      aiReachable: aiReachable ?? this.aiReachable,
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
  /// Честный статус UDP: «нет UDP» только если сервер РАБОТАЕТ (Deep Probe
  /// прошёл), а STUN-ответов нет. Мёртвый сервер — [UdpStatus.unreachable].
  UdpStatus get udpStatus {
    if (udpSupported) return UdpStatus.ok;
    if (isTrulyWorking) return UdpStatus.blocked;
    final probed = latencyMs != null || isAlive;
    if (!probed) return UdpStatus.unknown;
    return UdpStatus.unreachable;
  }

  NodeQuality get quality {
    if (!isAlive || latencyMs == null) return NodeQuality.dead;
    if (!isTrulyWorking) return NodeQuality.poor;
    if (latencyMs! < 150) return NodeQuality.excellent;
    if (latencyMs! < 400) return NodeQuality.good;
    return NodeQuality.poor;
  }

  Map<String, dynamic> toJson() => {
    'protocol': protocol,
    if (sourceIds.isNotEmpty) 'sourceIds': sourceIds,
    if (password.isNotEmpty) 'password': password,
    if (method.isNotEmpty) 'method': method,
    if (obfs.isNotEmpty) 'obfs': obfs,
    if (obfsPassword.isNotEmpty) 'obfsPassword': obfsPassword,
    if (serverPorts.isNotEmpty) 'serverPorts': serverPorts,
    if (hopInterval.isNotEmpty) 'hopInterval': hopInterval,
    if (alpn.isNotEmpty) 'alpn': alpn,
    if (insecure) 'insecure': insecure,
    if (congestion.isNotEmpty) 'congestion': congestion,
    if (upMbps > 0) 'upMbps': upMbps,
    if (downMbps > 0) 'downMbps': downMbps,
    if (plugin.isNotEmpty) 'plugin': plugin,
    if (pluginOpts.isNotEmpty) 'pluginOpts': pluginOpts,
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
    'aiReachable': aiReachable,
    'muxEnabled': muxEnabled,
    'muxProtocol': muxProtocol,
    'muxMaxStreams': muxMaxStreams,
  };

  factory Node.fromJson(Map<String, dynamic> json) => Node(
    sourceIds: (json['sourceIds'] as List?)?.whereType<String>().toList() ?? const [],
    protocol: json['protocol'] as String? ?? NodeProtocol.vless,
    password: json['password'] as String? ?? '',
    method: json['method'] as String? ?? '',
    obfs: json['obfs'] as String? ?? '',
    obfsPassword: json['obfsPassword'] as String? ?? '',
    serverPorts: json['serverPorts'] as String? ?? '',
    hopInterval: json['hopInterval'] as String? ?? '',
    alpn: (json['alpn'] as List?)?.whereType<String>().toList() ?? const [],
    insecure: json['insecure'] as bool? ?? false,
    congestion: json['congestion'] as String? ?? '',
    upMbps: json['upMbps'] as int? ?? 0,
    downMbps: json['downMbps'] as int? ?? 0,
    plugin: json['plugin'] as String? ?? '',
    pluginOpts: json['pluginOpts'] as String? ?? '',
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
    aiReachable: json['aiReachable'] as bool? ?? false,
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
  String toString() => 'Node(${NodeProtocol.label(protocol)} $name, $host:$port, ${latencyMs}ms, sni=$sni, '
      'working=$isTrulyWorking)';
}

enum NodeQuality { excellent, good, poor, dead }

/// Состояние UDP (голос Discord) для бейджа в UI.
enum UdpStatus {
  /// Ещё не проверяли.
  unknown,

  /// Сервер недоступен — UDP не проверялся (не «нет UDP»!).
  unreachable,

  /// Сервер работает, но UDP через него не проходит.
  blocked,

  /// UDP проходит.
  ok,
}