import '../entities/node.dart';
import '../entities/node_group.dart';
import '../entities/subscription_source.dart';
import '../failover_policy.dart';
import '../node_scorer.dart';

/// Чистая логика пула нод: склейка источников, группы, выбор, failover.
/// Без Flutter и хранилища — покрыта юнит-тестами.
abstract final class NodePool {
  /// Склеивает ноды включённых источников в один список.
  ///
  ///   • порядок — порядок источников, внутри — порядок в источнике;
  ///   • дубли (одинаковый [Node.id] = протокол + host + port + учётные
  ///     данные) склеиваются: параметры берутся из первого источника,
  ///     [Node.sourceIds] копит все источники;
  ///   • результаты проб (пинг, «работает», AI, UDP) переносятся из
  ///     [previous] по id — включение/выключение источника не сбрасывает
  ///     проверку.
  static List<Node> merge(
    List<SubscriptionSource> sources,
    Map<String, List<Node>> nodesBySource, {
    Iterable<Node> previous = const [],
  }) {
    final prev = {for (final n in previous) n.id: n};
    final out = <String, Node>{};
    final order = <String>[];
    for (final s in sources) {
      if (!s.enabled) continue;
      // Добавленные ссылками — «свои» серверы (#68), подписка — чужие.
      final own = s.kind == SourceKind.links;
      for (final n in nodesBySource[s.id] ?? const <Node>[]) {
        final existing = out[n.id];
        if (existing != null) {
          if (!existing.sourceIds.contains(s.id)) {
            out[n.id] = existing.copyWith(
              sourceIds: [...existing.sourceIds, s.id],
              isOwn: existing.isOwn || own,
            );
          }
          continue;
        }
        var merged = n.copyWith(sourceIds: [s.id], isOwn: own);
        final p = prev[n.id];
        if (p != null) {
          merged = merged.copyWith(
            latencyMs: p.latencyMs,
            isAlive: p.isAlive,
            isTrulyWorking: p.isTrulyWorking,
            aiReachable: p.aiReachable,
            udpSupported: p.udpSupported,
            exitCountry: p.exitCountry,
          );
        }
        out[n.id] = merged;
        order.add(n.id);
      }
    }
    return [for (final id in order) out[id]!];
  }

  /// Группы-источники: по одной на каждый источник (порядок источников).
  static List<NodeGroup> sourceGroups(List<SubscriptionSource> sources) => [
        for (final s in sources)
          NodeGroup(
            id: NodeGroup.idForSource(s.id),
            name: s.name,
            sourceIds: [s.id],
            isVirtual: true,
          ),
      ];

  /// Ноды группы [groupId] среди [nodes] (уже склеенных включённых).
  ///
  /// null / '' — все; `src:<id>` — источник; `auto:fav|udp|ai|own` — фильтры;
  /// иначе — пользовательская группа из [groups] (отдельные ноды + целые
  /// источники). Неизвестная группа — пустой список.
  static List<Node> nodesOf(
    String? groupId,
    List<Node> nodes, {
    List<NodeGroup> groups = const [],
    Set<String> favorites = const {},
  }) {
    if (groupId == null || groupId.isEmpty) return nodes;
    switch (groupId) {
      case NodeGroup.favoritesId:
        return nodes.where((n) => favorites.contains(n.id)).toList();
      case NodeGroup.udpId:
        return nodes.where((n) => n.udpSupported).toList();
      case NodeGroup.aiId:
        return nodes.where((n) => n.aiReachable).toList();
      case NodeGroup.ownId:
        return nodes.where((n) => n.isOwn).toList();
    }
    if (groupId.startsWith(NodeGroup.sourcePrefix)) {
      final sid = groupId.substring(NodeGroup.sourcePrefix.length);
      return nodes.where((n) => n.sourceIds.contains(sid)).toList();
    }
    NodeGroup? g;
    for (final x in groups) {
      if (x.id == groupId) g = x;
    }
    if (g == null) return const [];
    final ids = g.nodeIds.toSet();
    final srcs = g.sourceIds.toSet();
    return nodes
        .where((n) => ids.contains(n.id) || n.sourceIds.any(srcs.contains))
        .toList();
  }

  /// Лучшая нода: сначала прошедшие реальную проверку, затем живые по
  /// TCP. Внутри — по [NodeScorer] (регион, REALITY/QUIC, предпочтение UDP
  /// в режиме Discord, задержка). null — нет живых.
  ///
  /// [exclude] — ноды на карантине (сервер не отвечал при подключении):
  /// их не выбираем, даже если TCP-пинг или старая проверка «зелёные».
  ///
  /// «Заведомо медленные» (задержка выше потолка [FailoverPolicy]) берутся,
  /// только если нормальных нет совсем (#60): бонусы протокола и UDP в
  /// [NodeScorer] — тысячи «очков», и без потолка сервер с пингом 2000 мс
  /// обгонял сервер на 80 мс.
  static Node? best(
    Iterable<Node> nodes, {
    String? excludeId,
    Set<String> exclude = const {},
  }) {
    final ranked = rank(nodes, excludeId: excludeId, exclude: exclude);
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Все пригодные ноды в порядке выбора: проверенные быстрые → живые по
  /// TCP быстрые → проверенные медленные → живые медленные; внутри — по
  /// [NodeScorer], свои — раньше чужих ([ownFirst]). Мёртвые и [exclude] не
  /// входят.
  static List<Node> rank(
    Iterable<Node> nodes, {
    String? excludeId,
    Set<String> exclude = const {},
  }) {
    final pool = nodes.where((n) => n.id != excludeId && !exclude.contains(n.id)).toList();
    final fast = pool.where(FailoverPolicy.latencyAcceptable).toList();
    final slow = pool.where((n) => !FailoverPolicy.latencyAcceptable(n)).toList();
    List<Node> sorted(Iterable<Node> it) => ownFirst(it.toList()..sort(NodeScorer.compare));
    return [
      ...sorted(fast.where((n) => n.isTrulyWorking)),
      ...sorted(fast.where((n) => !n.isTrulyWorking && n.isAlive)),
      ...sorted(slow.where((n) => n.isTrulyWorking)),
      ...sorted(slow.where((n) => !n.isTrulyWorking && n.isAlive)),
    ];
  }

  /// «Свои» серверы при прочих равных — раньше чужих (#68). Внутри одного
  /// яруса [rank] (уже отсортированного [NodeScorer]) своя нода встаёт перед
  /// чужими, если её задержка не хуже лучшей чужой больше чем в
  /// 1/[FailoverPolicy.improvement] раза (≈ 133 %, тот же коэффициент
  /// «заметно лучше», что у автопрыжка #60). Задержки нет — не отсекаем.
  /// Ярусы и потолки #60 не трогаются: своя медленная нода не обгонит
  /// чужую быструю. Порядок внутри своих и внутри чужих сохраняется.
  static List<Node> ownFirst(List<Node> sorted) {
    if (!sorted.any((n) => n.isOwn) || sorted.every((n) => n.isOwn)) return sorted;
    final bestOther = sorted.firstWhere((n) => !n.isOwn);
    bool wins(Node n) {
      if (!n.isOwn) return false;
      final mine = rttMs(n);
      final theirs = rttMs(bestOther);
      if (mine == null || theirs == null) return true;
      return mine * FailoverPolicy.improvement <= theirs;
    }

    return [...sorted.where(wins), ...sorted.where((n) => !wins(n))];
  }

  /// Задержка в единицах одного RTT, чтобы сравнивать разные протоколы: у
  /// QUIC хранится время HTTPS-запроса (≈ 3 RTT, см. потолки #60).
  static double? rttMs(Node n) {
    final ms = n.latencyMs;
    if (ms == null) return null;
    return n.isQuic ? ms / 3 : ms.toDouble();
  }

  /// Кого перепроверять перед автопрыжком (#60): до [limit] лучших
  /// кандидатов с задержкой в пределах потолка — сначала из выбранной
  /// группы, потом из всех. Заведомо медленные сюда не попадают вовсе.
  /// При [preferAi] хотя бы один ИИ-годный кандидат, если такой есть.
  static List<Node> failoverShortlist({
    required String excludeId,
    required List<Node> groupNodes,
    required List<Node> allNodes,
    bool preferAi = false,
    Set<String> exclude = const {},
    int limit = FailoverPolicy.shortlistSize,
  }) {
    final seen = <String>{};
    final out = <Node>[];
    for (final pool in [groupNodes, allNodes]) {
      for (final n in rank(pool, excludeId: excludeId, exclude: exclude)) {
        if (!FailoverPolicy.latencyAcceptable(n) || !seen.add(n.id)) continue;
        out.add(n);
      }
    }
    final short = out.take(limit).toList();
    if (preferAi && short.isNotEmpty && !short.any((n) => n.aiReachable)) {
      final ai = out.skip(limit).where((n) => n.aiReachable);
      if (ai.isNotEmpty) short[short.length - 1] = ai.first;
    }
    return short;
  }

  /// Замена для упавшей ноды [excludeId].
  ///
  /// Сначала внутри [groupNodes] (выбранная автогруппа), потом по всем
  /// [allNodes]. При [preferAi] — сперва ноды с доступом к ИИ.
  static Node? failover({
    required String excludeId,
    required List<Node> groupNodes,
    required List<Node> allNodes,
    bool preferAi = false,
    Set<String> exclude = const {},
  }) {
    for (final pool in [groupNodes, allNodes]) {
      if (preferAi) {
        final ai = best(pool.where((n) => n.aiReachable), excludeId: excludeId, exclude: exclude);
        if (ai != null) return ai;
      }
      final n = best(pool, excludeId: excludeId, exclude: exclude);
      if (n != null) return n;
    }
    return null;
  }
}
