import '../entities/node.dart';
import '../entities/node_group.dart';
import '../entities/subscription_source.dart';
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
      for (final n in nodesBySource[s.id] ?? const <Node>[]) {
        final existing = out[n.id];
        if (existing != null) {
          if (!existing.sourceIds.contains(s.id)) {
            out[n.id] = existing.copyWith(sourceIds: [...existing.sourceIds, s.id]);
          }
          continue;
        }
        var merged = n.copyWith(sourceIds: [s.id]);
        final p = prev[n.id];
        if (p != null) {
          merged = merged.copyWith(
            latencyMs: p.latencyMs,
            isAlive: p.isAlive,
            isTrulyWorking: p.isTrulyWorking,
            aiReachable: p.aiReachable,
            udpSupported: p.udpSupported,
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
  /// null / '' — все; `src:<id>` — источник; `auto:fav|udp|ai` — фильтры;
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
  static Node? best(
    Iterable<Node> nodes, {
    String? excludeId,
    Set<String> exclude = const {},
  }) {
    final pool = nodes.where((n) => n.id != excludeId && !exclude.contains(n.id)).toList();
    final verified = pool.where((n) => n.isTrulyWorking).toList()..sort(NodeScorer.compare);
    if (verified.isNotEmpty) return verified.first;
    final alive = pool.where((n) => n.isAlive).toList()..sort(NodeScorer.compare);
    return alive.isEmpty ? null : alive.first;
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
