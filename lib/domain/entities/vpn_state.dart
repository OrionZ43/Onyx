import 'node.dart';

/// Sealed class describing every possible VPN lifecycle state.
/// Used as the single source of truth by [VpnController].
sealed class VpnState {
  const VpnState();
}

final class VpnDisconnected extends VpnState {
  const VpnDisconnected();
}

final class VpnConnecting extends VpnState {
  const VpnConnecting({required this.node});
  final Node node;
}

final class VpnConnected extends VpnState {
  const VpnConnected({
    required this.node,
    required this.connectedAt,
    this.rxBytes = 0,
    this.txBytes = 0,
  });
  final Node node;
  final DateTime connectedAt;
  final int rxBytes;
  final int txBytes;

  Duration get uptime => DateTime.now().difference(connectedAt);

  VpnConnected withTraffic({required int rx, required int tx}) =>
      VpnConnected(
        node: node,
        connectedAt: connectedAt,
        rxBytes: rx,
        txBytes: tx,
      );
}

final class VpnDisconnecting extends VpnState {
  const VpnDisconnecting({required this.node});
  final Node node;
}

final class VpnError extends VpnState {
  const VpnError({required this.message, this.node});
  final String message;
  final Node? node;
}
