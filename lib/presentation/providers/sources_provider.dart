import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log_service.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/subscription_source.dart';
import '../../domain/sources/sources_codec.dart';
import '../../domain/subscription_parser.dart';
import '../../domain/subscription_presets.dart';
import '../../domain/subscription_service.dart';
import '../../infrastructure/sources_store.dart';
import 'groups_provider.dart';
import 'subscription_provider.dart';

export '../../domain/entities/subscription_source.dart';
export '../../domain/subscription_presets.dart';

/// Итог «Обновить всё»: для тоста в UI.
class RefreshReport {
  const RefreshReport({this.ok = 0, this.failed = const []});

  /// Сколько источников обновилось.
  final int ok;

  /// «Имя: причина» для источников, которые не ответили (включая все зеркала).
  final List<String> failed;

  bool get allFailed => ok == 0 && failed.isNotEmpty;

  String get summary {
    if (ok == 0 && failed.isEmpty) return 'Нет включённых источников';
    if (allFailed) return 'Не удалось обновить: ${failed.join('; ')}';
    if (failed.isEmpty) return 'Обновлено источников: $ok. Проверяем серверы…';
    return 'Обновлено: $ok, не ответили: ${failed.join('; ')}';
  }
}

/// Итог импорта резервной копии.
class ImportResult {
  const ImportResult({this.sources = 0, this.groups = 0, this.error});
  final int sources;
  final int groups;
  final String? error;
  bool get ok => error == null;
}

/// Источники серверов: подписки по URL и наборы ссылок.
///
/// Владеет списком источников и «сырыми» нодами каждого. Склейку,
/// пробы и выбор делает [SubscriptionController] (subscriptionProvider),
/// которому контроллер сообщает об изменениях через syncFromSources().
class SourcesController extends StateNotifier<List<SubscriptionSource>> {
  SourcesController(this._ref, {SourcesStore? store, SubscriptionService? service})
      : _store = store ?? SourcesStore(),
        _service = service ?? SubscriptionService(),
        super(const []) {
    _init();
  }

  final Ref _ref;
  final SourcesStore _store;
  final SubscriptionService _service;
  final Map<String, List<Node>> _nodes = {};
  final _ready = Completer<void>();
  Timer? _autoTimer;

  /// Текст последней ошибки добавления (для тоста, если add* вернул null).
  String? lastError;

  /// Сырые ноды по источникам (без склейки и проб).
  Map<String, List<Node>> get nodesBySource => Map.unmodifiable(_nodes);

  /// Завершается, когда источники загружены (и при необходимости мигрированы).
  Future<void> get ready => _ready.future;

  /// Источники уже загружены с диска.
  bool get isLoaded => _ready.isCompleted;

  bool hasPreset(String presetId) => state.any((s) => s.presetId == presetId);

  SubscriptionSource? byId(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _init() async {
    try {
      final data = await _store.loadOrMigrate();
      if (!mounted) return;
      _nodes
        ..clear()
        ..addAll(data.nodesBySource);
      state = data.sources;
    } catch (e) {
      log.e('Источники не загрузились: $e', tag: 'SOURCES');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
    _sync(probeNew: false);
    _autoTimer = Timer.periodic(const Duration(minutes: 15), (_) => refreshDue());
    unawaited(refreshDue());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  // ── Добавление ───────────────────────────────────────────────────────────

  /// Добавляет подписку по URL. Если вместо URL вставлены ссылки или
  /// base64 — добавляет их как набор ссылок. Тот же URL второй раз не
  /// добавляется: существующий источник обновляется и включается.
  /// null — загрузить не удалось (причина в [lastError]), источник не создаётся.
  Future<SubscriptionSource?> addSubscription(String url, {String? name}) async {
    await ready;
    lastError = null;
    final input = url.trim();
    if (input.isEmpty) {
      lastError = 'Пустая ссылка';
      return null;
    }
    final unsupported = SubscriptionParser.unsupportedReason(input);
    if (unsupported != null) {
      lastError = unsupported;
      return null;
    }
    if (SubscriptionParser.looksLikeContent(input)) {
      return addLinks(input, name: name);
    }
    final fresh = SourcesCodec.newSubscription(input, name: name);
    final existing = byId(fresh.id);
    if (existing != null) {
      if (!existing.enabled) await setEnabled(existing.id, true);
      await refresh(existing.id);
      return byId(existing.id);
    }
    state = [...state, fresh.copyWith(status: SourceStatus.fetching)];
    final ok = await _load(fresh.id);
    if (!ok) {
      lastError = byId(fresh.id)?.error ?? 'Не удалось загрузить подписку';
      await _drop(fresh.id);
      return null;
    }
    await _persist();
    return byId(fresh.id);
  }

  /// Добавляет одну или несколько ссылок (vless://, hy2://, …), base64 или
  /// текст Clash/sing-box как один источник. Повторная вставка того же
  /// текста возвращает существующий источник.
  Future<SubscriptionSource?> addLinks(String raw, {String? name}) async {
    await ready;
    lastError = null;
    final result = _service.parseContent(raw.trim());
    if (!result.isSuccess || result.nodes.isEmpty) {
      lastError = SubscriptionParser.unsupportedReason(raw) ??
          result.error ??
          'Не найдено ни одной ссылки на сервер';
      return null;
    }
    final source = SourcesCodec.newLinks(raw, name: name, count: result.nodes.length);
    final existing = byId(source.id);
    if (existing != null) return existing;
    _nodes[source.id] = [for (final n in result.nodes) n.copyWith(sourceIds: [source.id])];
    state = [
      ...state,
      source.copyWith(nodeCount: result.nodes.length, lastUpdatedAt: DateTime.now()),
    ];
    await _store.saveNodes(source.id, _nodes[source.id]!);
    await _persist();
    _sync(probeNew: true);
    return byId(source.id);
  }

  /// Добавляет встроенный пресет как обычный источник (не заменяя другие).
  /// Если пресет уже есть — включает и возвращает его.
  Future<SubscriptionSource?> addPreset(SubscriptionPreset preset) async {
    await ready;
    for (final s in state) {
      if (s.presetId == preset.id) {
        if (!s.enabled) await setEnabled(s.id, true);
        return byId(s.id);
      }
    }
    return addSubscription(preset.url, name: preset.title);
  }

  // ── Управление ───────────────────────────────────────────────────────────

  Future<void> rename(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    _update(id, (s) => s.copyWith(name: n));
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _update(id, (s) => s.copyWith(enabled: enabled));
    await _persist();
    _sync(probeNew: enabled);
  }

  Future<void> setAutoUpdate(String id, int hours) async {
    _update(id, (s) => s.copyWith(autoUpdateHours: hours < 0 ? 0 : hours));
    await _persist();
  }

  /// Перезагружает источник (подписку — из сети с зеркалами, ссылки —
  /// перепарсивает). false — не удалось (причина в source.error).
  Future<bool> refresh(String id, {bool probe = true}) async {
    await ready;
    if (byId(id) == null) return false;
    final ok = await _load(id, probe: probe);
    if (ok) await _persist();
    return ok;
  }

  /// «Обновить»: перезагружает все включённые источники и ПЕРЕПРОВЕРЯЕТ все
  /// серверы (раньше проверялись только новые ноды — если состав не
  /// менялся, кнопка «ничего не делала»). Пока идёт загрузка, у
  /// subscriptionProvider статус fetching (крутилка в UI); если не ответил
  /// ни один источник — статус error с понятной причиной.
  Future<RefreshReport> refreshAll() async {
    await ready;
    final sub = _ref.read(subscriptionProvider.notifier);
    sub.beginRefresh();
    var ok = 0;
    final failed = <String>[];
    for (final s in List.of(state)) {
      if (!s.enabled) continue;
      if (await refresh(s.id, probe: false)) {
        ok++;
      } else {
        failed.add('${s.name}: ${byId(s.id)?.error ?? 'нет ответа'}');
      }
    }
    final report = RefreshReport(ok: ok, failed: failed);
    log.i(report.summary, tag: 'SOURCES');
    sub.endRefresh(error: report.allFailed ? report.summary : null);
    // Перепроверяем всё, что есть (и старые ноды тоже): мёртвые отсеются.
    unawaited(sub.reprobe());
    return report;
  }

  /// Обновляет источники, у которых подошло время автообновления.
  Future<void> refreshDue() async {
    await ready;
    final now = DateTime.now();
    for (final s in List.of(state)) {
      if (s.isDue(now)) await refresh(s.id);
    }
  }

  Future<void> remove(String id) async {
    await _drop(id);
    _ref.read(groupsProvider.notifier).onSourceRemoved(id);
    await _persist();
  }

  /// Семантика ReorderableListView.onReorder.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, state.length - 1);
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    await _persist();
    _sync(probeNew: false); // порядок влияет на склейку дублей
  }

  // ── Экспорт / импорт ─────────────────────────────────────────────────────

  SourcesBackup _backup() => SourcesBackup(
        sources: state,
        groups: _ref.read(groupsProvider),
        favorites: _ref.read(favoritesProvider),
      );

  /// JSON со списком источников, группами и избранным (без нод).
  String exportJson() => SourcesCodec.exportJson(_backup());

  /// То же одной строкой-ссылкой `onyx://import/…`.
  String exportLink() => SourcesCodec.exportLink(_backup());

  /// Импорт JSON или ссылки `onyx://import/…`: добавляет недостающие
  /// источники и группы, объединяет избранное. Ничего не удаляет.
  Future<ImportResult> importJson(String input) async {
    await ready;
    final SourcesBackup b;
    try {
      b = SourcesCodec.import(input);
    } on FormatException catch (e) {
      return ImportResult(error: e.message);
    }
    final added = <SubscriptionSource>[];
    for (final s in b.sources) {
      if (byId(s.id) != null) continue;
      added.add(s.copyWith(nodeCount: 0));
    }
    state = [...state, ...added];
    await _persist();
    final groups = await _ref.read(groupsProvider.notifier).importGroups(b.groups);
    await _ref.read(favoritesProvider.notifier).addAll(b.favorites);
    for (final s in added) {
      if (s.enabled) await refresh(s.id);
    }
    return ImportResult(sources: added.length, groups: groups);
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  Future<bool> _load(String id, {bool probe = true}) async {
    final src = byId(id);
    if (src == null) return false;
    _update(id, (s) => s.copyWith(status: SourceStatus.fetching, clearError: true));

    final SubscriptionResult result;
    if (src.kind == SourceKind.links) {
      result = _service.parseContent(src.rawLinks ?? '');
    } else {
      result = await _service.fetch(src.url ?? '', mirrors: src.mirrors);
    }
    if (!mounted) return false;

    if (!result.isSuccess || result.nodes.isEmpty) {
      _update(id, (s) => s.copyWith(
            status: SourceStatus.error,
            error: result.error ?? 'Пустая подписка',
          ));
      return false;
    }
    final nodes = [for (final n in result.nodes) n.copyWith(sourceIds: [id])];
    _nodes[id] = nodes;
    _update(id, (s) => s.copyWith(
          status: SourceStatus.idle,
          nodeCount: nodes.length,
          lastUpdatedAt: DateTime.now(),
          clearError: true,
        ));
    await _store.saveNodes(id, nodes);
    _sync(probeNew: probe);
    return true;
  }

  Future<void> _drop(String id) async {
    state = [for (final s in state) if (s.id != id) s];
    _nodes.remove(id);
    await _store.deleteNodes(id);
    _sync(probeNew: false);
  }

  void _update(String id, SubscriptionSource Function(SubscriptionSource) f) {
    if (!mounted) return;
    state = [for (final s in state) s.id == id ? f(s) : s];
  }

  Future<void> _persist() => _store.saveSources(state);

  void _sync({required bool probeNew}) {
    if (!mounted) return;
    _ref.read(subscriptionProvider.notifier).syncFromSources(probeNew: probeNew);
  }
}

final sourcesProvider =
    StateNotifierProvider<SourcesController, List<SubscriptionSource>>(
  (ref) => SourcesController(ref),
);
