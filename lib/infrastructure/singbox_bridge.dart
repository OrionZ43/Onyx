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
  Future<BridgeResult> start(Node node, {bool smartRouting = true});
  Future<void> stop();
  Stream<BridgeState> get stateStream;
  Stream<(int rx, int tx)> get statsStream;
  Stream<String> get errorStream;
  BridgeState get state;
}
