/// Регион умной маршрутизации: чей «домашний» трафик идёт мимо туннеля.
///
///   • [russia] — прежнее поведение Onyx: RU/BY-сайты и CDN напрямую.
///   • [china]  — для пользователей в материковом Китае: CN-сайты (WeChat,
///                Bilibili, Taobao, банки) напрямую, локальный DNS 223.5.5.5,
///                всё остальное — через туннель.
///
///   • [auto]   — определить по часовому поясу и локали устройства (Китай,
///                иначе Россия/Беларусь). Значение по умолчанию.
///
/// Работает только при включённой умной маршрутизации (smartRouting).
enum RoutingRegion { auto, russia, china }

extension RoutingRegionLabel on RoutingRegion {
  String get label => switch (this) {
        RoutingRegion.auto => 'Авто (по часовому поясу)',
        RoutingRegion.russia => 'Россия/Беларусь',
        RoutingRegion.china => 'Китай',
      };

  static RoutingRegion parse(String? v) => RoutingRegion.values.firstWhere(
        (r) => r.name == v,
        orElse: () => RoutingRegion.auto,
      );

  /// Конкретный регион: для [RoutingRegion.auto] — определённый по устройству.
  RoutingRegion resolve(RoutingRegion detected) =>
      this == RoutingRegion.auto ? detected : this;

  /// Определение региона без сети: Китай, если часовой пояс UTC+8 и при
  /// этом имя пояса китайское (China/CST/Beijing/Shanghai…) или локаль
  /// zh_CN / zh_Hans_CN. Иначе — Россия/Беларусь. (UTC+8 сам по себе
  /// не годится: это и Сингапур, и Гонконг, и Перт.)
  static RoutingRegion detect({
    required Duration offset,
    required String timeZoneName,
    required String locale,
  }) {
    if (offset != const Duration(hours: 8)) return RoutingRegion.russia;
    final tz = timeZoneName.toLowerCase();
    final loc = locale.toLowerCase().replaceAll('-', '_');
    final chinaTz = ['china', 'cst', 'beijing', 'shanghai', 'chongqing', 'urumqi', 'harbin', 'prc']
        .any(tz.contains);
    final chinaLocale = loc.startsWith('zh_cn') || loc.startsWith('zh_hans_cn') || loc == 'zh_hans';
    return (chinaTz || chinaLocale) ? RoutingRegion.china : RoutingRegion.russia;
  }
}

/// Домены Discord: клиент, API, gateway, CDN, медиа и голос.
///
/// Голос/видео идут по UDP на IP voice-серверов (`*.discord.media`), имя
/// которых клиент резолвит сам; поэтому в режиме Discord, кроме доменов,
/// на Windows ловим ещё и процесс Discord целиком ([kDiscordProcessNames]).
const kDiscordDomainSuffixes = <String>[
  'discord.com',
  'discord.gg',
  'discord.media',
  'discord.dev',
  'discord.new',
  'discord.gift',
  'discord.co',
  'discordapp.com',
  'discordapp.net',
  'discordcdn.com',
  'discordstatus.com',
  'dis.gd',
  'discord-attachments-uploads-prd.storage.googleapis.com',
];

/// Процессы клиента Discord на Windows (stable, PTB, Canary).
const kDiscordProcessNames = <String>[
  'Discord.exe',
  'DiscordPTB.exe',
  'DiscordCanary.exe',
];

/// Пакеты Discord на Android (для документации и будущего libbox-режима).
const kDiscordPackages = <String>['com.discord'];
