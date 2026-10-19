import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/fitness_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/features/fitness/fitness_providers.dart';
import 'package:organizacional/features/shopping/shopping_providers.dart';

import '../helpers.dart';

void main() {
  testWidgets('Hoje mostra aulas do dia, atrasadas e tarefas de hoje', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Cálculo I',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9, 40),
    ));
    await repo.upsertEvent(CalendarEvent(
      id: 'e2',
      title: 'Aula de amanhã',
      startsAt: DateTime(2026, 9, 29, 8),
      endsAt: DateTime(2026, 9, 29, 9),
    ));
    await repo.upsertTask(TaskItem(id: 't1', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59)));
    await repo.upsertTask(TaskItem(id: 't2', title: 'Resumo atrasado', dueAt: DateTime(2026, 9, 26, 23, 59)));
    await repo.upsertTask(TaskItem(id: 't3', title: 'Prova semana que vem', dueAt: DateTime(2026, 10, 5, 23, 59)));

    // 08:30: a aula está em andamento.
    await pumpApp(tester, repo, now: DateTime(2026, 9, 28, 8, 30));

    expect(find.text('segunda-feira, 28 de setembro'), findsOneWidget);
    expect(find.text('Cálculo I'), findsOneWidget);
    expect(find.text('08:00–09:40'), findsOneWidget);
    expect(find.text('Aula de amanhã'), findsNothing);
    expect(find.text('Resumo atrasado'), findsOneWidget);
    expect(find.text('Lista 3'), findsOneWidget);
    expect(find.text('Prova semana que vem'), findsNothing);
  });

  testWidgets('Hoje vazio mostra dicas', (tester) async {
    await pumpApp(tester, MemoryRepository());
    expect(find.text('Dia livre'), findsOneWidget);
  });

  testWidgets('a data em Hoje vira sozinha na meia-noite, sem precisar de outro evento',
      (tester) async {
    var current = DateTime(2026, 9, 28, 23, 59, 58);
    final repo = MemoryRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => current),
        newsRepositoryProvider.overrideWithValue(MemoryNewsRepository()),
        alexaRepositoryProvider.overrideWithValue(MemoryAlexaRepository()),
        fitnessRepositoryProvider.overrideWithValue(MemoryFitnessRepository()),
        shoppingRepositoryProvider.overrideWithValue(MemoryShoppingRepository()),
      ],
      child: OrganizacionalApp(
        router: buildRouter(initialLocation: '/', isSignedIn: () => true),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('segunda-feira, 28 de setembro'), findsOneWidget);

    current = DateTime(2026, 9, 29, 0, 0, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('terça-feira, 29 de setembro'), findsOneWidget);
  });
}
