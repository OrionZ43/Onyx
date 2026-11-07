import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/node.dart';
import '../../domain/entities/node_group.dart';
import '../../domain/sources/node_pool.dart';
import '../../infrastructure/sources_store.dart';
import 'settings_provider.dart';
import 'sources_provider.dart';
import 'subscription_provider.dart';

export '../../domain/entities/node_group.dart';

/// Пользовательские группы серверов (группы-источники — в [allGroupsProvider]).
class GroupsController extends StateNotifier<List<NodeGroup>> {
  GroupsController({SourcesStore? store})
      : _store = store ?? SourcesStore(),
        super(const []) {
    _store.loadGroups().then((loaded) {
      if (!mounted) return;
      // Сливаем: группы, созданные до окончания загрузки, не теряются,
      // сохранённые — тоже.
      final have = {for (final g in loaded) g.id};
      final merged = [...loaded, for (final g in state) if (!have.contains(g.id)) g];
      final changed = merged.length != loaded.length;
      state = merged;
      if (changed) _save();
    });
  }

  final SourcesStore _store;

  static String _newId() =>
      'grp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  Future<NodeGroup> create(String name) async {
    final g = NodeGroup(id: _newId(), name: name.trim().isEmpty ? 'Группа' : name.trim());
    state = [...state, g];
    await _save();
    return g;
  }

  Future<void> rename(String id, String name) => _edit(id, (g) => g.copyWith(name: name.trim()));

  Future<void> delete(String id) async {
    state = [for (final g in state) if (g.id != id) g];
    await _save();
    // Если группа была выбрана для автовыбора — назад к «по всем».
    // (AutoGroupController проверяет существование группы сам.)
  }

  /// Семантика ReorderableListView.onReorder.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    state = list;
    await _save();
  }

  Future<void> addNodes(String groupId, Iterable<String> nodeIds) => _edit(
        groupId,
        (g) => g.copyWith(nodeIds: {...g.nodeIds, ...nodeIds}.toList()),
      );

  Future<void> removeNode(String groupId, String nodeId) => _edit(
        groupId,
        (g) => g.copyWith(nodeIds: [for (final n in g.nodeIds) if (n != nodeId) n]),
      );

  Future<void> addSource(String groupId, String sourceId) => _edit(
        groupId,
        (g) => g.copyWith(sourceIds: {...g.sourceIds, sourceId}.toList()),
      );

  Future<void> removeSource(String groupId, String sourceId) => _edit(
        groupId,
        (g) => g.copyWith(sourceIds: [for (final s in g.sourceIds) if (s != sourceId) s]),
      );

  /// Источник удалён — убираем его из групп.
  void onSourceRemoved(String sourceId) {
    if (!state.any((g) => g.sourceIds.contains(sourceId))) return;
    state = [
      for (final g in state)
        g.copyWith(sourceIds: [for (final s in g.sourceIds) if (s != sourceId) s]),
    ];
    _save();
  }

  /// Импорт: добавляет группы, которых ещё нет (по id). Возвращает число добавленных.
  Future<int> importGroups(List<NodeGroup> groups) async {
    final have = {for (final g in state) g.id};
    final add = [for (final g in groups) if (!have.contains(g.id)) g];
    if (add.isEmpty) return 0;
    state = [...state, ...add];
    await _save();
    return add.length;
  }

  Future<void> _edit(String id, NodeGroup Function(NodeGroup) f) async {
    state = [for (final g in state) g.id == id ? f(g) : g];
    await _save();
  }

  Future<void> _save() => _store.saveGroups(state);
}

final groupsProvider = StateNotifierProvider<GroupsController, List<NodeGroup>>(
  (ref) => GroupsController(),
);

/// Пользовательские группы, затем группы-источники (isVirtual).
final allGroupsProvider = Provider<List<NodeGroup>>((ref) => [
      ...ref.watch(groupsProvider),
      ...NodePool.sourceGroups(ref.watch(sourcesProvider)),
    ]);

/// Ноды группы по id: пользовательская, `src:<id>`, `auto:fav|udp|ai`;
/// '' — все включённые.
final groupNodesProvider = Provider.family<List<Node>, String>((ref, groupId) {
  return NodePool.nodesOf(
    groupId,
    ref.watch(subscriptionProvider.select((s) => s.nodes)),
    groups: ref.watch(groupsProvider),
    favorites: ref.watch(favoritesProvider),
  );
});

// ── Избранное ────────────────────────────────────────────────────────────────

class FavoritesController extends StateNotifier<Set<String>> {
  FavoritesController({SourcesStore? store})
      : _store = store ?? SourcesStore(),
        super(const {}) {
    _store.loadFavorites().then((loaded) {
      if (!mounted) return;
      final merged = {...loaded, ...state};
      final changed = merged.length != loaded.length;
      state = merged;
      if (changed) _store.saveFavorites(merged);
    });
  }

  final SourcesStore _store;

  bool isFavorite(String nodeId) => state.contains(nodeId);

  Future<void> toggleFavorite(String nodeId) async {
    state = state.contains(nodeId) ? ({...state}..remove(nodeId)) : {...state, nodeId};
    await _store.saveFavorites(state);
  }

  /// Синоним [toggleFavorite].
  Future<void> toggle(String nodeId) => toggleFavorite(nodeId);

  Future<void> addAll(Iterable<String> ids) async {
    state = {...state, ...ids};
    await _store.saveFavorites(state);
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesController, Set<String>>(
  (ref) => FavoritesController(),
);

// ── Автовыбор по группе ──────────────────────────────────────────────────────

/// Группа, в рамках которой работают автовыбор и автопереключение.
/// null — «по всем» включённым серверам.
class AutoGroupController extends StateNotifier<String?> {
  AutoGroupController({SourcesStore? store})
      : _store = store ?? SourcesStore(),
        super(null) {
    _store.loadAutoGroup().then((id) {
      // Не затираем выбор, сделанный до окончания загрузки.
      if (mounted && !_touched) state = id;
    });
  }

  final SourcesStore _store;
  bool _touched = false;

  Future<void> setAutoGroup(String? groupId) async {
    _touched = true;
    final id = (groupId ?? '').isEmpty ? null : groupId;
    state = id;
    await _store.saveAutoGroup(id);
  }
}

final autoGroupProvider = StateNotifierProvider<AutoGroupController, String?>(
  (ref) => AutoGroupController(),
);

/// Лучшая нода для «Автовыбора»: в выбранной автогруппе, с учётом региона
/// и режима Discord (через NodeScorer). Если в группе нет живых нод —
/// лучшая по всем (лучше подключиться, чем не подключиться).
final autoNodeProvider = Provider<Node?>((ref) {
  // Регион и режим Discord влияют на скоринг — пересчитываем при их смене.
  ref.watch(settingsProvider.select((s) => (s.effectiveRegion, s.discordMode)));
  final all = ref.watch(subscriptionProvider.select((s) => s.nodes));
  final bad = ref.watch(subscriptionProvider.select((s) => s.quarantined));
  final groupId = ref.watch(autoGroupProvider);
  if (groupId == null) return NodePool.best(all, exclude: bad);
  return NodePool.best(ref.watch(groupNodesProvider(groupId)), exclude: bad) ??
      NodePool.best(all, exclude: bad);
});
