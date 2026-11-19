/// Группа серверов.
///
/// Пользовательская группа содержит отдельные ноды ([nodeIds]) и целые
/// источники ([sourceIds] — все их ноды, включая появившиеся после
/// обновления). Группы-источники ([isVirtual]) строятся автоматически:
/// по одной на каждый источник, их id — `src:<sourceId>`.
class NodeGroup {
  const NodeGroup({
    required this.id,
    required this.name,
    this.nodeIds = const [],
    this.sourceIds = const [],
    this.isVirtual = false,
  });

  final String id;
  final String name;
  final List<String> nodeIds;
  final List<String> sourceIds;
  final bool isVirtual;

  static const sourcePrefix = 'src:';

  /// Спец-id для автовыбора (фильтры поверх всех включённых нод).
  static const favoritesId = 'auto:fav';
  static const udpId = 'auto:udp';
  static const aiId = 'auto:ai';

  /// «Свои» серверы — добавленные ссылками, а не подпиской (#68).
  static const ownId = 'auto:own';

  static String idForSource(String sourceId) => '$sourcePrefix$sourceId';

  NodeGroup copyWith({String? name, List<String>? nodeIds, List<String>? sourceIds}) =>
      NodeGroup(
        id: id,
        name: name ?? this.name,
        nodeIds: nodeIds ?? this.nodeIds,
        sourceIds: sourceIds ?? this.sourceIds,
        isVirtual: isVirtual,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nodeIds': nodeIds,
        'sourceIds': sourceIds,
      };

  factory NodeGroup.fromJson(Map<String, dynamic> j) => NodeGroup(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Группа',
        nodeIds: (j['nodeIds'] as List?)?.whereType<String>().toList() ?? const [],
        sourceIds: (j['sourceIds'] as List?)?.whereType<String>().toList() ?? const [],
      );

  @override
  String toString() => 'Group($id, $name, nodes=${nodeIds.length}, sources=${sourceIds.length})';
}
