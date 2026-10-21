import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/reminders/reminder_actions.dart';
import 'package:organizacional/reminders/reminder_times.dart';

NotificationResponse response({String? actionId, String? payload, NotificationResponseType? type}) =>
    NotificationResponse(
      notificationResponseType: type ??
          (actionId == null
              ? NotificationResponseType.selectedNotification
              : NotificationResponseType.selectedNotificationAction),
      actionId: actionId,
      payload: payload,
    );

void main() {
  test('payload de ida e volta', () {
    expect(reminderPayload(ReminderKind.task, 'abc'), 'task:abc');
    expect(parseReminderPayload('task:abc'), (ReminderKind.task, 'abc'));
    expect(parseReminderPayload('event:e-1:2'), (ReminderKind.event, 'e-1:2'));
  });

  test('payload inválido vira nulo', () {
    for (final p in [null, '', 'task', 'task:', 'x:1', ':1']) {
      expect(parseReminderPayload(p), isNull, reason: '$p');
    }
  });

  test('toque abre /tarefas ou /agenda', () {
    expect(routeForReminderPayload('task:t1'), '/tarefas');
    expect(routeForReminderPayload('event:e1'), '/agenda');
    expect(routeForReminderPayload('lixo'), isNull);
    expect(routeForReminderPayload(null), isNull);
  });

  group('handleReminderResponse (ação Concluir)', () {
    test('Concluir numa tarefa marca como feita e cancela os avisos dela', () async {
      final done = <String>[];
      final cancelled = <String>[];
      final ok = await handleReminderResponse(
        response(actionId: reminderDoneActionId, payload: 'task:t1'),
        complete: (id) async => done.add(id),
        cancelPending: (id) async => cancelled.add(id),
      );
      expect(ok, isTrue);
      expect(done, ['t1']);
      expect(cancelled, ['t1']);
    });

    test('toque simples não conclui nada', () async {
      final done = <String>[];
      final ok = await handleReminderResponse(
        response(payload: 'task:t1'),
        complete: (id) async => done.add(id),
        cancelPending: (id) async {},
      );
      expect(ok, isFalse);
      expect(done, isEmpty);
    });

    test('Concluir em evento ou payload estranho é ignorado', () async {
      final done = <String>[];
      for (final p in ['event:e1', 'lixo', null]) {
        final ok = await handleReminderResponse(
          response(actionId: reminderDoneActionId, payload: p),
          complete: (id) async => done.add(id),
          cancelPending: (id) async {},
        );
        expect(ok, isFalse, reason: '$p');
      }
      expect(done, isEmpty);
    });

    test('falha ao gravar (sem rede/sessão) não lança e não cancela os avisos', () async {
      final cancelled = <String>[];
      final ok = await handleReminderResponse(
        response(actionId: reminderDoneActionId, payload: 'task:t1'),
        complete: (id) async => throw Exception('sem rede'),
        cancelPending: (id) async => cancelled.add(id),
      );
      expect(ok, isFalse);
      expect(cancelled, isEmpty);
    });
  });
}
