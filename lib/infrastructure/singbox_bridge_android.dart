import 'dart:async';
import 'dart:io';

import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/log_service.dart';
import '../domain/entities/node.dart';
import 'singbox_bridge.dart';

class SingboxBridgeAndroid implements SingboxBridge {
  SingboxBridgeAndroid._();
  static final instance = SingboxBridgeAndroid._();

  BridgeState _state = BridgeState.idle;

  final _stateCtrl = StreamController<BridgeState>.broadcast();
  final _statsCtrl = StreamController<(int rx, int tx)>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  bool _initialized = false;


  late final FlutterV2ray _v2ray = FlutterV2ray(
    onStatusChanged: (V2RayStatus status) {

      log.i('[V2RAY] state=${status.state} '
          'duration=${status.duration} '
          'upload=${status.upload} '
          'download=${status.download}', tag: 'BRIDGE');

      switch (status.state) {
        case 'CONNECTED':
          _setState(BridgeState.running);
        case 'CONNECTING':
          _setState(BridgeState.starting);
        case 'DISCONNECTED':
          if (_state != BridgeState.idle) {
            _setState(BridgeState.idle);
          }
        case 'ERROR':
          _setState(BridgeState.error);
          _errorCtrl.add('V2Ray connection error');
      }

      // Emit traffic stats on every status update
      if (status.state == 'CONNECTED') {
        _statsCtrl.add((
        status.download.toInt(),
        status.upload.toInt(),
        ));
      }
    },
  );

  @override
  Future<void> ensureBinaries({
    void Function(String, double?)? onStatus,
  }) async {
    if (!_initialized) {
      await _v2ray.initializeV2Ray(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      _initialized = true;
    }
    onStatus?.call('Готово', 1.0);
  }

  @override
  bool get binariesReady => true;

  @override
  Future<BridgeResult> start(Node node, {bool smartRouting = true}) async {
    if (_state == BridgeState.running || _state == BridgeState.starting) {
      return const BridgeResult(success: false, error: 'Уже запущен');
    }

    _setState(BridgeState.starting);
    log.i('Запускаем V2Ray для ${node.name} (Android)', tag: 'BRIDGE');

    try {
      if (!_initialized) await ensureBinaries();

      // Android 13+ (API 33) требует явного runtime-разрешения на показ
      // ЛЮБЫХ уведомлений, включая foreground-уведомление активного
      // VpnService. Без этого разрешения ни родное уведомление плагина,
      // ни наше собственное (VpnNotificationService) не покажутся —
      // без ошибки, просто молча. На более старых версиях Android
      // Permission.notification.request() возвращает granted сразу,
      // диалог не показывается.
      //
      // Намеренно не блокируем подключение, если пользователь отказал —
      // VPN должен продолжать работать, просто без уведомления о статусе.
      final notifStatus = await Permission.notification.status;
      if (notifStatus.isDenied) {
        final result = await Permission.notification.request();
        log.i('Разрешение на уведомления: $result', tag: 'BRIDGE');
      }

      final allowed = await _v2ray.requestPermission();
      if (!allowed) {
        _setState(BridgeState.idle);
        return const BridgeResult(
          success: false,
          error: 'VPN permission denied by user',
        );
      }

      // Resolve server IP before VPN starts to prevent routing loop
      final resolvedIp = await _resolveServerIp(node.host);
      log.i('Resolved ${node.host} → $resolvedIp', tag: 'BRIDGE');

      // Build vless:// share link from Node and parse it
      final shareLink = node.toShareLink();
      log.d('Share link: $shareLink', tag: 'BRIDGE');

      final V2RayURL parsed = FlutterV2ray.parseFromURL(shareLink);

      // Inject smart routing DNS
      parsed.dns = _buildDns(smartRouting: smartRouting);

      // Inject routing rules
      parsed.routing = _buildRouting(
        resolvedServerIp: resolvedIp,
        smartRouting: smartRouting,
      );

      final config = parsed.getFullConfiguration();
      log.d('V2Ray config: $config', tag: 'BRIDGE');

      await _v2ray.startV2Ray(
        remark: node.name,
        config: config,
        blockedApps: null,
        bypassSubnets: smartRouting ? _ruSubnets : null,
        proxyOnly: false,
        // Кнопка "Отключить" в родном уведомлении плагина (то самое
        // системное foreground-уведомление, которое Android требует для
        // любого активного VpnService и убрать нельзя). Эта кнопка
        // останавливает VPN на нативном уровне и триггерит наш
        // onStatusChanged → DISCONNECTED, так что состояние в Riverpod
        // корректно обновится даже если приложение свёрнуто.
        notificationDisconnectButtonName: 'ОТКЛЮЧИТЬ',
      );

      log.i('V2Ray started for ${node.name}', tag: 'BRIDGE');
      return const BridgeResult(success: true);
    } catch (e, stack) {
      log.e('Start error: $e', tag: 'BRIDGE');
      log.d('Stack: $stack', tag: 'BRIDGE');
      _setState(BridgeState.error);
      return BridgeResult(success: false, error: e.toString());
    }
  }

  @override
  Future<void> stop() async {
    log.i('Stopping V2Ray...', tag: 'BRIDGE');
    await _v2ray.stopV2Ray();
    _setState(BridgeState.idle);
  }

  @override
  Stream<BridgeState> get stateStream => _stateCtrl.stream;
  @override
  Stream<(int rx, int tx)> get statsStream => _statsCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  BridgeState get state => _state;

  void _setState(BridgeState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  Future<String?> _resolveServerIp(String host) async {
    if (_isIpAddress(host)) return null;
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull;
      return ipv4?.address ?? addresses.firstOrNull?.address;
    } catch (_) {
      return null;
    }
  }

  bool _isIpAddress(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
          host.contains(':');

  Map<String, dynamic> _buildDns({bool smartRouting = false}) => {
    'servers': [
      if (smartRouting)
        {
          'address': '77.88.8.8',
          'domains': [
            'geosite:ru',
            'geosite:yandex',
            'geosite:vk',
            'geosite:mailru',
          ],
        },
      {
        'address': 'https://8.8.8.8/dns-query',
      },
      'localhost',
    ],
    'queryStrategy': 'UseIPv4',
  };

  Map<String, dynamic> _buildRouting({
    String? resolvedServerIp,
    bool smartRouting = true,
  }) {
    final rules = <Map<String, dynamic>>[
      {
        'type': 'field',
        'ip': ['geoip:private'],
        'outboundTag': 'direct',
      },
      if (resolvedServerIp != null)
        {
          'type': 'field',
          'ip': ['$resolvedServerIp/32'],
          'outboundTag': 'direct',
        },
      if (smartRouting) ...[
        {
          'type': 'field',
          'domain': [
            'geosite:ru',
            'geosite:yandex',
            'geosite:vk',
            'geosite:mailru',
          ],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'ip': ['geoip:ru'],
          'outboundTag': 'direct',
        },
      ],
    ];

    return {
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
    };
  }

  static const List<String> _ruSubnets = [
    '2.56.168.0/21',
    '5.8.0.0/21',
    '5.16.0.0/14',
    '5.45.192.0/18',
    '5.53.32.0/19',
    '5.101.192.0/18',
    '37.9.0.0/20',
    '37.18.16.0/21',
    '46.8.0.0/15',
    '77.88.0.0/18',
    '84.201.128.0/17',
    '87.228.0.0/14',
    '91.108.4.0/22',
    '91.108.56.0/22',
    '149.154.160.0/20',
    '185.76.144.0/22',
    '188.72.96.0/20',
    '195.209.80.0/22',
  ];
}