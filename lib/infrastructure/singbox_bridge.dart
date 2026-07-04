import '../domain/entities/node.dart';

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
  Future<BridgeResult> start(
    Node node, {
    bool smartRouting = true,
    bool aiDirectLane = true,
    List<String> excludedApps = const [],
  });

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

  Stream<BridgeState> get stateStream;
  Stream<(int rx, int tx)> get statsStream;
  Stream<String> get errorStream;
  BridgeState get state;
}
