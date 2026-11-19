// Тон оговорок автопилота в интерфейсе (#66): значок тоста и лента событий.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/vpn_state.dart';
import 'package:onyx/presentation/providers/activity_provider.dart';
import 'package:onyx/presentation/providers/connect_phase.dart';
import 'package:onyx/presentation/providers/vpn_provider.dart';
import 'package:onyx/presentation/widgets/home_parts.dart';
import 'package:onyx/presentation/widgets/onyx_icon.dart';

class _FakeVpn extends StateNotifier<VpnState> implements VpnController {
  _FakeVpn() : super(const VpnDisconnected());
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

void main() {
  test('значок тоста по тону оговорки', () {
    expect(noticeGlyph(NoticeKind.warning), OnyxGlyph.error);
    expect(noticeGlyph(NoticeKind.switched), OnyxGlyph.zap);
    expect(noticeGlyph(NoticeKind.recovered), OnyxGlyph.check);
    expect(noticeGlyph(NoticeKind.info), OnyxGlyph.info);
  });

  test('лента событий: цвет по тону, «переключились» не дублируется, флаги убраны', () {
    final c = ProviderContainer(overrides: [vpnControllerProvider.overrideWith((ref) => _FakeVpn())]);
    addTearDown(c.dispose);
    c.read(activityProvider);
    final phase = c.read(connectPhaseProvider.notifier);

    phase.state = const ConnectPhase.notice('Соединение восстановлено после спящего режима', kind: NoticeKind.recovered);
    expect(c.read(activityProvider).first.kind, ActivityKind.connected);

    phase.state = const ConnectPhase.notice('Связь с 🇳🇱 AMS-03 постоянно рвётся.', kind: NoticeKind.warning);
    expect(c.read(activityProvider).first.kind, ActivityKind.warning);
    expect(c.read(activityProvider).first.text, 'Связь с AMS-03 постоянно рвётся.');

    final before = c.read(activityProvider).length;
    phase.state = const ConnectPhase.notice('Переключились: HEL-02 → AMS-03', kind: NoticeKind.switched);
    expect(c.read(activityProvider).length, before);
  });
}
