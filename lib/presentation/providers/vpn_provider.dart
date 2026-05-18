import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/log_service.dart';
import '../../domain/entities/vpn_state.dart';
import '../../domain/entities/node.dart';
import '../../domain/node_sanitizer.dart';
import '../../infrastructure/singbox_bridge_windows.dart';

class VpnController extends StateNotifier<VpnState> {
  VpnController() : super(const VpnDisconnected()) {
    _listenBridge();
  }

  final _sanitizer = const NodeSanitizer();
  final _bridge    = SingboxBridgeWindows.instance;

  StreamSubscription? _statsSub;
  StreamSubscription? _errorSub;

  // ── Подключение ────────────────────────────────────────────────────────

  Future<void> connect(Node rawNode) async {
    if (state is VpnConnecting || state is VpnConnected) return;

    final node = _sanitizer.sanitize(rawNode);
    log.i('Подключаемся к ${node.name} [${node.host}:${node.port}]',
        tag: 'VPN');
    log.d('SNI: ${node.sni}, fp: ${node.fingerprint}, '
        'mux: ${node.muxEnabled}', tag: 'VPN');

    state = VpnConnecting(node: node);

    final result = await _bridge.start(node);

    if (!result.success) {
      log.e('Не удалось подключиться: ${result.error}', tag: 'VPN');
      state = VpnError(message: result.error ?? 'Неизвестная ошибка', node: node);
      return;
    }

    log.i('VPN подключён!', tag: 'VPN');
    state = VpnConnected(node: node, connectedAt: DateTime.now());
  }

  // ── Отключение ────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    final current = state;
    if (current is! VpnConnected && current is! VpnConnecting) return;

    final node = switch (current) {
      VpnConnected(node: final n)  => n,
      VpnConnecting(node: final n) => n,
      _                            => null,
    };

    if (node == null) return;
    log.i('Отключаемся...', tag: 'VPN');
    state = VpnDisconnecting(node: node);

    await _bridge.stop();
    state = const VpnDisconnected();
    log.i('VPN отключён', tag: 'VPN');
  }

  void clearError() {
    if (state is VpnError) state = const VpnDisconnected();
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
      log.e('Мост сообщил об ошибке: $error', tag: 'VPN');
      final current = state;
      final node = current is VpnConnected ? current.node : null;
      state = VpnError(message: error, node: node);
    });
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}

final vpnControllerProvider =
    StateNotifierProvider<VpnController, VpnState>(
      (_) => VpnController(),
    );
