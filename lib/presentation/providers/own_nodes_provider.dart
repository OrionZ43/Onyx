// «Свои» серверы (#68): добавленные пользователем ссылками — источник вида
// SourceKind.links, а не чужая подписка. Признак ставит домен (Node.isOwn в
// NodePool.merge, «Оникс») — тот же, по которому автопилот предпочитает
// свои серверы, поэтому значок и приоритет не разойдутся. Вкладка «Свои» —
// автогруппа NodeGroup.ownId (groupNodesProvider).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subscription_provider.dart';

/// id своих серверов — для значка «СВОЙ» и секции «Свои» во «Все».
final ownNodeIdsProvider = Provider<Set<String>>((ref) => {
      for (final n in ref.watch(subscriptionProvider.select((s) => s.nodes)))
        if (n.isOwn) n.id,
    });
