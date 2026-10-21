import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar_event.dart';
import '../domain/task_item.dart';
import '../domain/user_settings.dart';
import '../widgets/widget_background.dart';
import 'reminder_actions.dart';
import 'reminder_plugin_sink.dart';
import 'reminder_scheduler.dart';

/// Consultas do segundo plano para reagendar os lembretes (injetáveis nos testes).
abstract interface class ReminderDataSource {
  Future<List<TaskItem>> openTasks();
  Future<List<CalendarEvent>> events(DateTime from, DateTime to);
  Future<UserSettings> settings();
}

class SupabaseReminderDataSource implements ReminderDataSource {
  SupabaseReminderDataSource(this._db);

  final SupabaseClient _db;

  @override
  Future<List<TaskItem>> openTasks() async {
    final rows = await _db.from('tasks').select().neq('status', 'done').not('due_at', 'is', null);
    return rows.map(TaskItem.fromMap).toList();
  }

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    final rows = await _db
        .from('events')
        .select()
        .gte('ends_at', from.toUtc().toIso8601String())
        .lte('starts_at', to.toUtc().toIso8601String())
        .order('starts_at', ascending: true);
    return rows.map(CalendarEvent.fromMap).toList();
  }

  @override
  Future<UserSettings> settings() async {
    final row = await _db.from('user_settings').select().maybeSingle();
    return row == null ? const UserSettings() : UserSettings.fromMap(row);
  }
}

/// Busca tarefas, eventos e ajustes e reagenda os lembretes. [source] nulo = sem sessão:
/// cancela tudo (o aparelho não deve avisar de uma conta que saiu). Falha ao buscar (sem rede)
/// mantém o que já estava agendado e devolve `false`.
Future<bool> runReminderReschedule({
  required ReminderDataSource? source,
  required ReminderSink sink,
  required DateTime now,
}) async {
  if (source == null) {
    await sink.replaceAll(const []);
    return true;
  }
  final List<TaskItem> tasks;
  final List<CalendarEvent> events;
  final UserSettings settings;
  try {
    tasks = await source.openTasks();
    // Horizonte de 3 dias mais a antecedência máxima (1 dia) e uma folga.
    events = await source.events(now, now.add(reminderHorizon + const Duration(days: 2)));
    settings = await source.settings();
  } catch (_) {
    return false;
  }
  await rescheduleReminders(sink: sink, tasks: tasks, events: events, settings: settings, now: now);
  return true;
}

/// Reagenda no isolate do workmanager (junto da atualização dos widgets).
Future<bool> rescheduleRemindersInBackground({
  required SupabaseClient? Function() client,
  required DateTime now,
}) async {
  DartPluginRegistrant.ensureInitialized();
  final c = client();
  final signedIn = c != null && c.auth.currentSession != null;
  return runReminderReschedule(
    source: signedIn ? SupabaseReminderDataSource(c) : null,
    sink: PluginReminderSink(),
    now: now,
  );
}

/// Marca a tarefa como feita (botão "Concluir" da notificação): `status=done`, `completed_at=agora`.
Future<void> completeTaskInBackground(SupabaseClient? client, String taskId, DateTime now) async {
  if (client == null || client.auth.currentSession == null) throw StateError('sem sessão');
  await client
      .from('tasks')
      .update({'status': 'done', 'completed_at': now.toUtc().toIso8601String()})
      .eq('id', taskId);
}

/// Chamado pelo plugin num isolate sem interface quando o usuário toca em "Concluir".
@pragma('vm:entry-point')
Future<void> reminderBackgroundResponse(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final sink = PluginReminderSink();
  await handleReminderResponse(
    response,
    complete: (id) async => completeTaskInBackground(await backgroundSupabaseClient(), id, DateTime.now()),
    cancelPending: sink.cancelPendingForTask,
  );
}
