import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';

import '../helpers.dart';

void main() {
  testWidgets('mostra o evento no dia certo e navega entre semanas', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Física',
      startsAt: DateTime(2026, 9, 30, 10),
      endsAt: DateTime(2026, 9, 30, 11, 40),
    ));
    await pumpApp(tester, repo, location: '/agenda');
    expect(find.text('quarta-feira, 30/09'), findsOneWidget);
    expect(find.text('Física'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next-week')));
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsNothing);
    expect(find.text('segunda-feira, 05/10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prev-week')));
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsOneWidget);
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

  testWidgets('excluir evento pede confirmação antes de apagar', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Física',
      startsAt: DateTime(2026, 9, 30, 10),
      endsAt: DateTime(2026, 9, 30, 11, 40),
    ));
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const ValueKey('delete-event-e1')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir “Física”?'), findsOneWidget);

    // Cancelar não apaga.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await repo.watchEvents(from: DateTime(2026, 9, 1)).first, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('delete-event-e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(await repo.watchEvents(from: DateTime(2026, 9, 1)).first, isEmpty);
  });
}
