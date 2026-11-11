import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Почему автопилот не смог подключиться.
enum ConnectFailure {
  /// Нет ни одного включённого источника серверов.
  noSources,

  /// Источники есть, но ни один не загрузился (и кэша нет).
  sourcesUnreachable,

  /// Серверы загружены, но ни один не отвечает.
  allDead,
}

/// Что предложить пользователю при ошибке.
enum ConnectAction {
  /// Обновить и попробовать ещё раз (smartConnect()).
  refresh,

  /// Открыть добавление своего сервера / подписки.
  addServer,

  /// Инструкция «свой сервер на AWS» (docs/china/aws-setup.md).
  awsGuide,
}

/// Тон оговорки ([ConnectNotice]) — UI выбирает по нему значок, цвет в ленте
/// событий и нужно ли системное уведомление, когда Onyx свёрнут в трей.
/// Различать оговорки по тексту нельзя: текст правится.
enum NoticeKind {
  /// Нейтральная оговорка.
  info,

  /// Соединение восстановлено (после смены сети, спящего режима, сбоя).
  recovered,

  /// Автопилот переключил сервер.
  switched,

  /// Что-то не так: сервер не отвечает, связь рвётся, стабильного сервера
  /// нет, не нашлось сервера с UDP.
  warning,
}

/// Этап автопилота «один тап» — для подписи под кнопкой подключения.
sealed class ConnectPhase {
  const ConnectPhase();

  static const idle = ConnectIdle();
  static const updating = ConnectUpdating();
  const factory ConnectPhase.checking(int done, int total) = ConnectChecking;
  const factory ConnectPhase.connecting(String nodeName) = ConnectConnecting;
  const factory ConnectPhase.switching(String from, String to) = ConnectSwitching;
  const factory ConnectPhase.notice(String message, {NoticeKind kind}) = ConnectNotice;
  const factory ConnectPhase.failed(
    ConnectFailure reason,
    String message,
    List<ConnectAction> actions,
  ) = ConnectFailed;

  /// Готовая строка для UI.
  String get label;

  /// Идёт работа (кнопку крутим).
  bool get busy => false;
}

class ConnectIdle extends ConnectPhase {
  const ConnectIdle();
  @override
  String get label => '';
}

class ConnectUpdating extends ConnectPhase {
  const ConnectUpdating();
  @override
  String get label => 'Обновляю подписку…';
  @override
  bool get busy => true;
}

class ConnectChecking extends ConnectPhase {
  const ConnectChecking(this.done, this.total);
  final int done;
  final int total;
  @override
  String get label => total > 0 ? 'Проверяю серверы… $done/$total' : 'Проверяю серверы…';
  @override
  bool get busy => true;
}

class ConnectConnecting extends ConnectPhase {
  const ConnectConnecting(this.nodeName);
  final String nodeName;
  @override
  String get label => 'Подключаюсь к $nodeName…';
  @override
  bool get busy => true;
}

class ConnectSwitching extends ConnectPhase {
  const ConnectSwitching(this.from, this.to);
  final String from;
  final String to;
  @override
  String get label => 'Переключаюсь на $to…';
  @override
  bool get busy => true;
}

/// Подключились, но с оговоркой (например, нет сервера с UDP для голоса).
/// UI показывает тостом; [kind] — тон оговорки.
class ConnectNotice extends ConnectPhase {
  const ConnectNotice(this.message, {this.kind = NoticeKind.info});
  final String message;
  final NoticeKind kind;
  @override
  String get label => message;
}

class ConnectFailed extends ConnectPhase {
  const ConnectFailed(this.reason, this.message, this.actions);
  final ConnectFailure reason;
  final String message;
  final List<ConnectAction> actions;
  @override
  String get label => message;
}

final connectPhaseProvider = StateProvider<ConnectPhase>((_) => ConnectPhase.idle);
