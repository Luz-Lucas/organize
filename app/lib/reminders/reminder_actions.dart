import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'reminder_times.dart';

/// Id do botão "Concluir" da notificação de tarefa.
const reminderDoneActionId = 'done';

/// Payload da notificação: `task:<id>` ou `event:<id>`.
String reminderPayload(ReminderKind kind, String itemId) => '${kind.name}:$itemId';

(ReminderKind, String)? parseReminderPayload(String? payload) {
  if (payload == null) return null;
  final i = payload.indexOf(':');
  if (i <= 0 || i == payload.length - 1) return null;
  final kind = switch (payload.substring(0, i)) {
    'task' => ReminderKind.task,
    'event' => ReminderKind.event,
    _ => null,
  };
  return kind == null ? null : (kind, payload.substring(i + 1));
}

/// Rota aberta ao tocar na notificação: tarefa -> `/tarefas`, evento -> `/agenda`.
String? routeForReminderPayload(String? payload) => switch (parseReminderPayload(payload)?.$1) {
      ReminderKind.task => '/tarefas',
      ReminderKind.event => '/agenda',
      null => null,
    };

/// Trata o botão "Concluir" (a tarefa vira feita e os avisos que sobraram dela somem).
/// Devolve `true` só se concluiu. Sem sessão/rede ou payload estranho: não faz nada e não lança.
Future<bool> handleReminderResponse(
  NotificationResponse response, {
  required Future<void> Function(String taskId) complete,
  required Future<void> Function(String taskId) cancelPending,
}) async {
  if (response.actionId != reminderDoneActionId) return false;
  final parsed = parseReminderPayload(response.payload);
  if (parsed == null || parsed.$1 != ReminderKind.task) return false;
  final id = parsed.$2;
  try {
    await complete(id);
  } catch (_) {
    return false;
  }
  try {
    await cancelPending(id);
  } catch (_) {
    // Os avisos restantes somem na próxima reagenda (a tarefa feita não avisa).
  }
  return true;
}
