import 'dart:async';
import 'dart:io';

import '../core/log_service.dart';

/// Адрес интерфейса для подписи сети (чистые данные — для тестов).
class NetAddr {
  final String interfaceName;
  final String address;

  const NetAddr(this.interfaceName, this.address);
}

/// Что случилось с сетью.
enum NetEvent {
  /// Сменилась сеть: Wi-Fi ↔ мобильная, другая точка доступа, кабель.
  changed,

  /// Устройство проснулось: опрос надолго замирал (сон, гибернация).
  /// Подпись сети могла и не измениться, а соединения — оборваться.
  resumed,
}

/// Следит за сменой сети (этап 2 автопилота): Wi-Fi → мобильная, другая
/// точка доступа, кабель, выход из сна. Раз в 5 с сравнивает «подпись»
/// физических IPv4-адресов: опрос дешёвый и одинаково работает на Windows и
/// Android без плагинов и разрешений. Сон узнаём по разрыву между опросами.
///
/// Подключены — сразу проверяем туннель (не ждём плановые 20 с).
/// Отключены — данные проб с прошлой сети устарели: перепроверяем в фоне.
class NetworkWatcher {
  NetworkWatcher._();
  static final instance = NetworkWatcher._();

  static const interval = Duration(seconds: 5);

  /// Разрыв между опросами больше этого — устройство спало.
  static const sleepGap = Duration(seconds: 20);

  final _ctrl = StreamController<NetEvent>.broadcast();
  Timer? _timer;
  String? _last;
  DateTime? _lastPoll;
  DateTime? _quietUntil;

  /// Свой туннель поднимается или гаснет (#69): изменения сети в ближайшие
  /// [d] — не «смена сети» и не «выход из сна». Подпись просто запоминаем
  /// заново, событий нет. Повторный вызов продлевает тишину.
  void quietFor(Duration d) {
    final until = DateTime.now().add(d);
    final cur = _quietUntil;
    if (cur == null || until.isAfter(cur)) _quietUntil = until;
  }

  /// Идёт ли тишина в момент [now].
  static bool isQuiet(DateTime? quietUntil, DateTime now) => quietUntil != null && now.isBefore(quietUntil);

  /// Событие по итогам опроса (чистая функция — для тестов). Первый опрос —
  /// без события; во время тишины своего (пере)подключения — без события
  /// (#69); сменилась подпись — [NetEvent.changed]; долго не было опроса —
  /// [NetEvent.resumed].
  static NetEvent? decide({
    required String? prevSig,
    required String sig,
    required DateTime? prevPoll,
    required DateTime now,
    DateTime? quietUntil,
  }) {
    if (isQuiet(quietUntil, now)) return null;
    if (prevSig != null && sig != prevSig) return NetEvent.changed;
    if (isSleepGap(prevPoll, now)) return NetEvent.resumed;
    return null;
  }

  /// События сети. Опрос стартует при первой подписке.
  Stream<NetEvent> get changes {
    _timer ??= Timer.periodic(interval, (_) => _poll());
    if (_last == null) unawaited(_poll());
    return _ctrl.stream;
  }

  Future<void> _poll() async {
    final now = DateTime.now();
    final prevPoll = _lastPoll;
    _lastPoll = now;
    try {
      final ifs = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      final sig = signature([
        for (final i in ifs)
          for (final a in i.addresses) NetAddr(i.name, a.address),
      ]);
      final prev = _last;
      _last = sig;
      final event = decide(prevSig: prev, sig: sig, prevPoll: prevPoll, now: now, quietUntil: _quietUntil);
      if (event == null) {
        if (prev != null && sig != prev) log.d('Сеть: [$prev] → [$sig] во время своего (пере)подключения — не событие', tag: 'NET');
        return;
      }
      if (event == NetEvent.changed) {
        log.i('Сеть сменилась: [$prev] → [$sig]', tag: 'NET');
      } else {
        log.i('Похоже, устройство спало (${now.difference(prevPoll!).inSeconds} с без опроса)', tag: 'NET');
      }
      _ctrl.add(event);
    } catch (e) {
      log.d('Опрос сетей не удался: $e', tag: 'NET');
    }
  }

  /// Есть ли физическая сеть (адрес не туннеля). До первого опроса — да.
  bool get hasNetwork => _last == null || _last!.isNotEmpty;

  /// Был ли между опросами сон: таймер раз в [interval] не срабатывал
  /// дольше [sleepGap] (процесс замораживается вместе с системой).
  static bool isSleepGap(DateTime? prev, DateTime now) =>
      prev != null && now.difference(prev) > sleepGap;

  /// Подпись физических сетей: отсортированные «имя=адрес» без туннелей
  /// (наш WinTUN 172.19.0.0/30, tun*/wintun на Android и у других VPN) и
  /// виртуальных адаптеров (WSL, Hyper-V, VirtualBox, VMware), которые
  /// появляются и пропадают сами по себе и давали бы ложные «смены сети».
  static String signature(List<NetAddr> addrs) {
    bool virtualName(String name) {
      final n = name.toLowerCase();
      return const ['tun', 'wintun', 'sing-box', 'vethernet', 'wsl', 'hyper-v', 'virtualbox', 'vmware', 'loopback', 'tap', 'utun']
          .any(n.contains);
    }

    bool ourTun(String a) => a.startsWith('172.19.0.');
    final keys = [
      for (final a in addrs)
        if (!virtualName(a.interfaceName) && !ourTun(a.address)) '${a.interfaceName}=${a.address}',
    ]..sort();
    return keys.join(',');
  }
}
