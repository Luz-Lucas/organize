import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/reminders/reminder_plugin_sink.dart';
import 'package:organizacional/reminders/reminder_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

ScheduledReminder reminder(int id, {bool canComplete = false, String payload = 'event:e1'}) => ScheduledReminder(
      id: id,
      fireAt: DateTime(2026, 10, 22, 14, 30),
      title: 'Reunião',
      body: 'Começa às 15:00',
      payload: payload,
      canComplete: canComplete,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late bool notificationsEnabled;
  late bool exactAllowed;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    calls = [];
    notificationsEnabled = true;
    exactAllowed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'areNotificationsEnabled':
          return notificationsEnabled;
        case 'canScheduleExactNotifications':
          return exactAllowed;
        case 'requestNotificationsPermission':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Iterable<String> names() => calls.map((c) => c.method);
  Iterable<MethodCall> scheduled() => calls.where((c) => c.method == 'zonedSchedule');

  test('replaceAll cancela os avisos pendentes e agenda cada um com id, texto e payload', () async {
    final sink = PluginReminderSink();
    await sink.replaceAll([reminder(7), reminder(8, canComplete: true, payload: 'task:t1')]);

    expect(names().where((n) => n == 'initialize'), hasLength(1));
    expect(names(), contains('cancelAllPendingNotifications'));
    expect(names().toList().indexOf('cancelAllPendingNotifications'),
        lessThan(names().toList().indexOf('zonedSchedule')));
    final s = scheduled().toList();
    expect(s, hasLength(2));
    expect(s[0].arguments['id'], 7);
    expect(s[0].arguments['title'], 'Reunião');
    expect(s[0].arguments['body'], 'Começa às 15:00');
    expect(s[0].arguments['payload'], 'event:e1');
    expect(s[1].arguments['payload'], 'task:t1');
  });

  test('só tarefa tem o botão Concluir, que não abre o app', () async {
    final sink = PluginReminderSink();
    await sink.replaceAll([reminder(7), reminder(8, canComplete: true, payload: 'task:t1')]);

    List actionsOf(MethodCall c) => (c.arguments['platformSpecifics']['actions'] as List?) ?? const [];
    final s = scheduled().toList();
    expect(actionsOf(s[0]), isEmpty);
    final actions = actionsOf(s[1]);
    expect(actions, hasLength(1));
    expect(actions.single['id'], 'done');
    expect(actions.single['title'], 'Concluir');
    expect(actions.single['showsUserInterface'], isFalse);
  });

  test('o horário vai como instante absoluto (fuso UTC), igual ao do aviso', () async {
    final sink = PluginReminderSink();
    final r = reminder(7);
    await sink.replaceAll([r]);
    final iso = scheduled().single.arguments['scheduledDateTimeISO8601'] as String;
    expect(DateTime.parse(iso).toUtc(), r.fireAt.toUtc());
  });

  test('usa alarme exato quando permitido e inexato quando não', () async {
    await PluginReminderSink().replaceAll([reminder(7)]);
    expect(scheduled().single.arguments['platformSpecifics']['scheduleMode'], 'exactAllowWhileIdle');

    calls.clear();
    exactAllowed = false;
    await PluginReminderSink().replaceAll([reminder(7)]);
    expect(scheduled().single.arguments['platformSpecifics']['scheduleMode'], 'inexactAllowWhileIdle');
  });

  test('lista vazia só cancela', () async {
    await PluginReminderSink().replaceAll(const []);
    expect(names(), contains('cancelAllPendingNotifications'));
    expect(scheduled(), isEmpty);
  });

  test('requestPermission: já concedida, não pergunta', () async {
    await PluginReminderSink().requestPermission();
    expect(names(), isNot(contains('requestNotificationsPermission')));
  });

  test('requestPermission: pergunta na primeira vez, não repete sem force, repete com force', () async {
    notificationsEnabled = false;
    final sink = PluginReminderSink();
    await sink.requestPermission();
    expect(names().where((n) => n == 'requestNotificationsPermission'), hasLength(1));
    await sink.requestPermission();
    expect(names().where((n) => n == 'requestNotificationsPermission'), hasLength(1));
    await sink.requestPermission(force: true);
    expect(names().where((n) => n == 'requestNotificationsPermission'), hasLength(2));
  });

  test('cancelPendingForTask cancela só os avisos pendentes daquela tarefa', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingNotificationRequests') {
        return [
          {'id': 1, 'title': 'a', 'body': 'b', 'payload': 'task:t1'},
          {'id': 2, 'title': 'a', 'body': 'b', 'payload': 'task:t2'},
          {'id': 3, 'title': 'a', 'body': 'b', 'payload': 'task:t1'},
          {'id': 4, 'title': 'a', 'body': 'b', 'payload': 'event:t1'},
        ];
      }
      return true;
    });
    await PluginReminderSink().cancelPendingForTask('t1');
    final cancelled = calls.where((c) => c.method == 'cancel').map((c) => c.arguments['id'] ?? c.arguments).toList();
    expect(cancelled, [1, 3]);
  });
}
