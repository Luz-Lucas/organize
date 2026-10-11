import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/space.dart';

import '../helpers.dart';

final _from = DateTime(2026, 9, 1);

CalendarEvent _fisica() => CalendarEvent(
      id: 'e1',
      title: 'Física',
      startsAt: DateTime(2026, 9, 30, 10),
      endsAt: DateTime(2026, 9, 30, 11, 40),
    );

void main() {
  testWidgets('abre na semana atual e navega entre semanas', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(_fisica());
    await pumpApp(tester, repo, location: '/agenda');
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('view-week'))).selected, isTrue);
    expect(find.text('27 set – 3 out 2026'), findsOneWidget);
    expect(find.text('Física'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next-week')));
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsNothing);
    expect(find.text('4 – 10 out 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prev-week')));
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsOneWidget);
  });

  testWidgets('visão de mês mostra pílulas e tocar no dia abre a semana', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(_fisica());
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const Key('view-month')));
    await tester.pumpAndSettle();
    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(find.text('Física'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('month-day-2026-09-30')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('view-week'))).selected, isTrue);
    expect(find.text('27 set – 3 out 2026'), findsOneWidget);
  });

  testWidgets('mês mostra no máximo 3 pílulas e "+N"', (tester) async {
    final repo = MemoryRepository();
    for (var i = 0; i < 5; i++) {
      await repo.upsertEvent(CalendarEvent(
        id: 'm$i',
        title: 'Ev$i',
        startsAt: DateTime(2026, 9, 29, 8 + i),
        endsAt: DateTime(2026, 9, 29, 9 + i),
      ));
    }
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const Key('view-month')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ev'), findsNWidgets(3));
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('novo evento pelo diálogo aparece na semana', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const Key('new-event')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Dê um título ao evento.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('event-title')), 'Monitoria');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Monitoria'), findsOneWidget);
    final saved = (await repo.watchEvents(from: DateTime(2026, 9, 28)).first).single;
    expect(saved.startsAt, DateTime(2026, 9, 28, 8));
    expect(saved.endsAt, DateTime(2026, 9, 28, 9, 40));
  });

  testWidgets('falha ao salvar mantém o diálogo aberto com o texto', (tester) async {
    final repo = MemoryRepository()..failWrites = true;
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const Key('new-event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('event-title')), 'Monitoria');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível salvar o evento.'), findsOneWidget);
    expect(find.text('Monitoria'), findsOneWidget);
    repo.failWrites = false;
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(await repo.watchEvents(from: _from).first, hasLength(1));
  });

  testWidgets('tocar num horário vazio abre o diálogo com 1h a partir dele', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const ValueKey('slot-2026-09-29-14')));
    await tester.pumpAndSettle();
    expect(find.text('Novo evento'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('event-start-time')), matching: find.text('14:00')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('event-end-time')), matching: find.text('15:00')),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('event-title')), 'Estudo');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final saved = (await repo.watchEvents(from: _from).first).single;
    expect(saved.startsAt, DateTime(2026, 9, 29, 14));
    expect(saved.endsAt, DateTime(2026, 9, 29, 15));
  });

  testWidgets('arrastar num horário vazio cria intervalo arredondado a 15 min', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/agenda');
    final slot = find.byKey(const ValueKey('slot-2026-09-29-10'));
    final top = tester.getTopLeft(slot);
    final gesture = await tester.startGesture(top + const Offset(10, 2));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Novo evento'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('event-start-time')), matching: find.text('10:00')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('event-end-time')), matching: find.text('12:00')),
        findsOneWidget);
  });

  testWidgets('tocar no evento edita o mesmo id', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(_fisica());
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    expect(find.text('Editar evento'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Física'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('event-title')), 'Física II');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final all = await repo.watchEvents(from: _from).first;
    expect(all.single.id, 'e1');
    expect(all.single.title, 'Física II');
    expect(all.single.startsAt, DateTime(2026, 9, 30, 10));
  });

  testWidgets('edição preserva o espaço quando não alterado', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Faculdade', kind: SpaceKind.materia));
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Física',
      startsAt: DateTime(2026, 9, 30, 10),
      endsAt: DateTime(2026, 9, 30, 11),
      spaceId: 's1',
      location: 'Sala 3',
    ));
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final e = (await repo.watchEvents(from: _from).first).single;
    expect(e.spaceId, 's1');
    expect(e.location, 'Sala 3');
  });

  testWidgets('excluir evento pede confirmação antes de apagar', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(_fisica());
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-event-e1')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir “Física”?'), findsOneWidget);

    // Cancelar não apaga.
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    expect(await repo.watchEvents(from: _from).first, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('delete-event-e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(await repo.watchEvents(from: _from).first, isEmpty);
    expect(find.text('Física'), findsNothing);
  });

  testWidgets('falha ao excluir mantém o evento e avisa', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(_fisica());
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    repo.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('delete-event-e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível excluir o evento.'), findsOneWidget);
    repo.failWrites = false;
    expect(await repo.watchEvents(from: _from).first, hasLength(1));
  });

  testWidgets('evento 23:30 → 00:15 aparece nos dois dias da semana', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'p',
      title: 'Plantão',
      startsAt: DateTime(2026, 9, 28, 23, 30),
      endsAt: DateTime(2026, 9, 29, 0, 15),
    ));
    await pumpApp(tester, repo, location: '/agenda');
    expect(find.byKey(const ValueKey('event-block-p-2026-09-28')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-block-p-2026-09-29')), findsOneWidget);
  });

  testWidgets('celular: mês compacto com pontos e lista do dia', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'f',
      title: 'Festa',
      startsAt: DateTime(2026, 9, 26, 22),
      endsAt: DateTime(2026, 9, 27, 2),
    ));
    await pumpApp(tester, repo, location: '/agenda', size: const Size(400, 800));
    expect(find.byKey(const Key('new-event')), findsOneWidget);
    expect(find.byKey(const Key('view-week')), findsNothing);
    expect(find.byKey(const ValueKey('dot-2026-09-26')), findsOneWidget);
    expect(find.byKey(const ValueKey('dot-2026-09-27')), findsOneWidget);
    expect(find.byKey(const ValueKey('dot-2026-09-28')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mini-day-2026-09-26')));
    await tester.pumpAndSettle();
    expect(find.text('Festa'), findsOneWidget);
    expect(find.textContaining('22:00 → dom 02:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mini-day-2026-09-27')));
    await tester.pumpAndSettle();
    expect(find.textContaining('sáb 22:00 → 02:00'), findsOneWidget);
  });
}
