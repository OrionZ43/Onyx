/// Источник серверов: URL-подписка или набор вставленных ссылок.
enum SourceKind { subscription, links }

/// Состояние загрузки источника (пробы нод — общие, в subscriptionProvider).
enum SourceStatus { idle, fetching, error }

class SubscriptionSource {
  const SubscriptionSource({
    required this.id,
    required this.name,
    required this.kind,
    this.url,
    this.rawLinks,
    this.presetId,
    this.mirrors = const [],
    this.enabled = true,
    this.autoUpdateHours = 0,
    this.lastUpdatedAt,
    this.nodeCount = 0,
    this.status = SourceStatus.idle,
    this.error,
  });

  final String id;
  final String name;
  final SourceKind kind;

  /// URL подписки (для [SourceKind.subscription]).
  final String? url;

  /// Исходный текст ссылок (для [SourceKind.links]) — чтобы «обновить»
  /// пересобрало ноды тем же парсером (например, после его улучшения).
  final String? rawLinks;

  /// Встроенный пресет, из которого добавлен источник ('china-free', 'zieng2').
  final String? presetId;

  /// Зеркала URL: перебираются, если основной недоступен.
  final List<String> mirrors;

  /// Выключенный источник не участвует в списке нод и автовыборе.
  final bool enabled;

  /// Период автообновления в часах; 0 — только вручную.
  final int autoUpdateHours;

  final DateTime? lastUpdatedAt;
  final int nodeCount;

  /// Не сохраняется: после перезапуска всегда idle.
  final SourceStatus status;
  final String? error;

  bool get isPreset => presetId != null;

  /// Пора ли обновить по расписанию.
  bool isDue(DateTime now) {
    if (!enabled || autoUpdateHours <= 0 || kind != SourceKind.subscription) {
      return false;
    }
    final last = lastUpdatedAt;
    return last == null || now.difference(last) >= Duration(hours: autoUpdateHours);
  }

  SubscriptionSource copyWith({
    String? name,
    String? url,
    String? rawLinks,
    List<String>? mirrors,
    bool? enabled,
    int? autoUpdateHours,
    DateTime? lastUpdatedAt,
    int? nodeCount,
    SourceStatus? status,
    String? error,
    bool clearError = false,
  }) =>
      SubscriptionSource(
        id: id,
        name: name ?? this.name,
        kind: kind,
        url: url ?? this.url,
        rawLinks: rawLinks ?? this.rawLinks,
        presetId: presetId,
        mirrors: mirrors ?? this.mirrors,
        enabled: enabled ?? this.enabled,
        autoUpdateHours: autoUpdateHours ?? this.autoUpdateHours,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
        nodeCount: nodeCount ?? this.nodeCount,
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        if (url != null) 'url': url,
        if (rawLinks != null) 'rawLinks': rawLinks,
        if (presetId != null) 'presetId': presetId,
        if (mirrors.isNotEmpty) 'mirrors': mirrors,
        'enabled': enabled,
        'autoUpdateHours': autoUpdateHours,
        if (lastUpdatedAt != null) 'lastUpdatedAt': lastUpdatedAt!.millisecondsSinceEpoch,
        'nodeCount': nodeCount,
      };

  factory SubscriptionSource.fromJson(Map<String, dynamic> j) => SubscriptionSource(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Подписка',
        kind: SourceKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => SourceKind.subscription,
        ),
        url: j['url'] as String?,
        rawLinks: j['rawLinks'] as String?,
        presetId: j['presetId'] as String?,
        mirrors: (j['mirrors'] as List?)?.whereType<String>().toList() ?? const [],
        enabled: j['enabled'] as bool? ?? true,
        autoUpdateHours: j['autoUpdateHours'] as int? ?? 0,
        lastUpdatedAt: j['lastUpdatedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(j['lastUpdatedAt'] as int)
            : null,
        nodeCount: j['nodeCount'] as int? ?? 0,
      );

  @override
  String toString() => 'Source($id, $name, ${kind.name}, enabled=$enabled, nodes=$nodeCount)';
}
