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
    final resumed = isSleepGap(prevPoll, now);
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
      if (prev != null && sig != prev) {
        log.i('Сеть сменилась: [$prev] → [$sig]', tag: 'NET');
        _ctrl.add(NetEvent.changed);
      } else if (resumed) {
        log.i('Похоже, устройство спало (${now.difference(prevPoll!).inSeconds} с без опроса)', tag: 'NET');
        _ctrl.add(NetEvent.resumed);
      }
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
