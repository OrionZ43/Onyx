import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/subscription_source.dart';
import '../../domain/smart_probe.dart';
import '../../domain/sources/node_pool.dart';
import '../../infrastructure/binary_manager.dart';
import 'sources_provider.dart';

// ── SubStatus ─────────────────────────────────────────────────────────────────

enum SubStatus {
  idle,
  fetching,
  probing, // Этап 1: параллельный TCP-пинг
  deepProbing, // Этап 2: реальный HTTP-запрос через sing-box
  ready,
  error,
}

// ── SubscriptionState ─────────────────────────────────────────────────────────

/// Итоговый пул серверов: склейка ВКЛЮЧЁННЫХ источников (sourcesProvider)
/// с результатами проверок. Источники, группы и избранное — в
/// sources_provider.dart и groups_provider.dart.
class SubscriptionState {
  const SubscriptionState({
    this.status = SubStatus.idle,
    this.nodes = const [],
    this.url = '',
    this.error,
    this.probedCount = 0,
    this.probeTotal = 0,
    this.deepProbedCount = 0,
    this.deepProbeTotal = 0,
    this.lastFetchedAt,
    this.isStale = false,
    this.quarantined = const {},
  });

  /// Ноды на карантине: сервер не ответил при подключении (connect timeout,
  /// туннель мёртв). Автовыбор и автопереключение их пропускают, пока
  /// Deep Probe снова не подтвердит работу или не истечёт срок (30 мин).
  final Set<String> quarantined;

  final SubStatus status;
  final List<Node> nodes;

  /// Совместимость: URL последней добавленной через loadFromUrl или первой
  /// включённой подписки. Для «обновить» используйте
  /// sourcesProvider.notifier.refreshAll().
  final String url;
  final String? error;
  final bool isStale;

  /// Сколько нод прошли TCP-пинг в текущем проходе (прогресс Этапа 1).
  final int probedCount;

  /// Сколько нод проверяется в текущем проходе Этапа 1.
  final int probeTotal;

  /// Сколько нод прошли Deep Probe (прогресс Этапа 2).
  final int deepProbedCount;
  final int deepProbeTotal;

  /// Самое свежее обновление среди включённых источников.
  final DateTime? lastFetchedAt;

  List<Node> get aliveNodes => nodes.where((n) => n.isAlive).toList();

  bool get isSubscriptionStale => isStale;

  /// Лучшая нода по ВСЕМ включённым источникам. Для выбора с учётом
  /// автогруппы — autoNodeProvider (groups_provider.dart).
  Node? get bestNode => NodePool.best(nodes, exclude: quarantined);

  /// Лучшая нода с доступом к ИИ; если таких нет — [bestNode].
  Node? get bestAiNode =>
      NodePool.best(nodes.where((n) => n.aiReachable), exclude: quarantined) ?? bestNode;

  int get aiReachableCount => nodes.where((n) => n.aiReachable).length;

  SubscriptionState copyWith({
    SubStatus? status,
    List<Node>? nodes,
    String? url,
    String? error,
    int? probedCount,
    int? probeTotal,
    int? deepProbedCount,
    int? deepProbeTotal,
    DateTime? lastFetchedAt,
    bool? isStale,
    Set<String>? quarantined,
  }) =>
      SubscriptionState(
        status: status ?? this.status,
        nodes: nodes ?? this.nodes,
        url: url ?? this.url,
        error: error,
        probedCount: probedCount ?? this.probedCount,
        probeTotal: probeTotal ?? this.probeTotal,
        deepProbedCount: deepProbedCount ?? this.deepProbedCount,
        deepProbeTotal: deepProbeTotal ?? this.deepProbeTotal,
        lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
        isStale: isStale ?? this.isStale,
        quarantined: quarantined ?? this.quarantined,
      );
}

// ── SubscriptionController ────────────────────────────────────────────────────

class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController(this._ref) : super(const SubscriptionState()) {
    // Поднимаем контроллер источников: после загрузки/миграции он сам
    // вызовет syncFromSources(). Кэш проб читаем параллельно; когда он
    // прочитан, пересобираем пул, чтобы вернуть ноды их пинг и флаги.
    _ref.read(sourcesProvider);
    _loadCache().then((_) {
      if (mounted) syncFromSources(probeNew: false);
    });
  }

  final Ref _ref;
  final _probe = const SmartProbe();
  static const _cacheKey = 'cached_nodes';
  static const _staleAfter = Duration(minutes: 30);
  Timer? _staleTimer;

  /// Результаты проб из прошлого запуска — для склейки до первой проверки.
  final Map<String, Node> _probeCache = {};

  /// id нод, уже прошедших TCP-пинг (в этом запуске или раньше).
  final Set<String> _probedIds = {};

  bool _busy = false;

  /// Идёт проверка нод (TCP/Deep Probe).
  bool get isProbing => _busy;
  final Set<String> _pending = {};

  @override
  void dispose() {
    _staleTimer?.cancel();
    super.dispose();
  }

  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Совместимость со старым UI: добавляет подписку (или ссылки) как
  /// источник — либо обновляет существующий с тем же URL. Ничего не заменяет.
  Future<void> loadFromUrl(String url) async {
    state = state.copyWith(status: SubStatus.fetching, url: url.trim());
    final sources = _ref.read(sourcesProvider.notifier);
    final added = await sources.addSubscription(url);
    if (!mounted) return;
    if (added == null) {
      state = state.copyWith(status: SubStatus.error, error: sources.lastError);
    } else if (!_busy && state.status == SubStatus.fetching) {
      state = state.copyWith(status: SubStatus.ready);
    }
  }

  /// Пересобрать пул из источников. Вызывается SourcesController-ом после
  /// любого изменения. [probeNew] — проверить ноды, которых ещё не пинговали.
  void syncFromSources({bool probeNew = true}) {
    if (!mounted) return;
    // До загрузки источников пул не трогаем: на экране кэш прошлого запуска.
    if (!_ref.read(sourcesProvider.notifier).isLoaded) return;
    final sources = _ref.read(sourcesProvider);
    final bySource = _ref.read(sourcesProvider.notifier).nodesBySource;
    final previous = {..._probeCache, for (final n in state.nodes) n.id: n};
    final merged = NodePool.merge(sources, bySource, previous: previous.values);

    DateTime? last;
    String firstUrl = '';
    for (final s in sources) {
      if (!s.enabled) continue;
      if (firstUrl.isEmpty && s.kind == SourceKind.subscription) firstUrl = s.url ?? '';
      final t = s.lastUpdatedAt;
      if (t != null && (last == null || t.isAfter(last))) last = t;
    }

    state = state.copyWith(
      nodes: merged,
      url: state.url.isNotEmpty && sources.any((s) => s.url == state.url) ? state.url : firstUrl,
      lastFetchedAt: last,
      status: state.status == SubStatus.idle && merged.isNotEmpty ? SubStatus.ready : state.status,
    );
    if (last != null) _scheduleStaleCheck(last);
    _saveCache(merged);

    if (probeNew) {
      final fresh = {for (final n in merged) if (!_probedIds.contains(n.id)) n.id};
      if (fresh.isNotEmpty) unawaited(_probeIds(fresh));
    }
  }

  /// Начало «Обновить всё» (SourcesController.refreshAll): крутилка в UI.
  void beginRefresh() {
    if (!mounted) return;
    state = state.copyWith(status: SubStatus.fetching);
  }

  /// Конец загрузки источников. [error] — не ответил ни один источник.
  void endRefresh({String? error}) {
    if (!mounted) return;
    if (error != null) {
      state = state.copyWith(status: SubStatus.error, error: error);
    } else if (state.status == SubStatus.fetching) {
      state = state.copyWith(status: SubStatus.ready);
    }
  }

  /// Повторная проверка всех нод пула.
  Future<void> reprobe() async {
    if (state.nodes.isEmpty) return;
    await _probeIds({for (final n in state.nodes) n.id});
  }

  /// Нода не работает при реальном подключении (туннель не отвечает):
  /// помечаем мёртвой и ставим на карантин — автовыбор и автопереключение
  /// её пропускают, даже если следующий TCP-пинг снова «зелёный» (порт
  /// открыт, а прокси не работает). Снимается подтверждением Deep Probe
  /// или через [quarantineTtl].
  void markNodeAsDead(String nodeId) {
    _quarantine[nodeId] = DateTime.now();
    state = state.copyWith(
      nodes: [
        for (final n in state.nodes)
          n.id == nodeId ? n.copyWith(isAlive: false, isTrulyWorking: false) : n,
      ],
      quarantined: _activeQuarantine(),
    );
  }

  static const quarantineTtl = Duration(minutes: 30);
  final Map<String, DateTime> _quarantine = {};

  Set<String> _activeQuarantine() {
    final now = DateTime.now();
    _quarantine.removeWhere((_, t) => now.difference(t) >= quarantineTtl);
    return Set.unmodifiable(_quarantine.keys);
  }

  void _liftQuarantine(String nodeId) {
    if (_quarantine.remove(nodeId) != null) {
      state = state.copyWith(quarantined: _activeQuarantine());
    }
  }

  // ── Проверки ───────────────────────────────────────────────────────────────

  /// TCP-пинг и Deep Probe для нод [ids]. Если проверка уже идёт — ноды
  /// встают в очередь и проверятся следующим проходом.
  Future<void> _probeIds(Set<String> ids) async {
    if (_busy) {
      _pending.addAll(ids);
      return;
    }
    _busy = true;
    try {
      var batch = ids;
      while (batch.isNotEmpty && mounted) {
        await _runProbe(batch);
        batch = {..._pending};
        _pending.clear();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _runProbe(Set<String> ids) async {
    final targets = state.nodes.where((n) => ids.contains(n.id)).toList();
    if (targets.isEmpty) return;
    state = state.copyWith(
      status: SubStatus.probing,
      probedCount: 0,
      probeTotal: targets.length,
      deepProbedCount: 0,
      deepProbeTotal: 0,
      isStale: false,
    );

    // ─── Этап 1: TCP-пинг ──────────────────────────────────────────────
    final probed = await _probe.probeAll(
      targets,
      onProgress: (done, total) {
        if (mounted) state = state.copyWith(status: SubStatus.probing, probedCount: done);
      },
    );
    if (!mounted) return;
    _probedIds.addAll(probed.map((n) => n.id));
    _apply(probed, (cur, upd) => cur.copyWith(
          isAlive: upd.isAlive,
          latencyMs: upd.latencyMs,
          // При повторной проверке сбрасываем «работает», пока Deep Probe не
          // подтвердит заново — иначе мёртвая нода висела бы зелёной.
          isTrulyWorking: upd.isAlive ? cur.isTrulyWorking : false,
        ));
    state = state.copyWith(status: SubStatus.ready, probedCount: probed.length);
    _saveCache(state.nodes);

    // ─── Этап 2: Deep Probe (реальный HTTPS + AI + UDP) ───────────────
    await _runDeepProbe(probed);
  }

  Future<void> _runDeepProbe(List<Node> sortedNodes) async {
    final aliveCount = sortedNodes.where((n) => n.isAlive).length;
    if (aliveCount == 0) return;
    final binMgr = BinaryManager.instance;
    if (!binMgr.isReady) return;

    if (mounted) {
      state = state.copyWith(
        status: SubStatus.deepProbing,
        deepProbedCount: 0,
        deepProbeTotal: aliveCount,
      );
    }

    await DeepProbe(singboxExePath: binMgr.singboxExe.path).probeAllNodes(
      sortedNodes,
      onNodeResult: (u) {
        if (!mounted) return;
        // Deep Probe подтвердил реальную работу — снимаем карантин.
        if (u.isTrulyWorking) _liftQuarantine(u.id);
        _apply([u], (cur, upd) => cur.copyWith(
              isTrulyWorking: upd.isTrulyWorking,
              aiReachable: upd.aiReachable,
              udpSupported: upd.udpSupported,
              latencyMs: upd.latencyMs,
            ));
      },
      onProgress: (done, total) {
        if (mounted) {
          state = state.copyWith(
            status: SubStatus.deepProbing,
            deepProbedCount: done,
            deepProbeTotal: total,
          );
        }
      },
      isCancelled: () => !mounted,
    );

    if (!mounted) return;
    _saveCache(state.nodes);
    state = state.copyWith(status: SubStatus.ready);
  }

  /// Вливает результаты проб в ТЕКУЩИЙ пул (он мог измениться, пока шла
  /// проверка: источник выключили или обновили) — по id, порядок не трогаем.
  void _apply(List<Node> updates, Node Function(Node cur, Node upd) f) {
    final byId = {for (final u in updates) u.id: u};
    state = state.copyWith(nodes: [
      for (final n in state.nodes) byId.containsKey(n.id) ? f(n, byId[n.id]!) : n,
    ]);
    for (final u in updates) {
      final cur = state.nodes.where((n) => n.id == u.id);
      if (cur.isNotEmpty) _probeCache[u.id] = cur.first;
    }
  }

  // ── Кэш и «устаревание» ───────────────────────────────────────────────────

  void _scheduleStaleCheck(DateTime lastFetched) {
    _staleTimer?.cancel();
    final staleTime = lastFetched.add(_staleAfter);
    final now = DateTime.now();
    if (!now.isBefore(staleTime)) {
      if (!state.isStale && mounted) state = state.copyWith(isStale: true);
      return;
    }
    if (state.isStale && mounted) state = state.copyWith(isStale: false);
    _staleTimer = Timer(staleTime.difference(now), () {
      if (mounted) state = state.copyWith(isStale: true);
    });
  }

  Future<void> _saveCache(List<Node> nodes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cacheKey, [for (final n in nodes) jsonEncode(n.toJson())]);
  }

  /// Кэш результатов проб прошлого запуска. Ноды показываем сразу (до
  /// загрузки источников), чтобы экран не был пустым.
  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_cacheKey) ?? const [];
    for (final s in cached) {
      try {
        final n = Node.fromJson(jsonDecode(s) as Map<String, dynamic>);
        _probeCache[n.id] = n;
        if (n.isAlive || n.latencyMs != null || n.isTrulyWorking) _probedIds.add(n.id);
      } catch (_) {}
    }
    if (mounted && state.nodes.isEmpty && _probeCache.isNotEmpty) {
      state = state.copyWith(nodes: _probeCache.values.toList(), status: SubStatus.ready);
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final subscriptionProvider =
    StateNotifierProvider<SubscriptionController, SubscriptionState>(
  (ref) => SubscriptionController(ref),
);
