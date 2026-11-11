// «Свои» серверы (#68): добавленные пользователем ссылками — источник вида
// SourceKind.links, а не чужая подписка. Если сервер есть и в подписке, и в
// ссылках, он всё равно «свой». Только для вида (значок, вкладка, секция);
// приоритет своих в автовыборе — в домене («Оникс»).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/node.dart';
import 'sources_provider.dart';
import 'subscription_provider.dart';

/// Источники-ссылки.
final ownSourceIdsProvider = Provider<Set<String>>((ref) => {
      for (final s in ref.watch(sourcesProvider))
        if (s.kind == SourceKind.links) s.id,
    });

/// id своих серверов.
final ownNodeIdsProvider = Provider<Set<String>>((ref) {
  final own = ref.watch(ownSourceIdsProvider);
  if (own.isEmpty) return const {};
  return {
    for (final n in ref.watch(subscriptionProvider.select((s) => s.nodes)))
      if (n.sourceIds.any(own.contains)) n.id,
  };
});

/// Свои серверы — для вкладки «Свои».
final ownNodesProvider = Provider<List<Node>>((ref) {
  final ids = ref.watch(ownNodeIdsProvider);
  if (ids.isEmpty) return const [];
  return [
    for (final n in ref.watch(subscriptionProvider.select((s) => s.nodes)))
      if (ids.contains(n.id)) n,
  ];
});
