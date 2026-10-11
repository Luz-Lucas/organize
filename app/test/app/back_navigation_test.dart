import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/features/agenda/agenda_screen.dart';
import 'package:organizacional/features/home/home_screen.dart';
import 'package:organizacional/features/home/wake_plan_screen.dart';
import 'package:organizacional/features/more/more_screen.dart';
import 'package:organizacional/features/news/news_screen.dart';
import 'package:organizacional/features/news/news_settings_screen.dart';
import 'package:organizacional/features/notes/note_screen.dart';
import 'package:organizacional/features/notes/notes_screen.dart';
import 'package:organizacional/features/settings/settings_screen.dart';
import 'package:organizacional/features/tasks/tasks_screen.dart';
import 'package:organizacional/features/today/today_screen.dart';
import 'package:organizacional/widgets/widget_links.dart';

import '../helpers.dart';

const _phone = Size(400, 800);
const _exitHint = 'Pressione voltar novamente para sair';

/// Simula o botão voltar do sistema (Android) e deixa a UI assentar.
Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> tapNav(WidgetTester tester, String path) async {
  await tester.tap(find.byKey(ValueKey('nav-$path')));
  await tester.pumpAndSettle();
}

void main() {
  group('voltar na casca', () {
    testWidgets('Agenda: voltar leva ao Início, sem sair', (tester) async {
      var exits = 0;
      await pumpApp(tester, MemoryRepository(),
          location: '/agenda', size: _phone, exitApp: () => exits++);
      expect(find.byType(AgendaScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.byType(AgendaScreen), findsNothing);
      expect(find.text(_exitHint), findsNothing);
      expect(exits, 0);
    });

    testWidgets('Início: 1º voltar avisa, não sai; 2º dentro de 2 s sai', (tester) async {
      var exits = 0;
      await pumpApp(tester, MemoryRepository(), size: _phone, exitApp: () => exits++);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_exitHint), findsOneWidget);
      expect(exits, 0);
      expect(find.byType(TodayScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exits, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('Início: após 2 s o aviso volta a ser exigido', (tester) async {
      var exits = 0;
      await pumpApp(tester, MemoryRepository(), size: _phone, exitApp: () => exits++);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle(); // passa os 2 s do aviso
      await tester.pump(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(exits, 0);
      expect(find.text(_exitHint), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('Tarefas -> Agenda -> voltar = Início, e o histórico não cresce',
        (tester) async {
      var exits = 0;
      await pumpApp(tester, MemoryRepository(), size: _phone, exitApp: () => exits++);
      await tapNav(tester, '/tarefas');
      await tapNav(tester, '/agenda');
      await tapNav(tester, '/notas');
      await tapNav(tester, '/tarefas');
      await tapNav(tester, '/agenda');
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
      // Nada de abas antigas na pilha: o próximo voltar é o aviso de saída.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text(_exitHint), findsOneWidget);
      expect(exits, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('barra lateral (desktop): Tarefas -> voltar = Início', (tester) async {
      await pumpApp(tester, MemoryRepository());
      await tapNav(tester, '/tarefas');
      expect(find.byType(TasksScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('Mais -> Ajustes: voltar leva ao Início', (tester) async {
      await pumpApp(tester, MemoryRepository(), size: _phone);
      await tapNav(tester, '/mais');
      expect(find.byType(MoreScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('more-/ajustes')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('Casa (por Mais): voltar leva ao Início', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/casa', size: _phone);
      expect(find.byType(HomeScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('link de widget abre direto na Tarefas; voltar vai ao Início', (tester) async {
      final route = routeForWidgetUri(Uri.parse('organizacional://tarefas'))!;
      await pumpApp(tester, MemoryRepository(), location: route, size: _phone);
      expect(find.byType(TasksScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('diálogo aberto fecha primeiro no voltar', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/agenda', size: _phone);
      final context = tester.element(find.byType(AgendaScreen));
      showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('Diálogo X')));
      await tester.pumpAndSettle();
      expect(find.text('Diálogo X'), findsOneWidget);
      await back(tester);
      expect(find.text('Diálogo X'), findsNothing);
      expect(find.byType(AgendaScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });
  });

  group('voltar em páginas internas', () {
    testWidgets('Notas -> abrir nota -> voltar = lista de notas (não o Início)', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertNote(const Note(id: 'n1', title: 'Redes'));
      await pumpApp(tester, repo, size: _phone);
      await tapNav(tester, '/notas');
      expect(find.byType(NotesScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tree-note-n1')));
      await tester.pumpAndSettle();
      expect(find.byType(NoteScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(NoteScreen), findsNothing);
      expect(find.byType(NotesScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('barra lateral: trocar de nota não empilha; voltar sai da nota', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertNote(const Note(id: 'n1', title: 'Redes'));
      await repo.upsertNote(const Note(id: 'n2', title: 'Cálculo'));
      await pumpApp(tester, repo);
      await tapNav(tester, '/notas');
      await tester.tap(find.byKey(const ValueKey('tree-note-n1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tree-note-n2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tree-note-n1')));
      await tester.pumpAndSettle();
      expect(find.byType(NoteScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(NoteScreen), findsNothing);
      expect(find.byType(NotesScreen), findsOneWidget);
    });

    testWidgets('Notícias -> Fontes e interesses -> voltar = Notícias', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/noticias', size: _phone);
      await tester.tap(find.byKey(const Key('news-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(NewsSettingsScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(NewsSettingsScreen), findsNothing);
      expect(find.byType(NewsScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('editor de despertar aberto em Casa: voltar = Casa', (tester) async {
      final alexa = MemoryAlexaRepository(plans: const [
        WakePlan(id: 'p1', label: 'Aula cedo', days: [1], hour: 7, minute: 0, echoDeviceId: 'E'),
      ]);
      await pumpApp(tester, MemoryRepository(),
          location: '/casa', alexa: alexa, size: const Size(1000, 1800));
      await tester.tap(find.byKey(const Key('new-wake')));
      await tester.pumpAndSettle();
      expect(find.byType(WakePlanScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(WakePlanScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('salvar o despertar volta para Casa sem deixar o editor na pilha',
        (tester) async {
      final alexa = MemoryAlexaRepository(
        plans: const [],
        devices: const [AlexaDevice(id: 'ECHO', name: 'Echo do quarto', kind: 'echo')],
      );
      await pumpApp(tester, MemoryRepository(),
          location: '/casa', alexa: alexa, size: const Size(1000, 1800));
      await tester.tap(find.byKey(const Key('new-wake')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('wake-label')), 'Academia');
      await tester.enterText(find.byKey(const Key('wake-spotify')), 'rock');
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect(find.byType(WakePlanScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });
  });
}
