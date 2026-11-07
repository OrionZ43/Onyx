/// Регион умной маршрутизации: чей «домашний» трафик идёт мимо туннеля.
///
///   • [russia] — прежнее поведение Onyx: RU/BY-сайты и CDN напрямую.
///   • [china]  — для пользователей в материковом Китае: CN-сайты (WeChat,
///                Bilibili, Taobao, банки) напрямую, локальный DNS 223.5.5.5,
///                всё остальное — через туннель.
///
/// Работает только при включённой умной маршрутизации (smartRouting).
enum RoutingRegion { russia, china }

extension RoutingRegionLabel on RoutingRegion {
  String get label => switch (this) {
        RoutingRegion.russia => 'Россия/Беларусь',
        RoutingRegion.china => 'Китай',
      };

  static RoutingRegion parse(String? v) => RoutingRegion.values.firstWhere(
        (r) => r.name == v,
        orElse: () => RoutingRegion.russia,
      );
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
