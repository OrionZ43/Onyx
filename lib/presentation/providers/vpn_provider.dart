import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/log_service.dart';
import '../../domain/entities/vpn_state.dart';
import '../../domain/entities/node.dart';
import '../../domain/node_sanitizer.dart';
import '../../infrastructure/singbox_bridge_windows.dart';
import 'subscription_provider.dart';
import 'node_provider.dart';
import 'settings_provider.dart';

class VpnController extends StateNotifier<VpnState> {
  VpnController(this.ref) : super(const VpnDisconnected()) {
    _listenBridge();
  }

  final Ref ref;
  final _sanitizer = const NodeSanitizer();
  final _bridge = SingboxBridgeWindows.instance;

  StreamSubscription? _statsSub;
  StreamSubscription? _errorSub;
  Timer? _healthTimer;
  int _failedPings = 0;

  // ── Подключение ────────────────────────────────────────────────────────

  Future<void> connect(Node rawNode) async {
    if (state is VpnConnecting || state is VpnConnected) return;

    final node = _sanitizer.sanitize(rawNode);
    log.i(
      'Подключаемся к ${node.name} [${node.host}:${node.port}]',
      tag: 'VPN',
    );
    log.d(
      'SNI: ${node.sni}, fp: ${node.fingerprint}, '
      'mux: ${node.muxEnabled}',
      tag: 'VPN',
    );

    state = VpnConnecting(node: node);

    final isSmartRouting = ref.read(settingsProvider).smartRouting;
    final result = await _bridge.start(node, smartRouting: isSmartRouting);

    if (!result.success) {
      log.e('Не удалось подключиться: ${result.error}', tag: 'VPN');
      state = VpnError(
        message: result.error ?? 'Неизвестная ошибка',
        node: node,
      );
      return;
    }

    log.i('VPN подключён!', tag: 'VPN');
    state = VpnConnected(node: node, connectedAt: DateTime.now());
    _startHealthMonitor();
  }

  // ── Отключение ────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    final current = state;
    if (current is! VpnConnected && current is! VpnConnecting) return;

    final node = switch (current) {
      VpnConnected(node: final n) => n,
      VpnConnecting(node: final n) => n,
      _ => null,
    };

    if (node == null) return;
    log.i('Отключаемся...', tag: 'VPN');
    state = VpnDisconnecting(node: node);

    _healthTimer?.cancel();
    await _bridge.stop();
    state = const VpnDisconnected();
    log.i('VPN отключён', tag: 'VPN');
  }

  void clearError() {
    if (state is VpnError) state = const VpnDisconnected();
  }

  // ── Active Health Monitor ─────────────────────────────────────────────

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _failedPings = 0;
    _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final current = state;
      if (current is! VpnConnected) return;

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      // Пускаем через наш локальный mixed-порт (HTTP/SOCKS)
      client.findProxy = (uri) => 'PROXY 127.0.0.1:2080';
      client.badCertificateCallback = (cert, host, port) => true;

      try {
        // Пингуем IP напрямую (1.1.1.1), чтобы избежать багов DNS-сниффинга
        final request = await client.getUrl(Uri.parse('http://1.1.1.1/'));
        final response =
            await request.close().timeout(const Duration(seconds: 5));

        // Любой ответ от сервера (даже 301 редирект) означает, что интернет есть
        if (response.statusCode >= 200 && response.statusCode < 400) {
          _failedPings = 0;
        } else {
          _failedPings++;
        }
      } catch (e) {
        log.d('Health Monitor пинг не прошел: $e', tag: 'VPN');
        _failedPings++;
      } finally {
        client.close(force: true);
      }

      if (_failedPings >= 2) {
        _healthTimer?.cancel();
        _autoSwitch();
      }
    });
  }

  Future<void> _autoSwitch() async {
    final current = state;
    if (current is! VpnConnected) return;
    final deadNode = current.node;

    log.w(
      '🔄 Авто-переключение: нода ${deadNode.name} не отвечает!',
      tag: 'VPN',
    );

    // 1. Отключаемся
    await disconnect();

    // 2. Помечаем ноду как мертвую в подписках
    ref.read(subscriptionProvider.notifier).markNodeAsDead(deadNode.id);
    ref.read(nodeSelectionProvider.notifier).clear(); // Сбрасываем ручной выбор

    // 3. Берем новую лучшую ноду
    final nextNode = ref.read(subscriptionProvider).bestNode;

    if (nextNode != null) {
      log.i(
        '🚀 Переключаемся на следующий сервер: ${nextNode.name}',
        tag: 'VPN',
      );
      await connect(nextNode);
    } else {
      log.e('❌ Нет доступных серверов для авто-переключения', tag: 'VPN');
      state = const VpnError(message: 'Все серверы недоступны');
    }
  }

  // ── Слушаем мост ──────────────────────────────────────────────────────

  void _listenBridge() {
    // Обновляем трафик статистику
    _statsSub = _bridge.statsStream.listen((stats) {
      final current = state;
      if (current is VpnConnected) {
        state = current.withTraffic(rx: stats.$1, tx: stats.$2);
      }
    });

    // Обрабатываем ошибки моста (неожиданное завершение)
    _errorSub = _bridge.errorStream.listen((error) {
      if (error == 'WATCHDOG_NO_TRAFFIC') {
        _autoSwitch();
        return;
      }

      log.e('Мост сообщил об ошибке: $error', tag: 'VPN');
      final current = state;
      final node = current is VpnConnected ? current.node : null;
      state = VpnError(message: error, node: node);
    });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _statsSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}

final vpnControllerProvider = StateNotifierProvider<VpnController, VpnState>(
  (ref) => VpnController(ref),
);
