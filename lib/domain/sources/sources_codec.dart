import 'dart:convert';

import 'package:crypto/crypto.dart' show sha1;

import '../entities/node.dart';
import '../entities/node_group.dart';
import '../entities/subscription_source.dart';
import '../subscription_presets.dart';

/// Состояние до появления источников (одна активная подписка).
class LegacyState {
  const LegacyState({
    this.subUrl,
    this.savedSubscriptions = const [],
    this.cachedNodes = const [],
    this.lastFetchedMs,
  });

  /// `sub_url` — активная подписка.
  final String? subUrl;

  /// `saved_subscriptions` — строки «имя||url» (или просто url).
  final List<String> savedSubscriptions;

  /// `cached_nodes` — ноды активной подписки с результатами проб.
  final List<Node> cachedNodes;

  /// `subscription_last_fetched`.
  final int? lastFetchedMs;

  bool get isEmpty => (subUrl ?? '').trim().isEmpty && savedSubscriptions.isEmpty;
}

class MigrationResult {
  const MigrationResult(this.sources, this.nodesBySource);
  final List<SubscriptionSource> sources;
  final Map<String, List<Node>> nodesBySource;
}

/// Резервная копия источников, групп и избранного.
class SourcesBackup {
  const SourcesBackup({
    required this.sources,
    this.groups = const [],
    this.favorites = const {},
  });
  final List<SubscriptionSource> sources;
  final List<NodeGroup> groups;
  final Set<String> favorites;
}

/// Идентификаторы, создание источников, миграция и экспорт/импорт.
abstract final class SourcesCodec {
  static const defaultSubscriptionAutoUpdateHours = 6;
  static const exportPrefix = 'onyx://import/';

  static String _hash(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 10);

  /// Стабильный id источника-подписки: один URL — один источник.
  static String subscriptionId(String url) {
    final preset = SubscriptionPresets.byUrl(url);
    return preset != null ? 'preset_${preset.id}' : 'sub_${_hash(url.trim())}';
  }

  static String linksId(String raw) => 'links_${_hash(raw.trim())}';

  /// Имя по умолчанию: имя пресета или хост URL.
  static String defaultName(String url) {
    final preset = SubscriptionPresets.byUrl(url);
    if (preset != null) return preset.title;
    final host = Uri.tryParse(url.trim())?.host ?? '';
    return host.isEmpty ? 'Подписка' : host;
  }

  static SubscriptionSource newSubscription(String url, {String? name, bool enabled = true}) {
    final clean = url.trim();
    final preset = SubscriptionPresets.byUrl(clean);
    return SubscriptionSource(
      id: subscriptionId(clean),
      name: (name ?? '').trim().isEmpty ? defaultName(clean) : name!.trim(),
      kind: SourceKind.subscription,
      url: clean,
      presetId: preset?.id,
      mirrors: preset?.mirrors ?? const [],
      enabled: enabled,
      autoUpdateHours: defaultSubscriptionAutoUpdateHours,
    );
  }

  static SubscriptionSource newPreset(SubscriptionPreset p) => newSubscription(p.url, name: p.title);

  static SubscriptionSource newLinks(String raw, {String? name, int count = 0}) => SubscriptionSource(
        id: linksId(raw),
        name: (name ?? '').trim().isEmpty
            ? (count == 1 ? 'Сервер' : 'Ссылки ($count)')
            : name!.trim(),
        kind: SourceKind.links,
        rawLinks: raw.trim(),
      );

  /// Миграция одной активной подписки и «сохранённых подписок» в источники.
  ///
  ///   • активная подписка → включённый источник, ей достаются кэш нод и
  ///     время последнего обновления (проверки не теряются);
  ///   • остальные сохранённые → источники, ВЫКЛЮЧЕННЫЕ: раньше их ноды не
  ///     показывались, включить можно одной кнопкой;
  ///   • дубли URL склеиваются, имя берётся из сохранённых, если было.
  static MigrationResult migrate(LegacyState legacy) {
    final sources = <SubscriptionSource>[];
    final byId = <String, int>{};
    final nodes = <String, List<Node>>{};

    final active = (legacy.subUrl ?? '').trim();
    final saved = <(String, String?)>[];
    for (final line in legacy.savedSubscriptions) {
      final parts = line.split('||');
      final url = (parts.length > 1 ? parts.sublist(1).join('||') : parts[0]).trim();
      final name = parts.length > 1 ? parts[0].trim() : null;
      if (url.isNotEmpty) saved.add((url, name));
    }
    String? savedName(String url) {
      for (final (u, n) in saved) {
        if (u == url && (n ?? '').isNotEmpty) return n;
      }
      return null;
    }

    void add(String url, {required bool enabled}) {
      final s = newSubscription(url, name: savedName(url), enabled: enabled);
      if (byId.containsKey(s.id)) return;
      byId[s.id] = sources.length;
      sources.add(s);
    }

    if (active.isNotEmpty) add(active, enabled: true);
    for (final (url, _) in saved) {
      add(url, enabled: false);
    }

    if (active.isNotEmpty) {
      final id = subscriptionId(active);
      final cached = [for (final n in legacy.cachedNodes) n.copyWith(sourceIds: [id])];
      nodes[id] = cached;
      final i = byId[id]!;
      sources[i] = sources[i].copyWith(
        nodeCount: cached.length,
        lastUpdatedAt: legacy.lastFetchedMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(legacy.lastFetchedMs!),
      );
    }
    return MigrationResult(sources, nodes);
  }

  // ── Экспорт / импорт ─────────────────────────────────────────────────────

  /// JSON без нод и результатов проб: только то, что нужно, чтобы
  /// восстановить список (подписки перезагрузятся сами).
  static String exportJson(SourcesBackup b) => const JsonEncoder.withIndent('  ').convert({
        'onyx': 'sources',
        'version': 1,
        'sources': [
          for (final s in b.sources)
            {
              ...s.toJson()..remove('nodeCount')..remove('lastUpdatedAt'),
            },
        ],
        'groups': [for (final g in b.groups) g.toJson()],
        'favorites': b.favorites.toList()..sort(),
      });

  /// Компактная ссылка `onyx://import/<base64url>` для пересылки.
  static String exportLink(SourcesBackup b) =>
      exportPrefix + base64Url.encode(utf8.encode(jsonEncode(jsonDecode(exportJson(b)))));

  /// Разбирает JSON или ссылку `onyx://import/…`. FormatException — не наш формат.
  static SourcesBackup import(String input) {
    var text = input.trim();
    if (text.startsWith(exportPrefix)) {
      var b64 = text.substring(exportPrefix.length);
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      text = utf8.decode(base64Url.decode(b64));
    }
    final Object? doc;
    try {
      doc = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Это не резервная копия Onyx');
    }
    if (doc is! Map || doc['onyx'] != 'sources') {
      throw const FormatException('Это не резервная копия Onyx');
    }
    return SourcesBackup(
      sources: [
        for (final s in (doc['sources'] as List? ?? const []))
          if (s is Map) SubscriptionSource.fromJson(Map<String, dynamic>.from(s)),
      ],
      groups: [
        for (final g in (doc['groups'] as List? ?? const []))
          if (g is Map) NodeGroup.fromJson(Map<String, dynamic>.from(g)),
      ],
      favorites: {...(doc['favorites'] as List? ?? const []).whereType<String>()},
    );
  }
}
