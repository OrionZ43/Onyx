import 'entities/node.dart';

/// Можно ли сейчас автоматически сменить сервер.
enum FailoverGate {
  /// Можно: перепроверить кандидатов и прыгнуть на заметно лучшего.
  allowed,

  /// Пользователь выключил «Автопереключение серверов».
  disabled,

  /// Сервер выбран вручную — без спроса не уводим.
  manual,

  /// Недавно уже прыгали сами, а текущий сервер хоть как-то отвечает —
  /// не скачем (гистерезис).
  cooldown,

  /// Недавно искали замену и не нашли — не перемеряем каждые 20 с.
  backoff,

  /// Только что подключились, а сервер хоть как-то отвечает (#69): первые
  /// минуты сеть и проверки ещё «успокаиваются», медленная проба — не повод.
  settling,
}

/// Правила автопереключения серверов (#60).
///
/// Раньше: две плохие пробы за 3 с → прыжок на «лучший» по формуле, где
/// бонусы протокола и UDP (тысячи «очков») перевешивали задержку. Сервер с
/// пингом 2000 мс обгонял сервер на 80 мс, данные задержки могли быть
/// часовой давности, ручной выбор не учитывался, а каждый прыжок рвёт игру
/// и звонок.
///
/// Теперь:
/// * «заведомо медленные» (сохранённая задержка выше потолка) не выбираются,
///   пока есть нормальные — ни при подключении, ни при переключении;
/// * перед прыжком лучшие кандидаты перепроверяются свежим замером, прыжок —
///   только на кандидата в пределах потолка и заметно лучше текущего;
/// * ручной выбор и выключенный тумблер — никаких прыжков, только
///   уведомление; после автопрыжка — пауза, пока сервер отвечает.
class FailoverPolicy {
  const FailoverPolicy._();

  /// Потолок сохранённой задержки. У обычных серверов это TCP-пинг
  /// (≈ 1 RTT): 400 мс и выше — для игр и голоса уже «заведомо плохо».
  static const tcpCeilingMs = 400;

  /// У QUIC (Hysteria2/TUIC) TCP-пинга нет — хранится время HTTPS-запроса
  /// через сервер (≈ 3 RTT), поэтому потолок втрое выше.
  static const quicCeilingMs = 1200;

  /// Потолок свежего замера кандидата — время HTTPS-запроса через сервер,
  /// те же единицы, что у монитора здоровья (≈ 3 RTT по 400 мс).
  static const freshCeilingMs = 1200;

  /// Кандидат должен быть заметно быстрее текущего: не больше 75% его
  /// последнего замера (если текущий вообще отвечает).
  static const improvement = 0.75;

  /// Сколько лучших кандидатов перепроверять перед прыжком.
  static const shortlistSize = 3;

  /// После автопрыжка не прыгаем снова, пока сервер отвечает.
  static const cooldown = Duration(minutes: 3);

  /// После безуспешного поиска замены — пауза перед следующим.
  static const backoff = Duration(minutes: 1);

  /// Первые минуты после подключения не меняем сервер, пока он отвечает
  /// (#69). Тогда же доделывается фоновая проверка серверов, поднимаются
  /// маршруты, и пробы через туннель бывают медленными без вины сервера.
  static const settleTime = Duration(minutes: 3);

  /// Уведомление «сервер нестабилен» — не чаще.
  static const notifyEvery = Duration(minutes: 5);

  /// Предпочтения (UDP для Discord, ИИ) работают, только если кандидат
  /// не сильно медленнее самого быстрого: ≤ 1.5× + 50 мс.
  static const preferenceSlack = 1.5;
  static const preferenceSlackMs = 50;

  /// Плохая ли проба здоровья: сервер не ответил ([ms] < 0) или ответил
  /// медленнее [thresholdMs]. Медленная проба, пока идёт своя проверка
  /// серверов (десятки sing-box мимо туннеля грузят сеть и процессор), не в
  /// счёт (#69): тормозит не сервер. Неответ — в счёт всегда.
  static bool healthSampleBad(int ms, {required int thresholdMs, required bool probesBusy}) =>
      ms < 0 || (ms > thresholdMs && !probesBusy);

  /// Сохранённая задержка в пределах потолка. Нет данных — не отсекаем:
  /// перед прыжком всё равно будет свежий замер.
  static bool latencyAcceptable(Node n) {
    final ms = n.latencyMs;
    if (ms == null) return true;
    return ms <= (n.isQuic ? quicCeilingMs : tcpCeilingMs);
  }

  /// Можно ли прыгать сейчас. [currentDead] — текущий сервер не ответил ни
  /// на одну из плохих проб (а не просто медленный). [connectedAt] — когда
  /// подключились к текущему серверу.
  static FailoverGate gate({
    required bool autoFailover,
    required bool manualPick,
    required bool currentDead,
    required DateTime now,
    DateTime? connectedAt,
    DateTime? lastAutoSwitch,
    DateTime? noBetterUntil,
  }) {
    if (!autoFailover) return FailoverGate.disabled;
    if (manualPick) return FailoverGate.manual;
    if (!currentDead && connectedAt != null && now.difference(connectedAt) < settleTime) {
      return FailoverGate.settling;
    }
    if (!currentDead && lastAutoSwitch != null && now.difference(lastAutoSwitch) < cooldown) {
      return FailoverGate.cooldown;
    }
    if (noBetterUntil != null && now.isBefore(noBetterUntil)) return FailoverGate.backoff;
    return FailoverGate.allowed;
  }

  /// Выбор по свежим замерам. [candidates] — в порядке приоритета,
  /// [fresh] — id → мс (−1 или нет записи — не ответил), [currentMs] —
  /// последний замер текущего сервера (−1 — не отвечает). null — прыгать
  /// не на что: остаёмся и честно об этом говорим.
  static Node? choose({
    required List<Node> candidates,
    required Map<String, int> fresh,
    required int currentMs,
    bool preferUdp = false,
    bool preferAi = false,
  }) {
    int ms(Node n) => fresh[n.id] ?? -1;
    final ok = [
      for (final n in candidates)
        if (ms(n) >= 0 &&
            ms(n) <= freshCeilingMs &&
            (currentMs < 0 || ms(n) <= currentMs * improvement))
          n,
    ];
    if (ok.isEmpty) return null;
    // Стабильная сортировка по свежему замеру: при равенстве — порядок
    // приоритета из [candidates].
    final order = {for (var i = 0; i < candidates.length; i++) candidates[i].id: i};
    ok.sort((a, b) {
      final c = ms(a).compareTo(ms(b));
      return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
    });
    final fastest = ms(ok.first);
    bool close(Node n) => ms(n) <= fastest * preferenceSlack + preferenceSlackMs;
    // Свой сервер (#68) при прочих равных раньше чужого: если его свежий
    // замер не хуже самого быстрого больше чем в 1/[improvement] раза.
    bool ownClose(Node n) => n.isOwn && ms(n) * improvement <= fastest;
    Node? firstWhere(bool Function(Node) test) {
      for (final n in ok) {
        if (ownClose(n) && test(n)) return n;
      }
      for (final n in ok) {
        if (close(n) && test(n)) return n;
      }
      return null;
    }

    // Нужное для дела (UDP для голоса, ИИ) — важнее, чем «свой».
    if (preferUdp && preferAi) {
      final both = firstWhere((n) => n.udpSupported && n.aiReachable);
      if (both != null) return both;
    }
    if (preferUdp) {
      final udp = firstWhere((n) => n.udpSupported);
      if (udp != null) return udp;
    }
    if (preferAi) {
      final ai = firstWhere((n) => n.aiReachable);
      if (ai != null) return ai;
    }
    return firstWhere((_) => true) ?? ok.first;
  }
}

/// Что делать, если туннель умер (смена сети, сон, падение ядра) — этап 2.
enum RecoveryStep {
  /// Только тот же сервер: он выбран вручную.
  sameNodeManual,

  /// Только тот же сервер: автопереключение выключено.
  sameNodeAutoOff,

  /// К тому же серверу, а не вышло — подобрать заново (smartConnect).
  sameNodeThenAuto;

  /// Другой сервер Onyx сам не подбирает (причина — в имени шага).
  bool get sameNodeOnly => this != sameNodeThenAuto;
}

/// Восстановление после обрыва. Тот же сервер — всегда: это не «прыжок»
/// (#60). Подбирать другой — только если автопереключение включено и сервер
/// не выбран вручную. Ручной выбор называем причиной первым: «выберите
/// другой или «Автовыбор»» помогает и при выключенном автопереключении.
class RecoveryPolicy {
  const RecoveryPolicy._();

  static RecoveryStep plan({required bool autoFailover, required bool manualPick}) => manualPick
      ? RecoveryStep.sameNodeManual
      : autoFailover
          ? RecoveryStep.sameNodeThenAuto
          : RecoveryStep.sameNodeAutoOff;
}
