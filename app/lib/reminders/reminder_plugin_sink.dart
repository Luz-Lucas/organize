import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_actions.dart';
import 'reminder_scheduler.dart';
import 'reminder_times.dart';

const _askedKey = 'reminders_permission_asked';
const _icon = '@drawable/ic_launcher_mono';

/// Lembretes do celular com o `flutter_local_notifications` (só Android).
class PluginReminderSink implements ReminderSink {
  PluginReminderSink({FlutterLocalNotificationsPlugin? plugin, this.onOpen, this.onBackgroundResponse})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Rota a abrir quando o usuário toca numa notificação (app aberto ou em segundo plano).
  final void Function(String route)? onOpen;

  /// Função de nível superior (`@pragma('vm:entry-point')`) que trata o botão "Concluir".
  final DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse;

  Future<void>? _init;

  /// Inicializa o plugin uma vez por isolate (no segundo plano, sem os callbacks).
  Future<void> ensureInitialized() => _init ??= _plugin
      .initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings(_icon)),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
      )
      .then((_) {});

  void _onResponse(NotificationResponse r) {
    final route = routeForReminderPayload(r.payload);
    if (route != null) onOpen?.call(route);
  }

  /// A rota da notificação que abriu o app (app fechado), se foi aberto por uma de lembrete.
  Future<String?> launchRoute() async {
    await ensureInitialized();
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    final r = d.notificationResponse;
    // O botão Concluir não abre o app; qualquer outra resposta abre a lista.
    if (r == null || r.actionId == reminderDoneActionId) return null;
    return routeForReminderPayload(r.payload);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> requestPermission({bool force = false}) async {
    await ensureInitialized();
    final android = _android;
    if (android == null) return;
    if (await android.areNotificationsEnabled() ?? false) return;
    final prefs = await SharedPreferences.getInstance();
    if (!force && (prefs.getBool(_askedKey) ?? false)) return;
    await prefs.setBool(_askedKey, true);
    await android.requestNotificationsPermission();
  }

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {
    await ensureInitialized();
    await _plugin.cancelAllPendingNotifications();
    if (reminders.isEmpty) return;
    // Sem permissão de alarme exato (Android 12+ negado) cai no inexato, que ainda avisa perto da hora.
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        // Instante absoluto (UTC): o horário local já foi resolvido em reminderFires.
        scheduledDate: tz.TZDateTime.from(r.fireAt, tz.UTC),
        notificationDetails: NotificationDetails(android: _details(r)),
        androidScheduleMode: mode,
        payload: r.payload,
      );
    }
  }

  AndroidNotificationDetails _details(ScheduledReminder r) => AndroidNotificationDetails(
        'lembretes',
        'Lembretes',
        channelDescription: 'Avisos antes de tarefas e eventos',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: _icon,
        actions: [
          if (r.canComplete) const AndroidNotificationAction(reminderDoneActionId, 'Concluir'),
        ],
      );

  /// Cancela os avisos ainda agendados de uma tarefa (ela foi concluída fora do app).
  Future<void> cancelPendingForTask(String taskId) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.payload == reminderPayload(ReminderKind.task, taskId)) await _plugin.cancel(id: p.id);
    }
  }
}
