import '../domain/entities/node.dart';
import '../domain/singbox_config_builder.dart';
import '../domain/udp_probe.dart';

export '../domain/singbox_config_builder.dart' show RoutingOptions;
export '../domain/udp_probe.dart' show UdpProbeResult;

enum BridgeState { idle, starting, running, stopping, error }

class BridgeResult {
  final bool success;
  final String? error;

  const BridgeResult({required this.success, this.error});
}

abstract class SingboxBridge {
  Future<void> ensureBinaries({void Function(String, double?)? onStatus});
  bool get binariesReady;

  /// Поднимает туннель для [node].
  ///
  /// Контракт: возвращает success: true только когда туннель РЕАЛЬНО
  /// подтверждён рабочим (а не сразу после fire-and-forget вызова нативного
  /// старта — см. историю симптома B в CHANGELOG).
  ///
  /// [excludedApps] — package name'ы приложений, идущих в обход VPN
  /// (split tunneling). Поддерживается только на Android; Windows-реализация
  /// игнорирует параметр.
  /// [fallbacks] — другие транспорты того же сервера (REALITY + Hysteria2):
  /// мост собирает из них urltest-группу с автопереключением.
  Future<BridgeResult> start(
    Node node, {
    List<Node> fallbacks = const [],
    RoutingOptions routing = const RoutingOptions(),
    List<String> excludedApps = const [],
  });

  /// Проверка UDP через поднятый туннель (STUN через локальный SOCKS5).
  /// Именно по UDP идут голос, камера и стримы Discord.
  Future<UdpProbeResult> checkUdp();

  Future<void> stop();

  /// Независимая проверка реальной связности ЧЕРЕЗ туннель.
  ///
  /// Гарантия: положительный результат возможен только если запрос прошёл
  /// именно через VPN-туннель, а не напрямую через физическую сеть.
  ///   • Windows — HTTPS-запрос через локальный mixed-прокси sing-box
  ///     (127.0.0.1:2080): если процесс мёртв, соединение просто не откроется.
  ///   • Android — измерение задержки средствами самого v2ray-core
  ///     (getConnectedServerDelay): запрос уходит через outbound туннеля,
  ///     при мёртвом core возвращается ошибка.
  ///
  /// Это закрывает ловушку, из-за которой прямой HTTPS-запрос на Android
  /// «подтверждал» связность даже при неподнятом VPN (трафик шёл через
  /// обычную сеть) — см. CHANGELOG, симптом B.
  Future<bool> verifyTunnel();

  /// Замеряет текущую задержку через туннель в миллисекундах.
  /// Возвращает -1, если туннель не отвечает (мёртв/таймаут).
  ///
  /// Отличие от [verifyTunnel]: даёт не булев «жив/мёртв», а число, по
  /// которому можно поймать ДЕГРАДАЦИЮ (пинг улетел в 5000 мс, туннель
  /// формально жив, но uplink захлёбывается — классический «тебя не слышно
  /// в звонке»). Булева проверка такое пропускает.
  ///   • Android — нативный getConnectedServerDelay (замер самим ядром);
  ///   • Windows — время HTTPS-запроса через локальный прокси sing-box.
  Future<int> measureLatency();

  Stream<BridgeState> get stateStream;
  Stream<(int rx, int tx)> get statsStream;
  Stream<String> get errorStream;
  BridgeState get state;
}
