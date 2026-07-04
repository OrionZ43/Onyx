// lib/domain/routing_domains.dart
//
// Единый каталог доменов и подсетей для маршрутизации.
// Используется ОБЕИМИ платформами:
//   • Windows — SingboxConfigBuilder (sing-box: dns.rules / route.rules)
//   • Android — SingboxBridgeAndroid (v2ray/Xray: dns / routing)
//
// Держим списки в одном месте, чтобы платформы никогда не расходились —
// платформенные допущения уже дважды становились источником багов в проекте.

/// ── AI Direct Lane ─────────────────────────────────────────────────────────
///
/// Домены ИИ-сервисов, которые ВСЕГДА идут строго через туннель:
///   • DNS-резолв — только через зашифрованный remote-DNS внутри туннеля
///     (никакого plaintext-резолва через локального провайдера → нет утечки
///     DNS, по которой сервис мог бы определить реальную страну);
///   • трафик — только через outbound `proxy`, с приоритетом выше любых
///     правил умной маршрутизации (geoip/geosite/domain_suffix direct).
///
/// Зачем: пользователи используют Onyx в первую очередь для доступа к
/// заблокированным ИИ. Утечка DNS или гео-IP на любом из этих доменов
/// приводит к "Access Denied"/"Not available in your region" даже при
/// формально работающем VPN.
///
/// Формат — суффиксы доменов (матчится сам домен и все поддомены).
/// При добавлении нового ИИ-сервиса достаточно дописать суффикс сюда:
/// оба платформенных конфига подхватят его автоматически.
const List<String> kAiDomainSuffixes = [
  // OpenAI / ChatGPT / Sora
  'openai.com',
  'chatgpt.com',
  'oaistatic.com',
  'oaiusercontent.com',
  'sora.com',
  'openai.org',

  // Anthropic / Claude
  'anthropic.com',
  'claude.ai',
  'claudeusercontent.com',

  // Google AI (только AI-поддомены, НЕ весь google.com — иначе умная
  // маршрутизация и обычный поиск начнут конфликтовать)
  'gemini.google.com',
  'aistudio.google.com',
  'notebooklm.google.com',
  'ai.google.dev',
  'deepmind.google',
  'generativelanguage.googleapis.com', // Gemini API
  'aiplatform.googleapis.com', // Vertex AI

  // xAI / Grok
  'x.ai',
  'grok.com',

  // Meta AI
  'meta.ai',

  // Microsoft Copilot (только AI-поддомен)
  'copilot.microsoft.com',
  'githubcopilot.com',

  // Mistral
  'mistral.ai',

  // Perplexity
  'perplexity.ai',
  'pplx.ai',

  // Прочие LLM-провайдеры и API-агрегаторы
  'deepseek.com',
  'qwen.ai',
  'cohere.com',
  'groq.com',
  'openrouter.ai',
  'together.ai',
  'fireworks.ai',
  'replicate.com',
  'huggingface.co',
  'hf.co',

  // Генерация изображений/видео/звука
  'midjourney.com',
  'stability.ai',
  'ideogram.ai',
  'lumalabs.ai',
  'runwayml.com',
  'klingai.com',
  'suno.com',
  'suno.ai',
  'elevenlabs.io',

  // AI-инструменты для разработки
  'cursor.com',
  'cursor.sh',
  'codeium.com',
  'windsurf.com',

  // Чат-платформы
  'character.ai',
  'poe.com',
];

/// ── RU CDN / сервисы СНГ ───────────────────────────────────────────────────
///
/// Хардкод-фолбэк для умной маршрутизации: критичные CDN и сервисы,
/// которые должны работать напрямую (в обход туннеля) НЕЗАВИСИМО от
/// наличия/актуальности geosite-БД.
///
/// Перенесено из SingboxConfigBuilder._ruCdnDomainSuffixes без изменений,
/// чтобы Android-мост (где geosite.dat вообще недоступен — см. комментарии
/// в singbox_bridge_android.dart) мог использовать тот же список.
const List<String> kRuCdnDomainSuffixes = [
  // Яндекс — CDN и сервисы
  'yandex.ru',
  'yandex.com',
  'yandex.net',
  'yandex.st',
  'yastatic.net', // главный Яндекс CDN (JS, CSS, изображения)
  'yandexapis.com',
  'ya.ru',
  'yandex-team.ru',

  // VK / Mail.ru Group
  'vk.com',
  'vk.me',
  'vkuseraudio.com',
  'vkuservideo.com',
  'vkontakte.ru',
  'userapi.com', // VK CDN для медиа
  'mail.ru',
  'mailru.com',
  'mradx.net', // Mail.ru рекламная сеть
  'mycdn.me', // OK.ru CDN
  'odnoklassniki.ru',
  'ok.ru',

  // Wildberries
  'wildberries.ru',
  'wb.ru',
  'wbstatic.net', // WB CDN для изображений товаров
  'wbx-ru.net',

  // Ozon
  'ozon.ru',
  'ozon-api.com',
  'ozoncdn.com',
  'cdnvideo.ru', // Ozon видео CDN

  // Сбер / ФинТех
  'sber.ru',
  'sberbank.ru',
  'sberpay.ru',
  'domclick.ru',
  'sbercloud.ru',

  // Прочие крупные RU-сервисы
  'gosuslugi.ru',
  'mos.ru',
  'nalog.ru',
  'pfr.gov.ru',
  'tinkoff.ru',
  'raiffeisen.ru',
  'alfabank.ru',
  'vtb.ru',
  'avito.ru',
  'cian.ru',
  'hh.ru',
  'rbc.ru',
  'ria.ru',
  'kommersant.ru',

  // Стриминг
  'kinopoisk.ru', // принадлежит Яндексу, но CDN отдельный
  'ivi.ru',
  'okko.tv',
  'more.tv',
  'premier.one',
];

/// ── Приватные диапазоны (RFC 1918 + служебные) ─────────────────────────────
///
/// Явный список вместо матчера `geoip:private`.
///
/// Зачем: на Android v2ray-core внутри flutter_v2ray НЕ имеет доступа к
/// geoip.dat (приложение его не бандлит, плагин его не поставляет), и любое
/// правило `geoip:*` валит запуск core. Явные CIDR работают всегда и на
/// обеих платформах ведут себя одинаково.
const List<String> kPrivateCidrs = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '127.0.0.0/8',
  '169.254.0.0/16', // link-local
  '100.64.0.0/10', // CGNAT
  '224.0.0.0/4', // multicast
];

/// RU-подсети, исключаемые из туннеля при умной маршрутизации.
/// (Перенесено из SingboxBridgeAndroid._ruSubnets — см. cidr_utils.dart,
/// почему на Android их нельзя передавать в плагин напрямую.)
const List<String> kRuBypassSubnets = [
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
