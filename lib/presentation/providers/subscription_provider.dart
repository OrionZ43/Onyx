import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/node.dart';
import '../../domain/subscription_service.dart';
import '../../domain/smart_probe.dart';
import '../../infrastructure/binary_manager.dart';

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

class SubscriptionState {
  const SubscriptionState({
    this.status = SubStatus.idle,
    this.nodes = const [],
    this.url = '',
    this.error,
    this.probedCount = 0,
    this.deepProbedCount = 0,
    this.deepProbeTotal = 0,
    this.lastFetchedAt,
    this.isStale = false,
  });

  final SubStatus status;
  final List<Node> nodes;
  final String url;
  final String? error;
  final bool isStale;

  /// Количество нод, прошедших TCP-пинг (для прогресс-бара Этапа 1).
  final int probedCount;

  /// Количество нод, прошедших Deep Probe (для прогресс-бара Этапа 2).
  final int deepProbedCount;

  /// Сколько нод всего проверяется на Этапе 2 (топ-10).
  final int deepProbeTotal;
  final DateTime? lastFetchedAt;

  List<Node> get aliveNodes => nodes.where((n) => n.isAlive).toList();

  /// Лучшая нода для подключения.
  ///
  /// Приоритет:
  ///   1. Первая нода с isTrulyWorking = true (прошла HTTP-проверку).
  ///   2. Если Deep Probe ещё не завершён — нода с минимальным TCP-пингом.
  bool get isSubscriptionStale => isStale;

  Node? get bestNode {
    // Приоритет: реально проверенная нода
    final verified = nodes.where((n) => n.isTrulyWorking).toList();
    if (verified.isNotEmpty) {
      verified.sort(
        (a, b) => (a.latencyMs ?? 9999).compareTo(b.latencyMs ?? 9999),
      );
      return verified.first;
    }

    // Fallback: лучший по TCP-пингу
    final alive = aliveNodes
      ..sort((a, b) => (a.latencyMs ?? 9999).compareTo(b.latencyMs ?? 9999));
    return alive.isEmpty ? null : alive.first;
  }

  SubscriptionState copyWith({
    SubStatus? status,
    List<Node>? nodes,
    String? url,
    String? error,
    int? probedCount,
    int? deepProbedCount,
    int? deepProbeTotal,
    DateTime? lastFetchedAt,
    bool? isStale,
  }) =>
      SubscriptionState(
        status: status ?? this.status,
        nodes: nodes ?? this.nodes,
        url: url ?? this.url,
        error: error,
        probedCount: probedCount ?? this.probedCount,
        deepProbedCount: deepProbedCount ?? this.deepProbedCount,
        deepProbeTotal: deepProbeTotal ?? this.deepProbeTotal,
        lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
        isStale: isStale ?? this.isStale,
      );
}

// ── SubscriptionController ────────────────────────────────────────────────────

class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController() : super(const SubscriptionState()) {
    _loadSavedUrl();
  }

  final _service = SubscriptionService();
  final _probe = const SmartProbe();
  static const _urlKey = 'sub_url';
  Timer? _staleTimer;

  @override
  void dispose() {
    _staleTimer?.cancel();
    super.dispose();
  }

  void _scheduleStaleCheck(DateTime lastFetched) {
    _staleTimer?.cancel();
    final now = DateTime.now();
    final staleTime = lastFetched.add(const Duration(minutes: 30));

    if (now.isAfter(staleTime) || now.isAtSameMomentAs(staleTime)) {
      if (!state.isStale && mounted) {
        state = state.copyWith(isStale: true);
      }
    } else {
      if (state.isStale && mounted) {
        state = state.copyWith(isStale: false);
      }
      final duration = staleTime.difference(now);
      _staleTimer = Timer(duration, () {
        if (mounted) {
          state = state.copyWith(isStale: true);
        }
      });
    }
  }

  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Загрузить подписку по URL и запустить двухэтапную проверку.
  Future<void> loadFromUrl(String url) async {
    if (state.status == SubStatus.fetching ||
        state.status == SubStatus.probing ||
        state.status == SubStatus.deepProbing) {
      return;
    }

    state = state.copyWith(
      status: SubStatus.fetching,
      url: url,
      probedCount: 0,
      deepProbedCount: 0,
      deepProbeTotal: 0,
      isStale: false,
    );

    // ─── Этап 0: Загрузка и парсинг ──────────────────────────────────────
    final result = await _service.fetch(url);
    if (!result.isSuccess) {
      if (mounted) {
        state = state.copyWith(status: SubStatus.error, error: result.error);
      }
      return;
    }

    // ─── Этап 1: TCP-пинг всех нод ───────────────────────────────────────
    if (mounted) {
      state = state.copyWith(
        status: SubStatus.probing,
        nodes: result.nodes,
        probedCount: 0,
      );
    }

    final probed = await _probe.probeAll(
      result.nodes,
      onProgress: (done, total) {
        if (mounted) {
          state = state.copyWith(status: SubStatus.probing, probedCount: done);
        }
      },
    );

    // Сохраняем URL сразу после TCP-пинга — пользователь уже видит серверы
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
    final fetchTime = DateTime.now();
    await prefs.setInt(
        'subscription_last_fetched', fetchTime.millisecondsSinceEpoch);

    _saveCache(probed);
    _scheduleStaleCheck(fetchTime);

    if (!mounted) return;
    state = state.copyWith(
      status: SubStatus.ready, // UI показывает результаты Этапа 1
      nodes: probed,
      probedCount: probed.length,
      lastFetchedAt: fetchTime,
    );

    // ─── Этап 2: Deep Probe (реальный HTTP) для топ-10 нод ───────────────
    await _runDeepProbe(probed);
  }

  /// Повторная проверка уже загруженных нод.
  Future<void> reprobe() async {
    if (state.nodes.isEmpty) return;
    if (state.status == SubStatus.fetching ||
        state.status == SubStatus.probing ||
        state.status == SubStatus.deepProbing) {
      return;
    }
    state = state.copyWith(
      status: SubStatus.probing,
      probedCount: 0,
      deepProbedCount: 0,
      deepProbeTotal: 0,
      isStale: false,
    );

    final probed = await _probe.probeAll(
      state.nodes,
      onProgress: (done, total) {
        if (mounted) {
          state = state.copyWith(status: SubStatus.probing, probedCount: done);
        }
      },
    );

    _saveCache(probed);
    final prefs = await SharedPreferences.getInstance();
    final fetchTime = DateTime.now();
    await prefs.setInt(
        'subscription_last_fetched', fetchTime.millisecondsSinceEpoch);

    _scheduleStaleCheck(fetchTime);

    if (!mounted) return;
    state = state.copyWith(
      status: SubStatus.ready,
      nodes: probed,
      probedCount: probed.length,
      lastFetchedAt: fetchTime,
    );

    await _runDeepProbe(probed);
  }

  void markNodeAsDead(String nodeId) {
    final updated = state.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(isAlive: false, isTrulyWorking: false);
      }
      return n;
    }).toList();
    state = state.copyWith(nodes: updated);
  }

  // ── Приватные ─────────────────────────────────────────────────────────────

  Future<void> _runDeepProbe(List<Node> sortedNodes) async {
    // Бинарник нужен для запуска sing-box
    final binMgr = BinaryManager.instance;
    if (!binMgr.isReady) {
      // Бинарники ещё не скачаны — пропускаем Deep Probe
      return;
    }

    // Сколько нод будет проверяться (топ-10 из живых)
    final candidateCount = sortedNodes.where((n) => n.isAlive).take(10).length;
    if (candidateCount == 0) return;

    if (mounted) {
      state = state.copyWith(
        status: SubStatus.deepProbing,
        deepProbedCount: 0,
        deepProbeTotal: candidateCount,
      );
    }

    final deepProbe = DeepProbe(singboxExePath: binMgr.singboxExe.path);

    final workingNode = await deepProbe.findWorkingNode(
      sortedNodes,
      onProgress: (done, total) {
        if (mounted) {
          state = state.copyWith(
            status: SubStatus.deepProbing,
            deepProbedCount: done,
            deepProbeTotal: total,
          );
        }
      },
    );

    if (!mounted) return;

    if (workingNode != null) {
      // Помечаем найденную ноду как isTrulyWorking = true в общем списке
      final updatedNodes = state.nodes.map((n) {
        return n.id == workingNode.id ? n.copyWith(isTrulyWorking: true) : n;
      }).toList();

      _saveCache(updatedNodes);
      state = state.copyWith(status: SubStatus.ready, nodes: updatedNodes);
    } else {
      // Ни одна нода не прошла — возвращаемся в ready без изменений
      state = state.copyWith(status: SubStatus.ready);
    }
  }

  Future<void> _saveCache(List<Node> nodes) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = nodes.map((n) => jsonEncode(n.toJson())).toList();
    await prefs.setStringList('cached_nodes', jsonList);
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_urlKey);
    final cached = prefs.getStringList('cached_nodes');
    final lastFetchedMs = prefs.getInt('subscription_last_fetched');
    final lastFetched = lastFetchedMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastFetchedMs)
        : null;

    if (saved != null && saved.isNotEmpty) {
      if (cached != null && cached.isNotEmpty) {
        try {
          final nodes =
              cached.map((s) => Node.fromJson(jsonDecode(s))).toList();
          state = state.copyWith(
            url: saved,
            nodes: nodes,
            status: SubStatus.ready,
            lastFetchedAt: lastFetched,
          );
          if (lastFetched != null) {
            _scheduleStaleCheck(lastFetched);
          }
        } catch (_) {
          state = state.copyWith(url: saved);
        }
      } else {
        state = state.copyWith(url: saved);
      }
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final subscriptionProvider =
    StateNotifierProvider<SubscriptionController, SubscriptionState>(
  (_) => SubscriptionController(),
);
