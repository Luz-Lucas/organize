import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/news.dart';
import 'package:organizacional/domain/notice.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
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
  group('Agora e a seguir', () {
    testWidgets('mostra o evento em andamento e os próximos 2, com a sobra', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('a', 'Cálculo I', DateTime(2026, 9, 28, 9, 30)));
      await repo.upsertEvent(_ev('b', 'Física', DateTime(2026, 9, 28, 11)));
      await repo.upsertEvent(_ev('c', 'Química', DateTime(2026, 9, 28, 14), location: 'Lab 2'));
      await repo.upsertEvent(_ev('d', 'Seminário', DateTime(2026, 9, 28, 18)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(_in('card-now-next', find.text('Agora')), findsOneWidget);
      expect(_in('card-now-next', find.text('A seguir')), findsOneWidget);
      expect(find.text('Cálculo I'), findsOneWidget);
      expect(find.text('09:30–10:30'), findsOneWidget);
      expect(find.text('Física'), findsOneWidget);
      expect(find.text('14:00–15:00 · Lab 2'), findsOneWidget);
      expect(find.text('Seminário'), findsNothing);
      expect(find.text('+ 1 evento mais tarde'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('card-now-next')));
      expect(_path(tester), '/agenda');
    });

    testWidgets('agenda livre hoje mostra o próximo dia com evento', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('x', 'Aula de quarta', DateTime(2026, 9, 30, 8)));
      await repo.upsertEvent(_ev('y', 'Aula de amanhã', DateTime(2026, 9, 29, 13)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.text('Agenda livre hoje'), findsOneWidget);
      expect(find.text('Próximo: amanhã, 13:00 · Aula de amanhã'), findsOneWidget);
    });

    testWidgets('agenda livre sem nenhum evento à vista', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(find.text('Agenda livre hoje'), findsOneWidget);
      expect(find.text('Nenhum evento à vista.'), findsOneWidget);
    });

    testWidgets('depois que os eventos acabam: nada mais por hoje', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('a', 'Cedo', DateTime(2026, 9, 28, 7)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.text('Nada mais por hoje'), findsOneWidget);
      expect(find.text('Agenda livre hoje'), findsNothing);
    });
  });

  group('Próxima prova', () {
    testWidgets('amanhã às 10:00 com sala', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(
          _ev('p', 'Prova de Redes', DateTime(2026, 9, 29, 10), location: 'Sala B-12'));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.byKey(const Key('card-exam')), findsOneWidget);
      expect(find.text('Prova de Redes'), findsOneWidget);
      expect(find.text('amanhã às 10:00'), findsOneWidget);
      expect(find.text('Sala B-12'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('card-exam')));
      expect(_path(tester), '/agenda');
    });

    testWidgets('em N dias, NPn conta como prova e o mais próximo vence', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('p1', 'Prova de Redes', DateTime(2026, 10, 20, 10)));
      await repo.upsertEvent(_ev('p2', 'NP1 Cálculo', DateTime(2026, 10, 3, 14)));
      await repo.upsertEvent(_ev('a', 'Aula comum', DateTime(2026, 9, 29, 8)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.text('NP1 Cálculo'), findsOneWidget);
      expect(find.text('em 5 dias'), findsOneWidget);
      expect(find.text('Prova de Redes'), findsNothing);
    });

    testWidgets('sem prova nos próximos 30 dias o cartão não aparece', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('p', 'Prova final', DateTime(2026, 11, 20, 10)));
      await repo.upsertEvent(_ev('a', 'Aula comum', DateTime(2026, 9, 29, 8)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.byKey(const Key('card-exam')), findsNothing);
    });
  });

  group('Tarefas', () {
    testWidgets('mostra atrasadas, hoje e em andamento com prioridade e prazo', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(id: 'o', title: 'Resumo', dueAt: DateTime(2026, 9, 26, 23, 59)));
      await repo.upsertTask(TaskItem(
          id: 'h', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59), priority: TaskPriority.alta));
      await repo.upsertTask(const TaskItem(id: 'd', title: 'Projeto', status: TaskStatus.doing));
      await repo.upsertTask(const TaskItem(id: 'f', title: 'Sem data'));
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(find.text('Atrasadas'), findsOneWidget);
      expect(find.text('Resumo'), findsOneWidget);
      expect(find.text('atrasada · 26 set.'), findsOneWidget);
      expect(find.text('Lista 3'), findsOneWidget);
      expect(find.text('hoje'), findsOneWidget);
      expect(_in('card-tasks', find.text('alta')), findsOneWidget);
      expect(find.text('Projeto'), findsOneWidget);
      expect(find.text('em andamento'), findsOneWidget);
      expect(find.text('Sem data'), findsNothing);
    });

    testWidgets('mostra no máximo 5 tarefas e conta o resto', (tester) async {
      final repo = MemoryRepository();
      for (var i = 0; i < 7; i++) {
        await repo.upsertTask(TaskItem(id: 'o$i', title: 'Atrasada $i', dueAt: DateTime(2026, 9, 20 + i)));
      }
      await pumpApp(tester, repo, now: _now, size: _phone);
      expect(_in('card-tasks', find.byType(Checkbox)), findsNWidgets(5));
      expect(find.text('+ 2 tarefas em destaque'), findsOneWidget);
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

    testWidgets('campo rápido cria tarefa sem prazo e limpa o texto', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, now: _now, size: _phone);
      await tester.ensureVisible(find.byKey(const Key('quick-task-field')));
      await tester.enterText(find.byKey(const Key('quick-task-field')), '  Comprar caderno ');
      await tester.tap(find.byKey(const Key('quick-task-add')));
      await tester.pumpAndSettle();
      final created = (await repo.watchTasks().first).single;
      expect(created.title, 'Comprar caderno');
      expect(created.dueAt, isNull);
      expect(find.widgetWithText(TextField, 'Comprar caderno'), findsNothing);
      expect(find.text('Tarefa adicionada'), findsOneWidget);
    });

    testWidgets('falha no campo rápido mantém o texto', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, now: _now, size: _phone);
      repo.failWrites = true;
      await tester.ensureVisible(find.byKey(const Key('quick-task-field')));
      await tester.enterText(find.byKey(const Key('quick-task-field')), 'Comprar caderno');
      await tester.tap(find.byKey(const Key('quick-task-add')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível adicionar. O texto continua no campo.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Comprar caderno'), findsOneWidget);
    });

    testWidgets('"Ver todas" abre Tarefas', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(find.text('Nenhuma tarefa para hoje.'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('tasks-see-all')));
      expect(_path(tester), '/tarefas');
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

  group('Notícias', () {
    NewsRepositoryFixture fixture() => NewsRepositoryFixture();

    testWidgets('mostra as 3 primeiras manchetes e o título abre Notícias', (tester) async {
      final news = fixture().build(count: 5);
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone, news: news);
      expect(find.text('Manchete 0'), findsOneWidget);
      expect(find.text('Manchete 2'), findsOneWidget);
      expect(find.text('Manchete 3'), findsNothing);
      await _tap(tester, find.descendant(of: find.byKey(const Key('card-news')), matching: find.text('Notícias')));
      expect(_path(tester), '/noticias');
    });

    testWidgets('puxar para atualizar relê o feed', (tester) async {
      final news = fixture().build(count: 1);
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone, news: news);
      expect(find.text('Manchete 0'), findsOneWidget);
      await news.setSubscribed('b', true); // mudança no servidor
      await tester.fling(find.byKey(const Key('dashboard-scroll')), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Manchete nova'), findsOneWidget);
    });

    testWidgets('sem manchetes mostra dica', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      expect(find.textContaining('Nenhuma manchete'), findsOneWidget);
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

    testWidgets('Aviso abre o diálogo de aviso e salva', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, now: _now, size: _phone);
      await tester.tap(find.byKey(const Key('quick-new-notice')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('notice-title')), 'Entregar relatório');
      await tester.tap(find.byKey(const Key('notice-save')));
      await tester.pumpAndSettle();
      expect((await repo.watchNotices().first).single.title, 'Entregar relatório');
      expect(find.text('Entregar relatório'), findsOneWidget);
    });

    testWidgets('os 4 botões têm rótulo semântico e alvo de pelo menos 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, MemoryRepository(), now: _now, size: _phone);
      for (final (key, label) in [
        ('quick-new-task', 'Nova tarefa'),
        ('quick-new-event', 'Novo evento'),
        ('quick-new-note', 'Nova nota'),
        ('quick-new-notice', 'Novo aviso'),
      ]) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(48), reason: key);
      }
      handle.dispose();
    });
  });

  group('layout', () {
    testWidgets('celular: uma coluna na ordem de importância', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(_ev('p', 'Prova de Redes', DateTime(2026, 9, 29, 10)));
      await pumpApp(tester, repo, now: _now, size: _phone);
      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      final order = [
        'card-now-next',
        'card-exam',
        'card-tasks',
        'notice-board',
        'email-card',
        'card-news',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(top(order[i]), greaterThan(top(order[i - 1])), reason: '${order[i]} depois de ${order[i - 1]}');
      }
    });

    testWidgets('computador: duas colunas, avisos/e-mail/notícias à direita', (tester) async {
      await pumpApp(tester, MemoryRepository(), now: _now);
      final left = tester.getTopLeft(find.byKey(const Key('card-tasks'))).dx;
      for (final k in ['notice-board', 'email-card', 'card-news']) {
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
          DateTime(2026, 10, 2, 10), location: 'Auditório Principal do Campus Central, andar 2'));
      for (var i = 0; i < 7; i++) {
        await repo.upsertTask(TaskItem(
          id: 't$i',
          title: 'Entregar o relatório final do projeto integrador número $i com anexos',
          dueAt: DateTime(2026, 9, 20 + i),
          priority: i.isEven ? TaskPriority.alta : TaskPriority.media,
        ));
      }
      await repo.upsertNotice(const Notice(
          id: 'n', title: 'Aviso com um título bastante comprido para testar quebra', body: 'Corpo do aviso', pinned: true));
      return repo;
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('360 dp com texto em ${scale}x', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const plan = WakePlan(
            id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'ECHO');
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
          news: MemoryNewsRepository(
            sources: const [
              NewsSource(id: 'a', name: 'Um portal com nome longo', section: 's', feedUrl: 'https://a', subscribed: true),
            ],
            items: [
              for (var i = 0; i < 4; i++)
                NewsItem(
                  id: 'i$i',
                  sourceId: 'a',
                  sourceName: 'Um portal com nome longo',
                  title: 'Uma manchete muito comprida que precisa quebrar em várias linhas número $i',
                  url: 'https://a/$i',
                  publishedAt: DateTime(2026, 9, 28, 8),
                ),
            ],
          ),
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
