// lib/presentation/providers/node_provider.dart
//
// Провайдер выбранного сервера.
// Хранит Node, выбранный пользователем вручную в NodeListSheet.
// Если пользователь не выбирал — возвращает null,
// тогда логика bestNode в SubscriptionState остаётся главной.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/node.dart';

class NodeSelectionNotifier extends StateNotifier<Node?> {
  NodeSelectionNotifier() : super(null);

  void select(Node node) => state = node;
  void clear() => state = null;
}

final nodeSelectionProvider =
    StateNotifierProvider<NodeSelectionNotifier, Node?>(
      (_) => NodeSelectionNotifier(),
    );
