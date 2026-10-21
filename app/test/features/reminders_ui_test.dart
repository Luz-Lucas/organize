import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/features/agenda/event_dialog.dart';
import 'package:organizacional/features/common/reminder_chips.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../helpers.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
      home: Scaffold(body: child),
    );

bool _selected(WidgetTester tester, int minutes) =>
    tester.widget<FilterChip>(find.byKey(Key('reminder-chip-$minutes'))).selected;

void main() {
  group('ReminderChips', () {
    testWidgets('mostra os 4 chips e marca os selecionados', (tester) async {
      await tester.pumpWidget(_host(ReminderChips(selected: const [60], onChanged: (_) {})));
      expect(find.text('Lembrar'), findsOneWidget);
      for (final label in ['1 dia', '1 hora', '30 min', '15 min']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect([for (final m in [1440, 60, 30, 15]) _selected(tester, m)], [false, true, false, false]);
    });

    testWidgets('tocar marca e desmarca (várias ao mesmo tempo), devolvendo a lista ordenada', (tester) async {
      var value = <int>[60];
      late StateSetter set;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
        set = setState;
        return ReminderChips(selected: value, onChanged: (v) => set(() => value = v));
      })));
      await tester.tap(find.byKey(const Key('reminder-chip-15')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminder-chip-1440')));
      await tester.pump();
      expect(value, [1440, 60, 15]);
      await tester.tap(find.byKey(const Key('reminder-chip-60')));
      await tester.pump();
      expect(value, [1440, 15]);
      await tester.tap(find.byKey(const Key('reminder-chip-1440')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminder-chip-15')));
      await tester.pump();
      expect(value, isEmpty); // pode ficar sem nenhum lembrete
    });

    testWidgets('"Não lembrar" fica marcado sem lembretes e, ao tocar, limpa os outros', (tester) async {
      var value = <int>[1440, 30];
      late StateSetter set;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
        set = setState;
        return ReminderChips(selected: value, onChanged: (v) => set(() => value = v));
      })));
      bool none() => tester.widget<FilterChip>(find.byKey(const Key('reminder-chip-none'))).selected;
      expect(find.text('Não lembrar'), findsOneWidget);
      expect(none(), isFalse);
      await tester.tap(find.byKey(const Key('reminder-chip-none')));
      await tester.pump();
      expect(value, isEmpty);
      expect(none(), isTrue);
      expect([for (final m in [1440, 60, 30, 15]) _selected(tester, m)], everyElement(isFalse));
      // Escolher um tempo desmarca "Não lembrar".
      await tester.tap(find.byKey(const Key('reminder-chip-15')));
      await tester.pump();
      expect(value, [15]);
      expect(none(), isFalse);
    });

    testWidgets('desativado não reage; hint aparece quando informado', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(ReminderChips(
        selected: const [],
        onChanged: (_) => calls++,
        enabled: false,
        hint: 'Dica de teste',
      )));
      await tester.tap(find.byKey(const Key('reminder-chip-30')));
      await tester.pump();
      expect(calls, 0);
      expect(find.text('Dica de teste'), findsOneWidget);
    });
  });

  group('editor de tarefa', () {
    testWidgets('tarefa existente abre com o padrão [60], editar e salvar grava os lembretes', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect(_selected(tester, 60), isTrue);
      expect(_selected(tester, 15), isFalse);
      await tester.ensureVisible(find.byKey(const Key('reminder-chip-15')));
      await tester.tap(find.byKey(const Key('reminder-chip-15')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminder-chip-1440')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect((await repo.watchTasks().first).single.reminders, [1440, 60, 15]);
    });

    testWidgets('respeita os lembretes já gravados na tarefa', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório', reminders: [30]));
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect([for (final m in [1440, 60, 30, 15]) _selected(tester, m)], [false, false, true, false]);
    });

    testWidgets('dica de 10h só com prazo sem horário (23:59)', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(id: 'a', title: 'Só data', dueAt: DateTime(2026, 10, 25, 23, 59)));
      await repo.upsertTask(TaskItem(id: 'b', title: 'Com hora', dueAt: DateTime(2026, 10, 25, 18)));
      await pumpApp(tester, repo, location: '/tarefas');
      const hint = 'Tarefas sem horário avisam às 10h se forem de prioridade alta';
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-card-b')));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
    });

    testWidgets('tarefa nova vem com [60] pré-marcado', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const Key('quick-more-todo')));
      await tester.pumpAndSettle();
      expect(_selected(tester, 60), isTrue);
      await tester.enterText(find.byKey(const Key('task-title')), 'Nova');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect((await repo.watchTasks().first).single.reminders, [60]);
    });
  });

  group('editor de evento', () {
    Future<void> open(WidgetTester tester, {CalendarEvent? existing}) async {
      await initializeDateFormatting('pt_BR');
      await tester.pumpWidget(MaterialApp(
        theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<CalendarEvent>(
              context: context,
              builder: (_) => EventDialog(
                initialStart: existing?.startsAt ?? DateTime(2026, 10, 21, 15),
                initialEnd: existing?.endsAt ?? DateTime(2026, 10, 21, 16),
                spaces: const [],
                existing: existing,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('evento novo vem com [30] e salva a escolha', (tester) async {
      CalendarEvent? saved;
      await initializeDateFormatting('pt_BR');
      await tester.pumpWidget(MaterialApp(
        theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showDialog<CalendarEvent>(
              context: context,
              builder: (_) => EventDialog(
                  initialStart: DateTime(2026, 10, 21, 15), initialEnd: DateTime(2026, 10, 21, 16), spaces: const []),
            ),
            child: const Text('abrir'),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect([for (final m in [1440, 60, 30, 15]) _selected(tester, m)], [false, false, true, false]);
      await tester.enterText(find.byKey(const Key('event-title')), 'Reunião');
      await tester.ensureVisible(find.byKey(const Key('reminder-chip-60')));
      await tester.tap(find.byKey(const Key('reminder-chip-60')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminder-chip-30')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(saved!.reminders, [60]);
    });

    testWidgets('evento existente abre com os próprios lembretes', (tester) async {
      final existing = CalendarEvent(
        id: 'e',
        title: 'Aula',
        startsAt: DateTime(2026, 10, 22, 8),
        endsAt: DateTime(2026, 10, 22, 9),
        reminders: const [1440, 15],
      );
      await open(tester, existing: existing);
      expect([for (final m in [1440, 60, 30, 15]) _selected(tester, m)], [true, false, false, true]);
    });
  });

  group('cartão Lembretes em Ajustes', () {
    const echos = [
      AlexaDevice(id: 'E1', name: 'Echo da sala', kind: 'echo'),
      AlexaDevice(id: 'E2', name: 'Echo do quarto', kind: 'echo'),
      AlexaDevice(id: 'L1', name: 'Lâmpada', kind: 'light'),
    ];

    Future<MemorySettingsRepository> pumpCard(WidgetTester tester,
        {UserSettings initial = const UserSettings(), List<AlexaDevice> devices = echos}) async {
      final settings = MemorySettingsRepository(initial: initial);
      await pumpApp(tester, MemoryRepository(),
          location: '/ajustes',
          settings: settings,
          alexa: MemoryAlexaRepository(devices: devices),
          size: const Size(600, 3000));
      return settings;
    }

    testWidgets('mostra as chaves nos padrões e o não perturbe 23:00 → 10:00', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('reminders-card')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('reminders-phone-switch'))).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('reminders-alexa-switch'))).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('reminders-dnd-switch'))).value, isTrue);
      expect(find.descendant(of: find.byKey(const Key('reminders-dnd-start')), matching: find.text('23:00')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('reminders-dnd-end')), matching: find.text('10:00')),
          findsOneWidget);
    });

    testWidgets('as chaves gravam nos ajustes', (tester) async {
      final settings = await pumpCard(tester);
      await tester.tap(find.byKey(const Key('reminders-phone-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminders-dnd-switch')));
      await tester.pumpAndSettle();
      final s = await settings.watchSettings().first;
      expect([s.remindersPhone, s.dndEnabled, s.remindersAlexa], [false, false, true]);
      expect(find.byKey(const Key('reminders-dnd-start')), findsNothing); // sem não perturbe, sem horários
    });

    testWidgets('escolher o Echo lista só Echos e grava o id', (tester) async {
      final settings = await pumpCard(tester);
      await tester.ensureVisible(find.byKey(const Key('reminders-echo')));
      await tester.tap(find.byKey(const Key('reminders-echo')));
      await tester.pumpAndSettle();
      expect(find.text('Echo da sala'), findsWidgets);
      expect(find.text('Lâmpada'), findsNothing);
      await tester.tap(find.text('Echo do quarto').last);
      await tester.pumpAndSettle();
      expect((await settings.watchSettings().first).reminderEcho, 'E2');
    });

    testWidgets('Alexa desligada esconde a escolha do Echo; sem Echo avisa', (tester) async {
      await pumpCard(tester, initial: const UserSettings(remindersAlexa: false));
      expect(find.byKey(const Key('reminders-echo')), findsNothing);
      await pumpCard(tester, devices: const []);
      expect(find.byKey(const Key('reminders-no-echo')), findsOneWidget);
    });

    testWidgets('mostra o Echo já escolhido', (tester) async {
      await pumpCard(tester, initial: const UserSettings(reminderEcho: 'E2'));
      expect(find.text('Echo do quarto'), findsOneWidget);
    });

    testWidgets('trocar o início do não perturbe grava os minutos', (tester) async {
      final settings = await pumpCard(tester);
      await tester.ensureVisible(find.byKey(const Key('reminders-dnd-start')));
      await tester.tap(find.byKey(const Key('reminders-dnd-start')));
      await tester.pumpAndSettle();
      // O seletor de hora abre; confirma com o valor inicial (23:00).
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await settings.watchSettings().first).dndStart, 23 * 60);
    });

    testWidgets('falha ao salvar mostra aviso', (tester) async {
      final settings = await pumpCard(tester);
      settings.failWrites = true;
      await tester.tap(find.byKey(const Key('reminders-phone-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar os lembretes.'), findsOneWidget);
    });
  });
}
