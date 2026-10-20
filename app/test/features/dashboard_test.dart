import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/fitness_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/news.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/domain/workout.dart';
import 'package:organizacional/features/email/email_card.dart';
import 'package:organizacional/features/notes/note_screen.dart';
import 'package:organizacional/location/location_service.dart';
import 'package:organizacional/ui/org_widgets.dart';

import '../helpers.dart';

const _phone = Size(360, 800);
final _now = DateTime(2026, 9, 28, 10); // segunda-feira

CalendarEvent _ev(String id, String title, DateTime start,
        {Duration length = const Duration(hours: 1), String? location, bool allDay = false}) =>
    CalendarEvent(
      id: id,
      title: title,
      startsAt: start,
      endsAt: start.add(length),
      location: location,
      allDay: allDay,
    );

String _path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first))
    .routeInformationProvider
    .value
    .uri
    .path;

Finder _in(String key, Finder f) => find.descendant(of: find.byKey(Key(key)), matching: f);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

const _home = UserSettings(homeLat: -19.9320, homeLon: -43.9380);

MemoryLocationRepository _locationAt(double metersNorth) => MemoryLocationRepository(
      initial: LocationReport(
        fix: GeoFix(lat: -19.9320 + metersNorth / 111194.9, lon: -43.9380, accuracyM: 5),
        reportedAt: _now,
      ),
    );

void main() {
  group('Para hoje', () {
    testWidgets('mostra horário e local, destaca o que está em andamento e esmaece o que acabou', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('ja', 'Cedo', DateTime(2026, 9, 28, 7)));
      await repo.upsertEvent(_ev('a', 'Cálculo I', DateTime(2026, 9, 28, 9, 30)));
      await repo.upsertEvent(_ev('b', 'Física', DateTime(2026, 9, 28, 14), location: 'Lab 2'));
      await repo.upsertEvent(_ev('amanha', 'Aula de amanhã', DateTime(2026, 9, 29, 8)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(_in('today-card', find.text('Para hoje')), findsOneWidget);
      expect(_in('today-card', find.text('09:30–10:30')), findsOneWidget);
      expect(_in('today-card', find.text('14:00–15:00 · Lab 2')), findsOneWidget);
      expect(_in('today-card', find.text('agora')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-done-ja')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-done-a')), findsNothing);
      expect(find.byKey(const ValueKey('today-done-b')), findsNothing);
      expect(find.text('Aula de amanhã'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('today-event-b')));
      expect(_path(tester), '/agenda');
    });

    testWidgets('evento de dia inteiro vem primeiro', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('a', 'Cálculo I', DateTime(2026, 9, 28, 8)));
      await repo.upsertEvent(_ev('d', 'Feriado', DateTime(2026, 9, 28), allDay: true, length: const Duration(days: 1)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(tester.getTopLeft(find.text('Feriado')).dy, lessThan(tester.getTopLeft(find.text('Cálculo I')).dy));
    });

    testWidgets('prova ganha o selo "Prova"; aula comum não', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('p', 'Prova de Redes', DateTime(2026, 9, 28, 14), location: 'Sala B-12'));
      await repo.upsertEvent(_ev('a', 'Aula comum', DateTime(2026, 9, 28, 16)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(_in('today-event-p', find.text('Prova')), findsOneWidget);
      expect(_in('today-event-a', find.text('Prova')), findsNothing);
    });

    testWidgets('fica de fora: academia, etiqueta secundária e série que se repete todo dia', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTag(const EventTag(id: 'sec', name: 'Lembrete', color: '#999999', role: EventTagRole.secondary));
      await repo.upsertEvent(_ev('g', 'Academia', DateTime(2026, 9, 28, 6)));
      await repo.upsertEvent(_ev('s', 'Passear com o cachorro', DateTime(2026, 9, 28, 7)).copyWith(tagId: 'sec'));
      for (var i = 0; i < 7; i++) {
        await repo.upsertEvent(_ev('r$i', 'Tomar remédio', DateTime(2026, 9, 28 + i, 9)).copyWith(seriesId: 'rem'));
      }
      await repo.upsertEvent(_ev('a', 'Cálculo I', DateTime(2026, 9, 28, 8)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.text('Cálculo I'), findsOneWidget);
      expect(_in('today-card', find.text('Academia')), findsNothing);
      expect(find.text('Passear com o cachorro'), findsNothing);
      expect(find.text('Tomar remédio'), findsNothing);
    });

    testWidgets('mostra atrasadas e de hoje com prioridade; amanhã, sem data e concluída ficam fora', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(id: 'o', title: 'Resumo', dueAt: DateTime(2026, 9, 26, 23, 59)));
      await repo.upsertTask(TaskItem(
          id: 'h', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59), priority: TaskPriority.alta));
      await repo.upsertTask(TaskItem(id: 'x', title: 'Semana que vem', dueAt: DateTime(2026, 9, 29, 12)));
      await repo.upsertTask(const TaskItem(id: 'f', title: 'Sem data'));
      await repo.upsertTask(TaskItem(
          id: 'c', title: 'Já feita', dueAt: DateTime(2026, 9, 28, 9), status: TaskStatus.done));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(_in('today-card', find.text('Resumo')), findsOneWidget);
      expect(find.text('atrasada · 26 set.'), findsOneWidget);
      expect(_in('today-card', find.text('Lista 3')), findsOneWidget);
      expect(find.text('hoje'), findsOneWidget);
      expect(_in('today-card', find.text('alta')), findsOneWidget);
      for (final t in ['Semana que vem', 'Sem data', 'Já feita']) {
        expect(find.text(t), findsNothing, reason: t);
      }
    });

    testWidgets('tarefa de série: só a próxima pendente aparece; concluí-la mostra a seguinte', (tester) async {
      final repo = MemoryRepository();
      for (var i = 0; i < 3; i++) {
        await repo.upsertTask(TaskItem(
            id: 'o$i', title: 'Lab de S01', dueAt: DateTime(2026, 9, 24 + 2 * i, 23, 59), seriesId: 'lab'));
      } // 24/09 e 26/09 atrasadas, 28/09 hoje
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.byKey(const ValueKey('today-task-o0')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-task-o1')), findsNothing);
      expect(find.byKey(const ValueKey('today-task-o2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('task-check-o0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-task-o0')), findsNothing);
      expect(find.byKey(const ValueKey('today-task-o1')), findsOneWidget);
    });

    testWidgets('mostra no máximo 5 tarefas e "+N tarefas" leva a Tarefas', (tester) async {
      final repo = MemoryRepository();
      for (var i = 0; i < 7; i++) {
        await repo.upsertTask(TaskItem(id: 'o$i', title: 'Atrasada $i', dueAt: DateTime(2026, 9, 20 + i)));
      }
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(_in('today-card', find.byType(Checkbox)), findsNWidgets(5));
      expect(find.text('+ 2 tarefas'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('today-more-tasks')));
      expect(_path(tester), '/tarefas');
    });

    testWidgets('o checkbox conclui e "Desfazer" restaura', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(
          id: 't1', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59), status: TaskStatus.doing));
      await pumpApp(tester, repo, now: _now);
      await tester.tap(find.byKey(const ValueKey('task-check-t1')));
      await tester.pumpAndSettle();
      var saved = (await repo.watchTasks().first).single;
      expect(saved.isDone, isTrue);
      expect(saved.completedAt, isNotNull);
      expect(find.text('Tarefa concluída'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-check-t1')), findsNothing);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      saved = (await repo.watchTasks().first).single;
      expect(saved.status, TaskStatus.doing);
      expect(saved.completedAt, isNull);
      expect(find.byKey(const ValueKey('task-check-t1')), findsOneWidget);
    });

    testWidgets('falha ao concluir avisa e mantém a tarefa', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(id: 't1', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59)));
      await pumpApp(tester, repo, now: _now);
      repo.failWrites = true;
      await tester.tap(find.byKey(const ValueKey('task-check-t1')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível atualizar a tarefa.'), findsOneWidget);
      expect((await repo.watchTasks().first).single.isDone, isFalse);
    });

    testWidgets('tocar numa tarefa abre Tarefas', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(id: 't1', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      await _tap(tester, find.text('Lista 3'));
      expect(_path(tester), '/tarefas');
    });

    testWidgets('sem nada para hoje: "Dia livre"', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(_in('today-card', find.text('Dia livre')), findsOneWidget);
    });
  });

  group('removidos da Início', () {
    testWidgets('sem Notícias, "Agora e a seguir", cartão de tarefas e "Próxima prova"', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('p', 'Prova de Redes', DateTime(2026, 9, 29, 10)));
      await repo.upsertTask(TaskItem(id: 't', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59)));
      await pumpApp(tester, repo, now: _now, size: _phone, news: NewsRepositoryFixture().build(count: 3));
      await tester.drag(find.byKey(const Key('dashboard-scroll')), const Offset(0, -3000));
      await tester.pumpAndSettle();
      for (final k in ['card-news', 'open-news', 'card-now-next', 'card-tasks', 'card-exam', 'quick-task-field']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.text('Manchete 0'), findsNothing);
      expect(find.text('Agora e a seguir'), findsNothing);
      expect(find.text('Próxima prova'), findsNothing);
      expect(find.byKey(const Key('open-home')), findsOneWidget);
    });
  });

  group('Academia e Compras', () {
    testWidgets('a Início mostra os dois cartões; Abrir leva às telas', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(find.byKey(const Key('gym-card')), findsOneWidget);
      expect(find.byKey(const Key('gym-create')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('shopping-card')));
      expect(find.byKey(const Key('shopping-card')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('shopping-open')));
      expect(_path(tester), '/compras');
    });

    testWidgets('tocar no cartão da Academia abre /academia', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      await _tap(tester, find.descendant(of: find.byKey(const Key('gym-card')), matching: find.text('Academia')));
      expect(_path(tester), '/academia');
    });

    testWidgets('treino de hoje aparece na Academia e fora do Para hoje', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(const Workout(id: 'w1', name: 'Treino B', exercises: [
        WorkoutExercise(id: 'e1', workoutId: 'w1', name: 'Supino', sets: 3, reps: '8–12'),
      ]));
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('g', 'Treino', DateTime(2026, 9, 28, 18)));
      await pumpApp(tester, repo, now: _now, size: _phone, fitnessRepo: fit);
      expect(_in('gym-card', find.text('Hoje: Treino B')), findsOneWidget);
      expect(_in('today-card', find.text('Treino')), findsNothing);
    });
  });

  group('faixa de status', () {
    testWidgets('sem casa definida não há chip de presença', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(find.byKey(const Key('status-presence')), findsNothing);
    });

    testWidgets('em casa', (tester) async {
      await pumpApp(tester, MemoryRepository(),
          now: _now,
          size: _phone,
          settings: MemorySettingsRepository(initial: _home),
          locationRepo: _locationAt(5));
      expect(_in('status-presence', find.text('Em casa')), findsOneWidget);
    });

    testWidgets('fora, com a distância', (tester) async {
      await pumpApp(tester, MemoryRepository(),
          now: _now,
          size: _phone,
          settings: MemorySettingsRepository(initial: _home),
          locationRepo: _locationAt(5000));
      expect(_in('status-presence', find.text('Fora (a 5,0 km)')), findsOneWidget);
    });

    testWidgets('casa definida mas sem localização recente', (tester) async {
      await pumpApp(tester, MemoryRepository(),
          now: _now, size: _phone, settings: MemorySettingsRepository(initial: _home));
      expect(_in('status-presence', find.text('Local indisponível')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('status-presence')));
      expect(_path(tester), '/ajustes');
    });

    testWidgets('login da Alexa expirado leva a Casa; sem despertar ativo some', (tester) async {
      const plan = WakePlan(
          id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'ECHO');
      final status = BridgeStatus(state: BridgeState.authRequired, lastSeen: _now);
      await pumpApp(tester, MemoryRepository(),
          now: _now, size: _phone, alexa: MemoryAlexaRepository(status: status, plans: const [plan]));
      expect(_in('status-bridge', find.text('Login da Alexa expirou')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('status-bridge')));
      expect(_path(tester), '/casa');
    });

    testWidgets('ponte offline', (tester) async {
      const plan = WakePlan(
          id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'ECHO');
      final status = BridgeStatus(state: BridgeState.ok, lastSeen: _now.subtract(const Duration(minutes: 20)));
      await pumpApp(tester, MemoryRepository(),
          now: _now, size: _phone, alexa: MemoryAlexaRepository(status: status, plans: const [plan]));
      expect(find.text('Alexa offline'), findsOneWidget);
    });

    testWidgets('ponte com problema mas sem despertar ativo: nada na faixa', (tester) async {
      final status = BridgeStatus(state: BridgeState.authRequired, lastSeen: _now);
      await pumpApp(tester, MemoryRepository(),
          now: _now, size: _phone, alexa: MemoryAlexaRepository(status: status));
      expect(find.byKey(const Key('status-bridge')), findsNothing);
    });
  });

  group('E-mail', () {
    testWidgets('o stub convida a conectar o Gmail e abre Ajustes', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(find.byType(EmailCard), findsOneWidget);
      expect(find.text('Conecte seu Gmail em Ajustes para ver as notificações aqui'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('email-open-settings')));
      expect(_path(tester), '/ajustes');
      expect(find.widgetWithText(PageHeader, 'Ajustes'), findsOneWidget);
    });
  });

  group('ações rápidas', () {
    testWidgets('Tarefa abre o editor em modo de criação', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      await tester.tap(find.byKey(const Key('quick-new-task')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-title')), findsOneWidget);
      expect(find.text('Nova tarefa'), findsOneWidget);
    });

    testWidgets('Evento abre o diálogo e salva na hora seguinte', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, now: _now, size: _phone);
      await tester.tap(find.byKey(const Key('quick-new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), 'Reunião');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      final saved = (await repo.watchEvents(from: DateTime(2026)).first).single;
      expect(saved.title, 'Reunião');
      expect(saved.startsAt, DateTime(2026, 9, 28, 11));
    });

    testWidgets('Nota cria uma nota e abre', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, now: _now, size: _phone);
      await tester.tap(find.byKey(const Key('quick-new-note')));
      await tester.pumpAndSettle();
      final notes = await repo.watchNotes().first;
      expect(notes.single.title, 'Sem título');
      expect(find.byType(NoteScreen), findsOneWidget);
    });

    testWidgets('os botões têm rótulo semântico e alvo de pelo menos 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      for (final (key, label) in [
        ('quick-new-task', 'Nova tarefa'),
        ('quick-new-event', 'Novo evento'),
        ('quick-new-note', 'Nova nota'),
        ('quick-new-notebook', 'Novo caderno'),
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(48), reason: key);
      }
      handle.dispose();
    });
  });

  group('layout', () {
    testWidgets('celular: uma coluna na ordem Para hoje, Academia, Compras, Despertares, E-mail', (tester) async {
      const plan = WakePlan(
          id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'ECHO');
      await pumpApp(tester, MemoryRepository(),
          now: _now, size: _phone, alexa: MemoryAlexaRepository(plans: const [plan]));
      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      final order = ['today-card', 'gym-card', 'shopping-card', 'wake-card', 'email-card'];
      for (var i = 1; i < order.length; i++) {
        expect(top(order[i]), greaterThan(top(order[i - 1])), reason: '${order[i]} depois de ${order[i - 1]}');
      }
    });

    testWidgets('computador: Para hoje à esquerda; os demais à direita', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now);
      final left = tester.getTopLeft(find.byKey(const Key('today-card'))).dx;
      for (final k in ['gym-card', 'shopping-card', 'email-card']) {
        expect(tester.getTopLeft(find.byKey(Key(k))).dx, greaterThan(left), reason: k);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('sem estouro de layout', () {
    Future<MemoryRepository> richData() async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('a', 'Cálculo Diferencial e Integral para Engenharia Avançada II',
          DateTime(2026, 9, 28, 9, 30), location: 'Prédio de Engenharia, Bloco C, sala 301-B'));
      await repo.upsertEvent(_ev('b', 'Laboratório de Física Experimental', DateTime(2026, 9, 28, 14)));
      await repo.upsertEvent(_ev('c', 'Seminário de Redes de Computadores', DateTime(2026, 9, 28, 16)));
      await repo.upsertEvent(_ev('d', 'Dia inteiro com um nome muito longo mesmo', DateTime(2026, 9, 28),
          allDay: true, length: const Duration(days: 1)));
      await repo.upsertEvent(_ev('p', 'Prova de Sistemas Operacionais e Arquitetura de Computadores',
          DateTime(2026, 9, 28, 18), location: 'Auditório Principal do Campus Central, andar 2'));
      for (var i = 0; i < 7; i++) {
        await repo.upsertTask(TaskItem(
          id: 't$i',
          title: 'Entregar o relatório final do projeto integrador número $i com anexos',
          dueAt: DateTime(2026, 9, 20 + i),
          priority: i.isEven ? TaskPriority.alta : TaskPriority.media,
        ));
      }
      return repo;
    }

    Future<MemoryFitnessRepository> gym() async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(const Workout(
        id: 'w1',
        name: 'Treino B — peito, ombros e tríceps com nome bem comprido',
        exercises: [WorkoutExercise(id: 'e1', workoutId: 'w1', name: 'Supino reto com barra')],
      ));
      return fit;
    }

    Future<MemoryShoppingRepository> market() async {
      final shop = MemoryShoppingRepository();
      final list = await shop.ensureDefaultList();
      for (final n in ['Leite integral de caixinha com tampa', 'Pão', 'Queijo minas frescal', 'Ovos']) {
        await shop.addItem(listId: list.id, name: n);
      }
      return shop;
    }

    const plan = WakePlan(id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'ECHO');

    for (final scale in [1.0, 1.3]) {
      testWidgets('360 dp com texto em ${scale}x', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(
          tester,
          await richData(),
          now: _now,
          size: _phone,
          settings: MemorySettingsRepository(initial: _home),
          locationRepo: _locationAt(173000),
          alexa: MemoryAlexaRepository(
            status: BridgeStatus(state: BridgeState.authRequired, lastSeen: _now),
            plans: const [plan],
          ),
          fitnessRepo: await gym(),
          shoppingRepo: await market(),
        );
        expect(tester.takeException(), isNull);
        // Rola até o fim: tudo precisa caber na largura.
        await tester.drag(find.byKey(const Key('dashboard-scroll')), const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll = tester.getSize(find.byKey(const Key('dashboard-scroll')));
        expect(scroll.width, 360);
      });
    }

    testWidgets('tela larga com dados cheios', (tester) async {
      await pumpApp(
        tester,
        await richData(),
        now: _now,
        alexa: MemoryAlexaRepository(plans: const [plan]),
        fitnessRepo: await gym(),
        shoppingRepo: await market(),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byKey(const Key('dashboard-scroll')), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// Feed de teste com N manchetes de uma fonte assinada e uma "nova" numa fonte
/// ainda não assinada (aparece só depois de assinar).
class NewsRepositoryFixture {
  MemoryNewsRepository build({required int count}) => MemoryNewsRepository(
        sources: const [
          NewsSource(id: 'a', name: 'A', section: 's', feedUrl: 'https://a', subscribed: true),
          NewsSource(id: 'b', name: 'B', section: 's', feedUrl: 'https://b'),
        ],
        items: [
          for (var i = 0; i < count; i++)
            NewsItem(
              id: 'a$i',
              sourceId: 'a',
              sourceName: 'A',
              title: 'Manchete $i',
              url: 'https://a/$i',
              publishedAt: DateTime(2026, 9, 28, 9).subtract(Duration(minutes: i)),
            ),
          NewsItem(
            id: 'b1',
            sourceId: 'b',
            sourceName: 'B',
            title: 'Manchete nova',
            url: 'https://b/1',
            publishedAt: DateTime(2026, 9, 28, 9, 30),
          ),
        ],
      );
}
