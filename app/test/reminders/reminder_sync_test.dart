import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/reminders/reminder_scheduler.dart';
import 'package:organizacional/reminders/reminder_sync.dart';

class FakeSink implements ReminderSink {
  final replaced = <List<ScheduledReminder>>[];
  final permissionRequests = <bool>[];
  bool failReplace = false;
  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {
    if (failReplace) throw Exception('plugin indisponível');
    replaced.add(reminders);
  }

  @override
  Future<void> requestPermission({bool force = false}) async => permissionRequests.add(force);
}

CalendarEvent event(String id, DateTime start) => CalendarEvent(
      id: id,
      title: 'Reunião',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    );

void main() {
  final now = DateTime(2026, 10, 21, 12);

  (ProviderContainer, FakeSink, MemoryRepository, MemorySettingsRepository) setup({
    UserSettings initial = const UserSettings(),
    bool fail = false,
  }) {
    final repo = MemoryRepository();
    final settings = MemorySettingsRepository(initial: initial);
    final sink = FakeSink()..failReplace = fail;
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(settings),
      clockProvider.overrideWithValue(() => now),
      reminderSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    container.listen(reminderSyncProvider, (_, _) {});
    return (container, sink, repo, settings);
  }

  testWidgets('agenda os avisos de eventos e tarefas depois do debounce', (tester) async {
    final (_, sink, repo, _) = setup();
    await repo.upsertEvent(event('e1', DateTime(2026, 10, 22, 15)));
    await repo.upsertTask(TaskItem(id: 't1', title: 'Pagar a luz', dueAt: DateTime(2026, 10, 22, 18)));
    await tester.pump();
    expect(sink.replaced, isEmpty, reason: 'debounce ainda não venceu');
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));

    expect(sink.replaced, hasLength(1));
    expect(sink.replaced.single.map((r) => r.payload), ['event:e1', 'task:t1']);
  });

  testWidgets('mudar uma tarefa reagenda; concluir tira o aviso', (tester) async {
    final (_, sink, repo, _) = setup();
    final t = TaskItem(id: 't1', title: 'Pagar a luz', dueAt: DateTime(2026, 10, 22, 18));
    await repo.upsertTask(t);
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.replaced.last.map((r) => r.payload), ['task:t1']);

    await repo.upsertTask(t.toggled(now));
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.replaced.last, isEmpty);
  });

  testWidgets('desligar a chave do celular limpa os avisos', (tester) async {
    final (_, sink, repo, settings) = setup();
    await repo.upsertEvent(event('e1', DateTime(2026, 10, 22, 15)));
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.replaced.last, hasLength(1));

    await settings.setRemindersPhone(false);
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.replaced.last, isEmpty);
  });

  testWidgets('pede a permissão uma vez ao iniciar com a chave ligada', (tester) async {
    final (_, sink, _, _) = setup();
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.permissionRequests, [false]);
  });

  testWidgets('não pede a permissão com a chave desligada; ao ligar, pede de novo (force)', (tester) async {
    final (_, sink, _, settings) = setup(initial: const UserSettings(remindersPhone: false));
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.permissionRequests, isEmpty);

    await settings.setRemindersPhone(true);
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.permissionRequests, [true]);
  });

  testWidgets('falha do sink não derruba o app', (tester) async {
    final (_, sink, repo, _) = setup(fail: true);
    await repo.upsertEvent(event('e1', DateTime(2026, 10, 22, 15)));
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.replaced, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ao voltar para o app reagenda (a janela de 3 dias andou)', (tester) async {
    final (_, sink, repo, _) = setup();
    await repo.upsertEvent(event('e1', DateTime(2026, 10, 22, 15)));
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    final before = sink.replaced.length;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(reminderSyncDebounce + const Duration(milliseconds: 100));
    expect(sink.replaced.length, before + 1);
  });
}
