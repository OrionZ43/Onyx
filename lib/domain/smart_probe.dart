import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../core/log_service.dart';
import 'entities/node.dart';
import 'node_scorer.dart'; // ← NEW: Умная система весов
import 'singbox_config_builder.dart';
import 'udp_probe.dart';
import '../infrastructure/win_child_guard.dart';

// ── TCP ProbeResult ───────────────────────────────────────────────────────────

class ProbeResult {
  const ProbeResult({
    required this.node,
    required this.isAlive,
    this.latencyMs,
    this.error,
  });
  final Node node;
  final bool isAlive;
  final int? latencyMs;
  final String? error;
}

// ── SmartProbe — быстрый TCP-пинг (Этап 1) ───────────────────────────────────

/// Параллельно проверяет TCP-доступность серверов и сортирует результат
/// по умной системе весов ([NodeScorer]) для оптимальной работы Deep Probe.
///
/// ## Порядок приоритетов (меньший score → выше в списке)
///
///   1. REALITY + оптимальная гео  (score ≈ −6940 при 60 мс)
///   2. REALITY + любая гео        (score ≈ −4850 при 150 мс)
///   3. TLS + оптимальная гео      (score ≈ −1960 при 40 мс)
///   4. TLS + любая гео            (score = latencyMs)
///   5. Мёртвые ноды               (score = 99999)
///
/// Это гарантирует, что Deep Probe в первую очередь проверяет пуленепробиваемые
/// REALITY-серверы в ближних локациях, а не CDN-обманки с минимальным пингом.
class SmartProbe {
  const SmartProbe();

  static const _concurrency = 5;
  static const _timeout = Duration(seconds: 5);

  /// Проверяет список нод параллельно батчами по [_concurrency].
  ///
  /// После TCP-пинга сортирует живые ноды по [NodeScorer.score] (вместо
  /// наивной сортировки по latencyMs). Мёртвые ноды помещаются в конец.
  ///
  /// [onProgress] вызывается после каждой проверенной ноды.
  Future<List<Node>> probeAll(
    List<Node> nodes, {
    void Function(int done, int total)? onProgress,
  }) async {
    log.i(
      'Этап 1: TCP-пинг ${nodes.length} узлов (по $_concurrency параллельно)',
      tag: 'PROBE',
    );

    final results = List<Node?>.filled(nodes.length, null);
    int done = 0;

    for (var i = 0; i < nodes.length; i += _concurrency) {
      final end = min(i + _concurrency, nodes.length);
      final batch = nodes.sublist(i, end);
      final batchIndices = List.generate(end - i, (j) => i + j);

      final probed = await Future.wait(
        List.generate(batch.length, (j) async {
          final node = batch[j];
          final result = await probeOne(node);
          done++;
          onProgress?.call(done, nodes.length);
          return result;
        }),
      );

      for (var j = 0; j < probed.length; j++) {
        results[batchIndices[j]] = probed[j];
      }
    }

    final allNodes = results.whereType<Node>().toList();
    final alive = allNodes.where((n) => n.isAlive).length;

    log.i('Этап 1 завершён: $alive/${nodes.length} живых', tag: 'PROBE');

    // ── NEW: Сортировка по умной системе весов ────────────────────────────
    allNodes.sort(NodeScorer.compare);
    _logScoredRanking(allNodes);
    // ─────────────────────────────────────────────────────────────────────

    return allNodes;
  }

  Future<Node> probeOne(Node node) async {
    // Hysteria2/TUIC живут на UDP: TCP-порта нет, TCP-пинг всегда «мёртв».
    // Считаем ноду кандидатом; реальную задержку и UDP проставит Deep Probe.
    if (node.isQuic) {
      log.d('~ ${node.name} — QUIC-нода, TCP-пинг пропущен', tag: 'PROBE');
      return node.copyWith(isAlive: true);
    }
    final r = await _tcpProbe(node);
    if (r.isAlive) {
      log.i('✓ ${node.name} — ${r.latencyMs}мс', tag: 'PROBE');
    } else {
      log.w('✗ ${node.name} — недоступен: ${r.error}', tag: 'PROBE');
    }
    return node.copyWith(isAlive: r.isAlive, latencyMs: r.latencyMs);
  }

  Future<ProbeResult> _tcpProbe(Node node) async {
    log.d('TCP → ${node.host}:${node.port}', tag: 'PROBE');
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        node.host,
        node.port,
        timeout: _timeout,
      );
      sw.stop();
      await socket.close();
      return ProbeResult(
        node: node,
        isAlive: true,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return ProbeResult(node: node, isAlive: false, error: e.toString());
    }
  }

  // ── NEW: Диагностическое логирование рейтинга ─────────────────────────────

  /// Выводит топ-10 нод после скоринга с подробным объяснением их позиции.
  ///
  /// Пример вывода:
  /// ```
  /// [PROBE] 🏆 Рейтинг нод после скоринга (топ-10):
  /// [PROBE]  #1  score=−6940  🇩🇪 REALITY DE-01  (REALITY +5000pts | GEO +2000pts | latency=60ms)
  /// [PROBE]  #2  score=−4910  🇺🇸 REALITY US-03  (REALITY +5000pts | no bonus | latency=90ms)
  /// [PROBE]  #3  score=−1960  🇳🇱 TLS NL-07      (GEO +2000pts | no bonus | latency=40ms)
  /// ```
  void _logScoredRanking(List<Node> sorted) {
    final liveNodes = sorted.where((n) => n.isAlive).toList();
    if (liveNodes.isEmpty) return;

    final topN = liveNodes.take(10).toList();
    final buffer = StringBuffer(
      '🏆 Рейтинг нод после скоринга (топ-${topN.length} из ${liveNodes.length} живых):\n',
    );

    for (var i = 0; i < topN.length; i++) {
      final node = topN[i];
      final score = NodeScorer.score(node);
      final label = NodeScorer.debugLabel(node);
      buffer.write(
        '  #${(i + 1).toString().padLeft(2)}  '
        'score=${score.toString().padLeft(6)}  '
        '${node.name.padRight(30)}  ($label)\n',
      );
    }

    log.i(buffer.toString(), tag: 'PROBE');
  }
}

// ── DeepProbe — реальная HTTPS-проверка через sing-box (Этап 2) ──────────────

/// Проверяет реальную работоспособность прокси-серверов, запуская отдельный
/// процесс sing-box для каждого кандидата и делая HTTPS-запрос через него.
///
/// ─── Алгоритм ────────────────────────────────────────────────────────────────
///
///   1. Берёт ВСЕ живые ноды из [sortedNodes] — уже отсортированных по
///      [NodeScorer] (REALITY + оптимальная гео идут первыми).
///      Это необходимо, потому что первые ~15 нод в публичных подписках часто
///      являются "обманками" (Domain Fronting через CDN), которые дают
///      идеальный TCP-пинг (10 мс), но блокируют реальный VLESS-трафик.
///
///   2. Разбивает на батчи по [_batchSize] нод.
///
///   3. В каждом батче проверяет ноды параллельно:
///      a. Для каждой записывает probe_NNNN.json (SOCKS5 вход → VLESS выход).
///      b. Запускает sing-box.exe в detached-режиме.
///      c. Ждёт [_startupDelay] — пока SOCKS5 не будет готов.
///      d. Делает HTTPS-запрос:
///           TCP → 127.0.0.1:[proxyPort]
///           → HTTP CONNECT cp.cloudflare.com:443
///           → HTTP/1.0 GET /generate_204
///           → ожидаем "HTTP/1.x 204" или "HTTP/1.x 200"
///
///   4. КАК ТОЛЬКО первая нода вернула успех — НЕМЕДЛЕННО:
///      • устанавливаем флаг [cancelled]
///      • убиваем ВСЕ sing-box процессы текущего батча
///      • возвращаем победителя (isTrulyWorking = true)
///      • прочие батчи НЕ запускаются
///
///   5. Если батч полностью провалился — переходим к следующему.
///
/// ─── Почему HTTPS, а не HTTP ─────────────────────────────────────────────────
///
///   Многие VLESS-серверы блокируют порт 80. Порт 443 (HTTPS) практически
///   всегда открыт. cp.cloudflare.com/generate_204 возвращает HTTP 204
///   No Content (пустое тело), что минимизирует трафик теста.
///
/// ─── Порты ───────────────────────────────────────────────────────────────────
///
///   Начинаются с [_basePort] = 2090. Каждая нода получает
///   уникальный порт: 2090, 2091, 2092, ... Это исключает конфликт
///   с основным VPN (2080) и Clash API (9090).
///
class DeepProbe {
  DeepProbe({required this.singboxExePath});

  /// Путь к sing-box.exe (из BinaryManager.instance.singboxExe.path).
  final String singboxExePath;

  /// Сколько нод проверяем параллельно в одном батче.
  /// 5 — баланс между скоростью и нагрузкой на систему.
  static const _batchSize = 5;

  /// Базовый порт для SOCKS5-слушателей probe-процессов.
  static const _basePort = 2090;

  /// Задержка после запуска sing-box — ждём инициализацию SOCKS5.
  static const _startupDelay = Duration(seconds: 2);

  /// Таймаут всего HTTPS-обмена (считается с момента SOCKS5 CONNECT).
  static const _httpTimeout = Duration(seconds: 10);

  /// Цель HTTPS-проверки: Cloudflare generate_204 (всегда открыт, 204 ответ).
  static const _probeHost = 'cp.cloudflare.com';
  static const _probePath = '/generate_204';

  /// Цель AI-проверки. ChatGPT фронтирован Cloudflare, и именно Cloudflare
  /// отдаёт 403/challenge для датацентр-IP из типовых блок-листов — то есть
  /// это хороший индикатор "пустит ли exit-IP к ИИ вообще".
  ///
  /// Почему один хост, а не все ИИ сразу: полный обход всех ИИ-доменов
  /// умножил бы время скана. ChatGPT/Cloudflare — самый строгий и
  /// репрезентативный фильтр; если IP проходит здесь, он с высокой
  /// вероятностью пройдёт и к остальным. При желании список можно
  /// расширить (ценой скорости).
  static const _aiProbeHost = 'chatgpt.com';

  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Возвращает первую ноду из [sortedNodes], прошедшую реальную HTTPS-проверку.
  ///
  /// [sortedNodes] — список, уже отсортированный [NodeScorer] (лучший первый).
  /// [onProgress]  — (проверено, всего_живых) для отображения прогресса.
  Future<Node?> findWorkingNode(
    List<Node> sortedNodes, {
    void Function(int done, int total)? onProgress,
  }) async {
    final candidates = sortedNodes.where((n) => n.isAlive).toList();

    if (candidates.isEmpty) {
      log.w('Этап 2: нет живых кандидатов для глубокой проверки', tag: 'DEEP');
      return null;
    }

    log.i(
      'Этап 2: Deep Probe — ${candidates.length} кандидатов, '
      'батчи по $_batchSize, HTTPS→$_probeHost',
      tag: 'DEEP',
    );

    int done = 0;

    for (var batchStart = 0;
        batchStart < candidates.length;
        batchStart += _batchSize) {
      final batchEnd = min(batchStart + _batchSize, candidates.length);
      final batch = candidates.sublist(batchStart, batchEnd);

      log.d(
        'Батч ${batchStart ~/ _batchSize + 1}: '
        'ноды ${batchStart + 1}–$batchEnd из ${candidates.length} '
        '[${batch.map((n) => n.name).join(', ')}]',
        tag: 'DEEP',
      );

      final winner = await _runBatch(batch, portOffset: batchStart);
      done += batch.length;
      onProgress?.call(done, candidates.length);

      if (winner != null) {
        log.i('✅ Рабочая нода найдена: ${winner.name}', tag: 'DEEP');
        return winner;
      }

      log.d(
        'Батч ${batchStart ~/ _batchSize + 1} провалился. '
        'Осталось проверить: ${candidates.length - batchEnd}',
        tag: 'DEEP',
      );
    }

    log.w(
      'Этап 2: ни одна нода не прошла реальную HTTPS-проверку',
      tag: 'DEEP',
    );
    return null;
  }

  /// Полный Deep-скан ВСЕХ живых нод — без ранней остановки.
  ///
  /// В отличие от [findWorkingNode] (который ищет ПЕРВУЮ рабочую и глушит
  /// остальные), этот метод проверяет КАЖДУЮ живую ноду и для каждой ставит
  /// два флага:
  ///   • isTrulyWorking — базовая связность (generate_204);
  ///   • aiReachable    — доступ к ИИ (только если базовая прошла).
  ///
  /// Результат по каждой ноде отдаётся немедленно через [onNodeResult],
  /// чтобы UI заполнялся прогрессивно и пользователь мог подключиться к
  /// первой же зелёной ноде, не дожидаясь конца полного скана.
  ///
  /// Батчи идут последовательно (по [_batchSize] параллельно внутри батча),
  /// поэтому порты переиспользуются в пределах слота 0..[_batchSize]-1 —
  /// процессы предыдущего батча к началу следующего уже убиты.
  ///
  /// [isCancelled] проверяется между батчами — позволяет прервать долгий
  /// скан (например, при размонтировании провайдера).
  Future<void> probeAllNodes(
    List<Node> sortedNodes, {
    required void Function(Node updated) onNodeResult,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final candidates = sortedNodes.where((n) => n.isAlive).toList();
    if (candidates.isEmpty) {
      log.w('Deep-скан: нет живых кандидатов', tag: 'DEEP');
      return;
    }

    log.i(
      'Deep-скан ВСЕХ нод: ${candidates.length} кандидатов, '
      'батчи по $_batchSize, база=$_probeHost, AI=$_aiProbeHost',
      tag: 'DEEP',
    );

    int done = 0;

    for (var start = 0; start < candidates.length; start += _batchSize) {
      if (isCancelled?.call() ?? false) {
        log.d('Deep-скан прерван на $done/${candidates.length}', tag: 'DEEP');
        return;
      }

      final end = min(start + _batchSize, candidates.length);
      final batch = candidates.sublist(start, end);

      log.d(
        'Батч ${start ~/ _batchSize + 1}: ноды ${start + 1}–$end '
        'из ${candidates.length}',
        tag: 'DEEP',
      );

      await Future.wait(
        List.generate(batch.length, (slot) async {
          final node = batch[slot];
          final port = _basePort + slot;
          final result = await _probeNodeFull(node, port);
          done++;
          onNodeResult(result);
          onProgress?.call(done, candidates.length);
        }),
      );
    }

    log.i('Deep-скан завершён: проверено ${candidates.length} нод', tag: 'DEEP');
  }

  /// Свежий замер перед автопрыжком (#60): время HTTPS-запроса через каждую
  /// ноду — те же единицы, что у монитора здоровья. Параллельно, лучший из
  /// двух запросов (первый включает рукопожатие с сервером). Порты — свободные
  /// от ОС, не пересекаются со сканом. Возвращает id → мс (−1 — не ответила).
  ///
  /// Работает и при поднятом VPN: на Windows трафик sing-box.exe идёт мимо
  /// туннеля (правило в конфиге), на Android приложение исключено из VPN.
  Future<Map<String, int>> measure(List<Node> nodes) async {
    final res = <String, int>{};
    await Future.wait([
      for (final n in nodes) _measureOne(n).then((ms) => res[n.id] = ms),
    ]);
    return res;
  }

  Future<int> _measureOne(Node node) async {
    Process? process;
    String? configPath;
    try {
      final port = await _freePort();
      configPath = _probeConfigPath(port);
      await _writeProbeConfig(node, port, configPath);
      process = await Process.start(
        singboxExePath,
        ['run', '-c', configPath],
        mode: ProcessStartMode.detached,
      );
      WinChildGuard.adopt(process.pid);
      // Ждём слушатель до 3 с вместо фиксированных 2 с.
      var up = false;
      for (var i = 0; i < 12 && !up; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        up = await _isSocksListening(port);
      }
      if (!up) return -1;
      var best = -1;
      for (var i = 0; i < 2; i++) {
        final sw = Stopwatch()..start();
        final ok = await _httpsProbeViaSocks5(port, node.name)
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
        sw.stop();
        if (!ok) break;
        final ms = sw.elapsedMilliseconds;
        if (best < 0 || ms < best) best = ms;
      }
      log.i('Замер ${node.name}: ${best < 0 ? "не ответил" : "$best мс"}', tag: 'DEEP');
      return best;
    } catch (e) {
      log.d('[${node.name}] замер: $e', tag: 'DEEP');
      return -1;
    } finally {
      try {
        process?.kill();
      } catch (_) {}
      if (configPath != null) {
        try {
          File(configPath).deleteSync();
        } catch (_) {}
      }
    }
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  /// Полная проверка одной ноды: базовая связность + (при успехе) AI.
  /// Всегда возвращает ноду с проставленными флагами (в т.ч. false/false
  /// при провале), чтобы вызывающий мог обновить UI без исключений.
  Future<Node> _probeNodeFull(Node node, int port) async {
    final configPath = _probeConfigPath(port);
    Process? process;
    bool basicOk = false;
    bool aiOk = false;
    bool udpOk = false;
    int? latency;

    try {
      await _writeProbeConfig(node, port, configPath);
      process = await Process.start(
        singboxExePath,
        ['run', '-c', configPath],
        mode: ProcessStartMode.detached,
      );
      // Пробы не переживают onyx.exe: задание Windows погасит их при любом выходе (#57)
      WinChildGuard.adopt(process.pid);
      log.d('[${node.name}] PID=${process.pid}, SOCKS5 порт=$port', tag: 'DEEP');

      await Future.delayed(_startupDelay);

      if (!await _isSocksListening(port)) {
        log.d('[${node.name}] SOCKS5:$port не отвечает', tag: 'DEEP');
        return node.copyWith(isTrulyWorking: false, aiReachable: false);
      }

      final sw = Stopwatch()..start();
      basicOk = await _httpsProbeViaSocks5(port, node.name).timeout(
        _httpTimeout,
        onTimeout: () => false,
      );
      sw.stop();
      if (basicOk && (node.isQuic || node.latencyMs == null)) {
        // Для QUIC-нод TCP-пинга не было: берём время HTTPS-запроса
        // через прокси (грубо, с запасом — включает TLS к cp.cloudflare.com).
        latency = sw.elapsedMilliseconds;
      }
      if (basicOk) {
        // UDP — то, на чём живут голос, камера и стримы Discord.
        final udp = await UdpProbe.viaSocks5(
          port,
          attempts: 3,
          timeout: const Duration(seconds: 3),
        );
        udpOk = udp.ok;
        log.d('[${node.name}] UDP: ${udp.summary}', tag: 'DEEP');
      }

      // AI проверяем только у живых нод — на мёртвой это пустая трата времени.
      if (basicOk) {
        aiOk = await _aiProbeViaSocks5(port, node.name).timeout(
          _httpTimeout,
          onTimeout: () => false,
        );
      }

      log.i(
        '${basicOk ? "✓" : "✗"} [${node.name}] '
        'база=${basicOk ? "ok" : "нет"} AI=${aiOk ? "ok" : "нет"} UDP=${udpOk ? "ok" : "нет"}',
        tag: 'DEEP',
      );
    } catch (e) {
      log.d('[${node.name}] _probeNodeFull ошибка: $e', tag: 'DEEP');
    } finally {
      try {
        process?.kill();
      } catch (_) {}
      try {
        File(configPath).deleteSync();
      } catch (_) {}
    }

    return node.copyWith(
      isTrulyWorking: basicOk,
      aiReachable: aiOk,
      udpSupported: udpOk,
      latencyMs: latency,
    );
  }

  // ── Приватные методы ───────────────────────────────────────────────────────

  Future<Node?> _runBatch(List<Node> batch, {required int portOffset}) async {
    final winnerCmpl = Completer<Node?>();
    final activeProcs = <int, Process>{};
    final cancelled = [false];
    int pending = batch.length;

    void onProbeResult(Node? winner, int port) {
      if (winnerCmpl.isCompleted) return;

      if (winner != null) {
        cancelled[0] = true;
        final toKill = Map<int, Process>.from(activeProcs)..remove(port);

        if (toKill.isNotEmpty) {
          log.d(
            '🎯 Победитель: ${winner.name}. '
            'Убиваем ${toKill.length} лишних sing-box процессов...',
            tag: 'DEEP',
          );
          for (final proc in toKill.values) {
            try {
              proc.kill();
            } catch (_) {}
          }
        }

        winnerCmpl.complete(winner);
        return;
      }

      pending--;
      if (pending <= 0 && !winnerCmpl.isCompleted) {
        winnerCmpl.complete(null);
      }
    }

    for (var i = 0; i < batch.length; i++) {
      final node = batch[i];
      final port = _basePort + portOffset + i;
      _probeOneNode(
        node: node,
        port: port,
        activeProcs: activeProcs,
        cancelled: cancelled,
        onResult: onProbeResult,
      );
    }

    final batchTimeout = Duration(
      seconds: _startupDelay.inSeconds + _httpTimeout.inSeconds + 5,
    );

    return winnerCmpl.future.timeout(
      batchTimeout,
      onTimeout: () {
        if (!winnerCmpl.isCompleted) {
          log.w(
            'Батч: общий таймаут ${batchTimeout.inSeconds}с. '
            'Принудительно убиваем ${activeProcs.length} процессов.',
            tag: 'DEEP',
          );
          cancelled[0] = true;
          for (final proc in activeProcs.values) {
            try {
              proc.kill();
            } catch (_) {}
          }
          activeProcs.clear();
          winnerCmpl.complete(null);
        }
        return null;
      },
    );
  }

  Future<void> _probeOneNode({
    required Node node,
    required int port,
    required Map<int, Process> activeProcs,
    required List<bool> cancelled,
    required void Function(Node? winner, int port) onResult,
  }) async {
    final configPath = _probeConfigPath(port);
    Process? process;
    Node? winner;

    try {
      if (cancelled[0]) return;

      await _writeProbeConfig(node, port, configPath);
      if (cancelled[0]) return;

      process = await Process.start(
          singboxExePath,
          [
            'run',
            '-c',
            configPath,
          ],
          mode: ProcessStartMode.detached);
      activeProcs[port] = process;
      WinChildGuard.adopt(process.pid); // #57
      log.d(
        '[${node.name}] PID=${process.pid}, SOCKS5 порт=$port',
        tag: 'DEEP',
      );

      await Future.delayed(_startupDelay);
      if (cancelled[0]) return;

      if (!await _isSocksListening(port)) {
        log.d(
          '[${node.name}] SOCKS5:$port не отвечает — sing-box не стартовал?',
          tag: 'DEEP',
        );
        return;
      }
      if (cancelled[0]) return;

      final sw = Stopwatch()..start();
      final ok = await _httpsProbeViaSocks5(port, node.name).timeout(
        _httpTimeout,
        onTimeout: () {
          log.d('[${node.name}] HTTPS-проверка: таймаут', tag: 'DEEP');
          return false;
        },
      );

      if (ok) {
        log.i(
          '✓ [${node.name}] HTTP 204 через порт $port — нода рабочая!',
          tag: 'DEEP',
        );
        winner = node.copyWith(
          isTrulyWorking: true,
          latencyMs: node.isQuic ? sw.elapsedMilliseconds : null,
        );
      } else {
        log.w('✗ [${node.name}] HTTPS-проверка провалилась', tag: 'DEEP');
      }
    } catch (e) {
      log.d('[${node.name}] _probeOneNode ошибка: $e', tag: 'DEEP');
    } finally {
      try {
        process?.kill();
      } catch (_) {}
      activeProcs.remove(port);
      try {
        File(configPath).deleteSync();
      } catch (_) {}
      onResult(winner, port);
    }
  }

  Future<bool> _httpsProbeViaSocks5(int proxyPort, String nodeName) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
    client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final url = Uri.parse('https://$_probeHost$_probePath');
      final request = await client.getUrl(url);
      final response = await request.close().timeout(_httpTimeout);

      log.d(
        '[$nodeName] HTTPS ответ: HTTP ${response.statusCode}',
        tag: 'DEEP',
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      log.d('[$nodeName] HTTPS-проверка таймаут/ошибка', tag: 'DEEP');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// AI-проверка: пускает ли exit-IP к ИИ-сервису.
  ///
  /// Логика: делаем HTTPS-запрос к ChatGPT (Cloudflare-фронт) через прокси,
  /// НЕ следуя редиректам, и смотрим первый статус:
  ///   • 200 / 301 / 302 / 307 / 308 → IP чистый, ИИ доступен (обычная
  ///     страница или редирект на /auth);
  ///   • 403 / 451 → IP забанен по репутации/региону (то самое "Unable to
  ///     load site" от Cloudflare, что мы видели на скринах);
  ///   • заголовок cf-mitigated: challenge → Cloudflare выдаёт челлендж =
  ///     тоже фактический блок для автоматики.
  ///
  /// Возвращает false при любой ошибке/таймауте — нет ответа, значит не
  /// подтверждено.
  Future<bool> _aiProbeViaSocks5(int proxyPort, String nodeName) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await client.getUrl(Uri.parse('https://$_aiProbeHost/'));
      request.followRedirects = false;
      // Реалистичный User-Agent: некоторые эджи режут запросы без него.
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/122.0 Safari/537.36',
      );
      final response = await request.close().timeout(_httpTimeout);

      final code = response.statusCode;
      final cfMitigated = response.headers.value('cf-mitigated');
      await response.drain<void>();

      if (cfMitigated != null && cfMitigated.contains('challenge')) {
        log.d('[$nodeName] AI: cf-mitigated=challenge → блок', tag: 'DEEP');
        return false;
      }

      final ok = code == 200 ||
          code == 301 ||
          code == 302 ||
          code == 307 ||
          code == 308;
      log.d(
        '[$nodeName] AI-проверка ($_aiProbeHost): HTTP $code → '
        '${ok ? "доступен" : "блок"}',
        tag: 'DEEP',
      );
      return ok;
    } catch (e) {
      log.d('[$nodeName] AI-проверка таймаут/ошибка', tag: 'DEEP');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _isSocksListening(int port) async {
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 2),
      );
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _probeConfigPath(int port) {
    final tempDir = Platform.isWindows
        ? (Platform.environment['TEMP'] ?? Directory.systemTemp.path)
        : Directory.systemTemp.path;
    return '$tempDir${Platform.pathSeparator}onyx_probe_$port.json';
  }

  Future<void> _writeProbeConfig(Node node, int port, String path) async {
    final builder = const SingboxConfigBuilder();
    final config = builder.buildProbeConfig(node, port);
    final json = builder.buildJson(config);
    await File(path).writeAsString(json, flush: true);
    log.d('Probe-конфиг: $path', tag: 'DEEP');
  }
}