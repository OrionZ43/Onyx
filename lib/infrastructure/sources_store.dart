import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/log_service.dart';
import '../domain/entities/node.dart';
import '../domain/entities/node_group.dart';
import '../domain/entities/subscription_source.dart';
import '../domain/sources/sources_codec.dart';

/// Хранение источников, их нод, групп, избранного и автогруппы.
///
/// Ключи SharedPreferences:
///   sources_v1            — JSON-список источников (порядок = порядок в UI);
///   source_nodes_<id>     — ноды источника (как пришли из подписки);
///   groups_v1             — JSON-список пользовательских групп;
///   favorites_v1          — id избранных нод;
///   auto_group_v1         — группа автовыбора (нет ключа = «по всем»);
///   sources_migrated_v1   — миграция со старой схемы выполнена.
/// Результаты проб по-прежнему лежат в `cached_nodes` (subscriptionProvider).
class SourcesStore {
  SourcesStore([this._prefsOverride]);

  final SharedPreferences? _prefsOverride;
  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  static const _sourcesKey = 'sources_v1';
  static const _nodesPrefix = 'source_nodes_';
  static const _groupsKey = 'groups_v1';
  static const _favoritesKey = 'favorites_v1';
  static const _autoGroupKey = 'auto_group_v1';
  static const _migratedKey = 'sources_migrated_v1';

  // Старая схема.
  static const legacySubUrlKey = 'sub_url';
  static const legacySavedKey = 'saved_subscriptions';
  static const legacyCacheKey = 'cached_nodes';
  static const legacyFetchedKey = 'subscription_last_fetched';

  /// Загружает источники; при первом запуске новой версии — мигрирует.
  Future<MigrationResult> loadOrMigrate() async {
    final p = await _prefs;
    if (p.getBool(_migratedKey) != true) {
      final legacy = LegacyState(
        subUrl: p.getString(legacySubUrlKey),
        savedSubscriptions: p.getStringList(legacySavedKey) ?? const [],
        cachedNodes: _decodeNodes(p.getStringList(legacyCacheKey)),
        lastFetchedMs: p.getInt(legacyFetchedKey),
      );
      final result = SourcesCodec.migrate(legacy);
      await saveSources(result.sources);
      for (final e in result.nodesBySource.entries) {
        await saveNodes(e.key, e.value);
      }
      await p.setBool(_migratedKey, true);
      // Старые ключи не удаляем: при откате на прошлую версию всё на месте.
      log.i('Миграция подписок: ${result.sources.length} источник(ов)', tag: 'SOURCES');
      return result;
    }
    final sources = _decodeSources(p.getString(_sourcesKey));
    return MigrationResult(sources, {
      for (final s in sources) s.id: _decodeNodes(p.getStringList('$_nodesPrefix${s.id}')),
    });
  }

  Future<void> saveSources(List<SubscriptionSource> sources) async {
    final p = await _prefs;
    await p.setString(_sourcesKey, jsonEncode([for (final s in sources) s.toJson()]));
  }

  Future<void> saveNodes(String sourceId, List<Node> nodes) async {
    final p = await _prefs;
    await p.setStringList(
      '$_nodesPrefix$sourceId',
      [for (final n in nodes) jsonEncode(n.toJson())],
    );
  }

  Future<void> deleteNodes(String sourceId) async {
    final p = await _prefs;
    await p.remove('$_nodesPrefix$sourceId');
  }

  Future<List<NodeGroup>> loadGroups() async {
    final raw = (await _prefs).getString(_groupsKey);
    if (raw == null) return const [];
    try {
      return [
        for (final g in jsonDecode(raw) as List)
          if (g is Map) NodeGroup.fromJson(Map<String, dynamic>.from(g)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveGroups(List<NodeGroup> groups) async {
    await (await _prefs).setString(_groupsKey, jsonEncode([for (final g in groups) g.toJson()]));
  }

  Future<Set<String>> loadFavorites() async =>
      ((await _prefs).getStringList(_favoritesKey) ?? const []).toSet();

  Future<void> saveFavorites(Set<String> ids) async {
    await (await _prefs).setStringList(_favoritesKey, ids.toList()..sort());
  }

  Future<String?> loadAutoGroup() async => (await _prefs).getString(_autoGroupKey);

  Future<void> saveAutoGroup(String? id) async {
    final p = await _prefs;
    if (id == null) {
      await p.remove(_autoGroupKey);
    } else {
      await p.setString(_autoGroupKey, id);
    }
  }

  static List<SubscriptionSource> _decodeSources(String? raw) {
    if (raw == null) return const [];
    try {
      return [
        for (final s in jsonDecode(raw) as List)
          if (s is Map) SubscriptionSource.fromJson(Map<String, dynamic>.from(s)),
      ];
    } catch (e) {
      log.e('Не удалось прочитать источники: $e', tag: 'SOURCES');
      return const [];
    }
  }

  static List<Node> _decodeNodes(List<String>? raw) {
    if (raw == null) return const [];
    final out = <Node>[];
    for (final s in raw) {
      try {
        out.add(Node.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }
}
