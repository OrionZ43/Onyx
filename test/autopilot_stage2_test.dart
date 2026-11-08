import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/smart_probe.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/infrastructure/network_watcher.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';

/// #41 + этап 2 автопилота: бюджет Deep Probe, порядок проверки, «смена сети».
const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

Node _n(String host, {int? ms, bool verified = false, bool udp = false}) =>
    const SubscriptionParser()
        .parseLink('vless://$_uuid@$host:443?security=reality#$host')!
        .copyWith(isAlive: ms != null, latencyMs: ms, isTrulyWorking: verified, udpSupported: udp);

void main() {
  group('Deep Probe: бюджет', () {
    test('«достаточно»: 3 рабочих; в режиме Discord — ещё и с UDP', () {
      final three = [_n('1.1.1.1', ms: 50, verified: true), _n('2.2.2.2', ms: 60, verified: true), _n('3.3.3.3', ms: 70, verified: true)];
      expect(SubscriptionController.deepEnough(three, discord: false), isTrue);
      expect(SubscriptionController.deepEnough(three, discord: true), isFalse);
      final withUdp = [...three, _n('4.4.4.4', ms: 80, verified: true, udp: true)];
      expect(SubscriptionController.deepEnough(withUdp, discord: true), isTrue);
      expect(SubscriptionController.deepEnough(three.take(2), discord: false), isFalse);
    });

    test('порядок: сначала в пределах потолка, медленные — в конец', () {
      final slow = _n('9.9.9.9', ms: 2000);
      final fast = _n('1.1.1.1', ms: 80);
      final unknown = _n('5.5.5.5'); // нет данных — не отсекаем
      expect(SubscriptionController.deepOrder([slow, fast, unknown]).map((n) => n.host), ['1.1.1.1', '5.5.5.5', '9.9.9.9']);
    });

    test('probeAllNodes: без живых кандидатов — ни одного запуска sing-box', () async {
      final dead = [for (var i = 0; i < 100; i++) _n('10.0.0.$i')];
      var results = 0;
      await DeepProbe(singboxExePath: 'нет-такого-файла').probeAllNodes(
        dead,
        maxNodes: 5,
        onNodeResult: (_) => results++,
      );
      expect(results, 0);
    });
  });

  group('подпись сети', () {
    test('туннели и виртуальные адаптеры не влияют', () {
      final base = [const NetAddr('Wi-Fi', '192.168.0.55')];
      final withNoise = [
        ...base,
        const NetAddr('sing-box', '172.19.0.1'), // наш WinTUN
        const NetAddr('vEthernet (WSL)', '172.24.16.1'),
        const NetAddr('tun0', '10.0.0.2'), // VPN на Android
        const NetAddr('Ethernet 3', '172.19.0.2'), // адрес из нашей подсети TUN
      ];
      expect(NetworkWatcher.signature(withNoise), NetworkWatcher.signature(base));
    });

    test('смена Wi-Fi-адреса или переход на мобильную сеть — новая подпись', () {
      final home = NetworkWatcher.signature([const NetAddr('Wi-Fi', '192.168.0.55')]);
      final cafe = NetworkWatcher.signature([const NetAddr('Wi-Fi', '10.1.2.3')]);
      final mobile = NetworkWatcher.signature([const NetAddr('rmnet_data0', '100.64.1.2')]);
      expect(cafe, isNot(home));
      expect(mobile, isNot(home));
    });

    test('порядок адаптеров не важен', () {
      final a = NetworkWatcher.signature([const NetAddr('Wi-Fi', '192.168.0.55'), const NetAddr('Ethernet', '10.0.0.5')]);
      final b = NetworkWatcher.signature([const NetAddr('Ethernet', '10.0.0.5'), const NetAddr('Wi-Fi', '192.168.0.55')]);
      expect(a, b);
    });
  });
}
