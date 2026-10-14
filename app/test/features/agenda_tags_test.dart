import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/recurrence.dart';
import 'package:organizacional/features/agenda/agenda_filter.dart';

import '../helpers.dart';

const _aula = EventTag(id: 't-aula', name: 'Aula', color: '#3E63DD', role: EventTagRole.main, position: 0);
const _acad =
    EventTag(id: 't-acad', name: 'Academia', color: '#30A46C', role: EventTagRole.secondary, position: 1);
const _saz = EventTag(id: 't-saz', name: 'Sazonal', color: '#FFB224', role: EventTagRole.seasonal, position: 2);
const _reu = EventTag(id: 't-reu', name: 'Reunião', color: '#8E4EC6', role: EventTagRole.meeting, position: 3);
const _all = [_aula, _acad, _saz, _reu];

final _from = DateTime(2026, 9, 1);

/// Terça 29/09/2026 (dentro da semana aberta, 27/09–03/10).
CalendarEvent _ev(String id, String title, {String? tagId, int hour = 10, bool allDay = false}) => CalendarEvent(
      id: id,
      title: title,
      startsAt: DateTime(2026, 9, 29, hour),
      endsAt: DateTime(2026, 9, 29, hour + 1),
      allDay: allDay,
      tagId: tagId,
    );

/// Conta as chamadas de semeadura.
class _SeedSpy extends MemoryRepository {
  int seeds = 0;

  @override
  Future<int> seedEventTags() {
    seeds++;
    return super.seedEventTags();
  }
}

/// Semeadura que não cria nada (usuário que apagou todas as etiquetas e não as quer de volta).
class _NoSeed extends MemoryRepository {
  @override
  Future<int> seedEventTags() async => 0;
}

Future<T> _withTags<T extends MemoryRepository>(T repo, [List<CalendarEvent> events = const []]) async {
  for (final t in _all) {
    await repo.upsertTag(t);
  }
  await repo.upsertEvents(events);
  return repo;
}

Future<List<CalendarEvent>> _events(MemoryRepository repo) => repo.watchEvents(from: _from).first;
Future<List<EventTag>> _tags(MemoryRepository repo) => repo.watchTags().first;

Color _barColor(WidgetTester tester, String key) =>
    tester.widget<ColoredBox>(find.byKey(ValueKey(key))).color;

void main() {
  group('semeadura ao abrir a agenda', () {
    testWidgets('sem nenhuma etiqueta chama a semeadura uma vez e mostra os filtros', (tester) async {
      final repo = _SeedSpy();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      expect(repo.seeds, 1);
      expect((await _tags(repo)).map((t) => t.name), ['Aula', 'Academia', 'Sazonal', 'Reunião']);
      final bar = find.byKey(const Key('tag-filter-bar'));
      expect(bar, findsOneWidget);
      for (final n in ['Aula', 'Academia', 'Sazonal', 'Reunião', 'Sem etiqueta']) {
        expect(find.descendant(of: bar, matching: find.text(n)), findsOneWidget, reason: n);
      }
    });

    testWidgets('com etiquetas já existentes não semeia', (tester) async {
      final repo = await _withTags(_SeedSpy());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      expect(repo.seeds, 0);
      expect((await _tags(repo)), hasLength(4));
    });

    testWidgets('sem etiquetas e nada a criar: não há barra de filtros', (tester) async {
      await pumpApp(tester, _NoSeed(), location: '/agenda');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag-filter-bar')), findsNothing);
    });

    testWidgets('falha na semeadura não derruba a agenda', (tester) async {
      final repo = _FailSeed();
      await repo.upsertEvent(_ev('e1', 'Física'));
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      expect(find.text('Física'), findsOneWidget);
      expect(find.byKey(const Key('tag-filter-bar')), findsNothing);
    });
  });

  group('visual dos eventos', () {
    testWidgets('semana: barra na cor da etiqueta; main em negrito; secondary mais discreto', (tester) async {
      final repo = await _withTags(MemoryRepository(), [
        _ev('e1', 'Cálculo', tagId: 't-aula'),
        _ev('e2', 'Treino', tagId: 't-acad', hour: 12),
        _ev('e3', 'Dentista', hour: 15),
      ]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      expect(_barColor(tester, 'tag-bar-e1-2026-09-29'), const Color(0xFF3E63DD));
      expect(_barColor(tester, 'tag-bar-e2-2026-09-29'), const Color(0xFF30A46C));
      expect(find.byKey(const ValueKey('tag-bar-e3-2026-09-29')), findsNothing);

      FontWeight? weight(String title) => tester.widget<Text>(find.text(title)).style?.fontWeight;
      expect(weight('Cálculo'), FontWeight.w700);
      expect(weight('Treino')!.value, lessThan(FontWeight.w600.value));
      expect(weight('Dentista'), FontWeight.w600); // sem etiqueta: visual de sempre
    });

    testWidgets('semana: evento de dia inteiro também leva a cor', (tester) async {
      final repo = await _withTags(MemoryRepository(), [_ev('e1', 'Feriado', tagId: 't-saz', allDay: true)]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      expect(_barColor(tester, 'tag-bar-e1-allday'), const Color(0xFFFFB224));
    });

    testWidgets('mês: a pílula leva a cor da etiqueta', (tester) async {
      final repo = await _withTags(MemoryRepository(), [_ev('e1', 'Reunião NP', tagId: 't-reu')]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.byKey(const Key('view-month')));
      await tester.pumpAndSettle();
      expect(_barColor(tester, 'tag-bar-e1-month'), const Color(0xFF8E4EC6));
    });

    testWidgets('celular: o cartão da lista leva a barra na cor da etiqueta', (tester) async {
      final repo = await _withTags(MemoryRepository(), [
        _ev('e1', 'Cálculo', tagId: 't-aula'),
        _ev('e2', 'Dentista', hour: 15),
      ]);
      await pumpApp(tester, repo, location: '/agenda', size: const Size(400, 800));
      await tester.tap(find.byKey(const ValueKey('mini-day-2026-09-29')));
      await tester.pumpAndSettle();
      expect(_barColor(tester, 'tag-bar-e1-list'), const Color(0xFF3E63DD));
      // Sem etiqueta a barra segue a cor de sempre (por espaço), sem chave de etiqueta.
      expect(find.byKey(const ValueKey('tag-bar-e2-list')), findsNothing);
      expect(find.byKey(const ValueKey('agenda-event-e2')), findsOneWidget);
    });

    testWidgets('celular: o ponto do dia no mês usa a cor da etiqueta do primeiro evento etiquetado', (tester) async {
      final repo = await _withTags(MemoryRepository(), [
        _ev('e1', 'Dentista', hour: 8),
        _ev('e2', 'Treino', tagId: 't-acad', hour: 12),
        _ev('e3', 'Cálculo', tagId: 't-aula', hour: 15),
        CalendarEvent(
            id: 'e4', title: 'Livre', startsAt: DateTime(2026, 9, 30, 9), endsAt: DateTime(2026, 9, 30, 10)),
      ]);
      await pumpApp(tester, repo, location: '/agenda', size: const Size(400, 800));
      Color? dot(String day) =>
          (tester.widget<Container>(find.byKey(ValueKey('dot-$day'))).decoration as BoxDecoration).color;
      expect(dot('2026-09-29'), const Color(0xFF30A46C));
      // Dia só com evento sem etiqueta: a cor de destaque de sempre.
      expect(dot('2026-09-30'), isNot(const Color(0xFF30A46C)));
      expect(dot('2026-09-30'), isNotNull);
    });

    testWidgets('Início: "Agora e a seguir" mostra a barra da etiqueta', (tester) async {
      final repo = await _withTags(MemoryRepository(), [
        CalendarEvent(
            id: 'e1',
            title: 'Cálculo',
            startsAt: DateTime(2026, 9, 28, 11),
            endsAt: DateTime(2026, 9, 28, 12),
            tagId: 't-aula'),
      ]);
      await pumpApp(tester, repo, location: '/');
      await tester.pumpAndSettle();
      expect(_barColor(tester, 'tag-bar-e1-dash'), const Color(0xFF3E63DD));
    });
  });

  group('filtros', () {
    Future<MemoryRepository> repoWithEvents() => _withTags(MemoryRepository(), [
          _ev('e1', 'Cálculo', tagId: 't-aula'),
          _ev('e2', 'Treino', tagId: 't-acad', hour: 12),
          _ev('e3', 'Dentista', hour: 15),
        ]);

    testWidgets('esconder e mostrar uma etiqueta filtra a semana', (tester) async {
      await pumpApp(tester, await repoWithEvents(), location: '/agenda');
      await tester.pumpAndSettle();
      expect(find.text('Treino'), findsOneWidget);
      expect(tester.widget<FilterChip>(find.byKey(const Key('tag-filter-t-acad'))).selected, isTrue);

      await tester.tap(find.byKey(const Key('tag-filter-t-acad')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(find.byKey(const Key('tag-filter-t-acad'))).selected, isFalse);
      expect(find.text('Treino'), findsNothing);
      expect(find.text('Cálculo'), findsOneWidget);
      expect(find.text('Dentista'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tag-filter-t-acad')));
      await tester.pumpAndSettle();
      expect(find.text('Treino'), findsOneWidget);
    });

    testWidgets('"Sem etiqueta" esconde só os eventos sem etiqueta', (tester) async {
      await pumpApp(tester, await repoWithEvents(), location: '/agenda');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-filter-none')));
      await tester.pumpAndSettle();
      expect(find.text('Dentista'), findsNothing);
      expect(find.text('Cálculo'), findsOneWidget);
      expect(find.text('Treino'), findsOneWidget);
    });

    testWidgets('o filtro vale no mês e na lista do celular', (tester) async {
      final repo = await repoWithEvents();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-filter-t-aula')));
      await tester.tap(find.byKey(const Key('view-month')));
      await tester.pumpAndSettle();
      expect(find.text('Cálculo'), findsNothing);
      expect(find.text('Treino'), findsOneWidget);
    });

    testWidgets('a escolha é lembrada pelo aparelho (some e volta ao reabrir)', (tester) async {
      final prefs = MemoryAgendaFilterPrefs();
      final repo = await repoWithEvents();
      await pumpApp(tester, repo,
          location: '/agenda', overrides: [agendaFilterPrefsProvider.overrideWithValue(prefs)]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-filter-t-acad')));
      await tester.tap(find.byKey(const Key('tag-filter-none')));
      await tester.pumpAndSettle();
      expect(await prefs.load(), {'t-acad', kNoTagFilter});

      // "Reabre" o app com as mesmas preferências do aparelho.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, repo,
          location: '/agenda', overrides: [agendaFilterPrefsProvider.overrideWithValue(prefs)]);
      await tester.pumpAndSettle();
      expect(find.text('Treino'), findsNothing);
      expect(find.text('Dentista'), findsNothing);
      expect(find.text('Cálculo'), findsOneWidget);
      expect(tester.widget<FilterChip>(find.byKey(const Key('tag-filter-t-acad'))).selected, isFalse);
    });

    testWidgets('etiqueta nova nasce visível mesmo com outras escondidas', (tester) async {
      final prefs = MemoryAgendaFilterPrefs();
      await prefs.save({'t-acad'});
      final repo = await repoWithEvents();
      await pumpApp(tester, repo,
          location: '/agenda', overrides: [agendaFilterPrefsProvider.overrideWithValue(prefs)]);
      await tester.pumpAndSettle();
      await repo.upsertTag(const EventTag(id: 't-nova', name: 'Nova', color: '#E5484D', position: 4));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(find.byKey(const Key('tag-filter-t-nova'))).selected, isTrue);
    });
  });

  group('gerenciar etiquetas', () {
    Future<void> openManager(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('agenda-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-manage-tags')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tags-manager')), findsOneWidget);
    }

    testWidgets('lista as etiquetas na ordem, com o papel de cada uma', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      for (final t in _all) {
        expect(find.byKey(ValueKey('tag-row-${t.id}')), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const ValueKey('tag-row-t-aula')), matching: find.text('Principal')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('tag-row-t-acad')), matching: find.text('Secundária')),
          findsOneWidget);
    });

    testWidgets('criar etiqueta com nome, cor e papel', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(const Key('tag-new')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tag-save')));
      await tester.pump();
      expect(find.text('Dê um nome à etiqueta.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      await tester.tap(find.byKey(const Key('tag-color-D6409F')));
      await tester.tap(find.byKey(const Key('tag-role-main')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tag-save')));
      await tester.pumpAndSettle();

      final created = (await _tags(repo)).firstWhere((t) => t.name == 'Estágio');
      expect(created.color, '#D6409F');
      expect(created.role, EventTagRole.main);
      expect(created.position, 4); // vai para o fim
      expect(find.byKey(ValueKey('tag-row-${created.id}')), findsOneWidget);
    });

    testWidgets('nome repetido mostra o aviso e mantém o editor aberto', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(const Key('tag-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag-name')), 'aula');
      await tester.tap(find.byKey(const Key('tag-save')));
      await tester.pumpAndSettle();
      expect(find.text('Já existe uma etiqueta com esse nome.'), findsOneWidget);
      expect(find.byKey(const Key('tag-name')), findsOneWidget);
      expect(await _tags(repo), hasLength(4));
    });

    testWidgets('renomear, recolorir e mudar o papel', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(const ValueKey('tag-row-t-saz')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('tag-name'))).controller!.text, 'Sazonal');
      await tester.enterText(find.byKey(const Key('tag-name')), 'Férias');
      await tester.tap(find.byKey(const Key('tag-color-0091FF')));
      await tester.tap(find.byKey(const Key('tag-role-secondary')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tag-save')));
      await tester.pumpAndSettle();
      final t = (await _tags(repo)).firstWhere((t) => t.id == 't-saz');
      expect((t.name, t.color, t.role, t.position), ('Férias', '#0091FF', EventTagRole.secondary, 2));
    });

    testWidgets('reordenar com as setas regrava as posições', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(const ValueKey('tag-down-t-aula')));
      await tester.pumpAndSettle();
      expect((await _tags(repo)).map((t) => t.id), ['t-acad', 't-aula', 't-saz', 't-reu']);
      await tester.tap(find.byKey(const ValueKey('tag-up-t-reu')));
      await tester.pumpAndSettle();
      final l = await _tags(repo);
      expect(l.map((t) => t.id), ['t-acad', 't-aula', 't-reu', 't-saz']);
      expect(l.map((t) => t.position), [0, 1, 2, 3]);
      // Os extremos não andam para fora.
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('tag-up-t-acad'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('tag-down-t-saz'))).onPressed, isNull);
    });

    testWidgets('excluir pede confirmação e deixa os eventos sem etiqueta', (tester) async {
      final repo = await _withTags(MemoryRepository(), [_ev('e1', 'Cálculo', tagId: 't-aula')]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(const ValueKey('tag-row-t-aula')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ficarão sem etiqueta'), findsOneWidget);

      // Cancelar não apaga.
      await tester.tap(find.byKey(const Key('tag-delete-cancel')));
      await tester.pumpAndSettle();
      expect(await _tags(repo), hasLength(4));

      await tester.tap(find.byKey(const Key('tag-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-delete-confirm')));
      await tester.pumpAndSettle();
      expect((await _tags(repo)).map((t) => t.id), ['t-acad', 't-saz', 't-reu']);
      final e = (await _events(repo)).single;
      expect(e.title, 'Cálculo');
      expect(e.tagId, isNull);
      expect(find.byKey(const ValueKey('tag-row-t-aula')), findsNothing);
    });

    testWidgets('falha ao salvar mostra o erro e não fecha o editor', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openManager(tester);
      await tester.tap(find.byKey(const Key('tag-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      repo.failWrites = true;
      await tester.tap(find.byKey(const Key('tag-save')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar a etiqueta.'), findsOneWidget);
      expect(find.byKey(const Key('tag-name')), findsOneWidget);
    });
  });

  group('campo Etiqueta no editor de evento', () {
    Future<void> openNew(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
    }

    testWidgets('evento novo: escolher uma etiqueta grava o tagId', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openNew(tester);
      expect(find.text('Etiqueta'), findsOneWidget);
      expect(find.byKey(const Key('event-tag-none')), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-none'))).selected, isTrue);
      await tester.enterText(find.byKey(const Key('event-title')), 'Treino de perna');
      await tester.tap(find.byKey(const Key('event-tag-t-acad')));
      await tester.pump();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-t-acad'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-none'))).selected, isFalse);
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect((await _events(repo)).single.tagId, 't-acad');
    });

    testWidgets('sem etiquetas cadastradas o campo não aparece', (tester) async {
      await pumpApp(tester, _NoSeed(), location: '/agenda');
      await tester.pumpAndSettle();
      await openNew(tester);
      expect(find.text('Etiqueta'), findsNothing);
      expect(find.byKey(const Key('event-tag-none')), findsNothing);
    });

    testWidgets('editar: vem marcada a etiqueta atual e "Sem etiqueta" a remove', (tester) async {
      final repo = await _withTags(MemoryRepository(), [_ev('e1', 'Cálculo', tagId: 't-aula')]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-block-e1-2026-09-29')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-t-aula'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('event-tag-none')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect((await _events(repo)).single.tagId, isNull);
    });

    testWidgets('etiqueta que não existe mais aparece como "Sem etiqueta"', (tester) async {
      final repo = await _withTags(MemoryRepository(), [_ev('e1', 'Cálculo', tagId: 'apagada')]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('event-block-e1-2026-09-29')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-none'))).selected, isTrue);
    });

    testWidgets('série nova com etiqueta: todas as ocorrências a recebem', (tester) async {
      final repo = await _withTags(MemoryRepository());
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await openNew(tester);
      await tester.enterText(find.byKey(const Key('event-title')), 'Treino');
      await tester.tap(find.byKey(const Key('event-tag-t-acad')));
      await tester.tap(find.byKey(const Key('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todo dia').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-repeat-mode-count')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-repeat-count')), '3');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('event-save')));
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      final events = await _events(repo);
      expect(events, hasLength(3));
      expect(events.map((e) => e.tagId).toSet(), {'t-acad'});
    });

    group('em série segue o escopo', () {
      testWidgets('Só este: muda apenas a ocorrência aberta', (tester) async {
        final (repo, series) = await setupAndScope(tester, 'series-scope-one');
        final byId = {for (final e in await _events(repo)) e.id: e};
        expect(byId[series[1].id]!.tagId, 't-reu');
        expect(byId[series[1].id]!.seriesId, isNull);
        for (final i in [0, 2, 3]) {
          expect(byId[series[i].id]!.tagId, 't-aula', reason: 'ocorrência $i');
        }
      });

      testWidgets('Este e os seguintes: muda da aberta em diante', (tester) async {
        final (repo, series) = await setupAndScope(tester, 'series-scope-following');
        final byId = {for (final e in await _events(repo)) e.id: e};
        expect([for (final e in series) byId[e.id]!.tagId], ['t-aula', 't-reu', 't-reu', 't-reu']);
      });

      testWidgets('Todos: muda a série inteira', (tester) async {
        final (repo, series) = await setupAndScope(tester, 'series-scope-all');
        final byId = {for (final e in await _events(repo)) e.id: e};
        expect([for (final e in series) byId[e.id]!.tagId], ['t-reu', 't-reu', 't-reu', 't-reu']);
      });
    });
  });
}

/// Abre a 2ª ocorrência da série (qui 01/10), troca a etiqueta para Reunião, salva e escolhe o escopo.
Future<(MemoryRepository, List<CalendarEvent>)> setupAndScope(WidgetTester tester, String scopeKey) async {
  var n = 0;
  final series = SeriesOps.buildSeries(
    CalendarEvent(
        id: 'tpl',
        title: 'Cálculo',
        startsAt: DateTime(2026, 9, 29, 18),
        endsAt: DateTime(2026, 9, 29, 19, 40),
        tagId: 't-aula'),
    Recurrence(freq: RepeatFreq.weekly, days: {2, 4}, count: 4),
    () => 's${++n}',
  );
  final repo = await _withTags(MemoryRepository(), series);
  await pumpApp(tester, repo, location: '/agenda');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('event-block-${series[1].id}-2026-10-01')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('event-tag-t-reu')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('event-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(scopeKey)));
  await tester.pumpAndSettle();
  return (repo, series);
}

/// Repositório cuja semeadura falha.
class _FailSeed extends MemoryRepository {
  @override
  Future<int> seedEventTags() => throw const RepositoryException('Sem conexão (simulado)');
}
