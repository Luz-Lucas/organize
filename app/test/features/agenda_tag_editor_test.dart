import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/features/agenda/tag_editor.dart';

import '../helpers.dart';

const _aula = EventTag(id: 't-aula', name: 'Aula', color: '#3E63DD', role: EventTagRole.main, position: 0);
const _acad =
    EventTag(id: 't-acad', name: 'Academia', color: '#30A46C', role: EventTagRole.secondary, position: 1);
const _all = [_aula, _acad];

final _from = DateTime(2026, 9, 1);

CalendarEvent _ev(String id, String title, {String? tagId}) => CalendarEvent(
      id: id,
      title: title,
      startsAt: DateTime(2026, 9, 29, 10),
      endsAt: DateTime(2026, 9, 29, 11),
      tagId: tagId,
    );

Future<MemoryRepository> _repo({List<EventTag> tags = _all, List<CalendarEvent> events = const []}) async {
  final repo = MemoryRepository();
  for (final t in tags) {
    await repo.upsertTag(t);
  }
  await repo.upsertEvents(events);
  return repo;
}

Future<List<EventTag>> _tags(MemoryRepository repo) => repo.watchTags().first;
Future<List<CalendarEvent>> _events(MemoryRepository repo) => repo.watchEvents(from: _from).first;

/// Abre o editor pelo chip "+ Nova etiqueta" da fileira de filtros.
Future<void> _openFromBar(WidgetTester tester) async {
  final chip = find.byKey(const Key('tag-new'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _openFromEventDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('new-event')));
  await tester.pumpAndSettle();
  final chip = find.byKey(const Key('event-tag-new'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _saveEditor(WidgetTester tester) async {
  final save = find.byKey(const Key('tag-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> _longPressChip(WidgetTester tester, String id) async {
  final chip = find.byKey(Key('tag-filter-$id'));
  await tester.ensureVisible(chip);
  await tester.longPress(chip);
  await tester.pumpAndSettle();
}

void main() {
  group('validateTagName', () {
    test('exige nome de 1 a 40 caracteres', () {
      expect(validateTagName('', const []), 'Dê um nome à etiqueta.');
      expect(validateTagName('   ', const []), 'Dê um nome à etiqueta.');
      expect(validateTagName('a' * 41, const []), 'O nome pode ter até 40 caracteres.');
      expect(validateTagName('a' * 40, const []), isNull);
      expect(validateTagName('A', const []), isNull);
    });

    test('é único sem diferenciar maiúsculas e ignora a própria etiqueta', () {
      expect(validateTagName('aula', _all), 'Já existe uma etiqueta com esse nome.');
      expect(validateTagName('  ACADEMIA ', _all), 'Já existe uma etiqueta com esse nome.');
      expect(validateTagName('Aula', _all, editingId: 't-aula'), isNull);
      expect(validateTagName('Academia', _all, editingId: 't-aula'), 'Já existe uma etiqueta com esse nome.');
    });
  });

  group('cor livre: conversões', () {
    test('parseTagHex aceita #RRGGBB (com ou sem #) e rejeita o resto', () {
      expect(parseTagHex('#3E63DD'), const Color(0xFF3E63DD));
      expect(parseTagHex('3e63dd'), const Color(0xFF3E63DD));
      expect(parseTagHex('#3E63D'), isNull);
      expect(parseTagHex('#3E63DDA'), isNull);
      expect(parseTagHex('#GGGGGG'), isNull);
      expect(parseTagHex(''), isNull);
    });
  });

  group('criar pela fileira de filtros', () {
    testWidgets('"+ Nova etiqueta" é o último chip da fileira', (tester) async {
      await pumpApp(tester, await _repo(), location: '/agenda');
      await tester.pumpAndSettle();
      final bar = find.byKey(const Key('tag-filter-bar'));
      expect(find.descendant(of: bar, matching: find.byKey(const Key('tag-new'))), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('+ Nova etiqueta')), findsOneWidget);
      final none = tester.getTopLeft(find.byKey(const Key('tag-filter-none'))).dx;
      final nova = tester.getTopLeft(find.byKey(const Key('tag-new'))).dx;
      expect(nova, greaterThan(none));
    });

    testWidgets('nome e cor da paleta: cria, aparece na fileira e vai para o fim', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      expect(find.text('Nova etiqueta'), findsOneWidget); // título do diálogo

      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      await tester.tap(find.byKey(const Key('tag-color-D6409F')));
      await tester.pump();
      await _saveEditor(tester);

      final created = (await _tags(repo)).firstWhere((t) => t.name == 'Estágio');
      expect(created.color, '#D6409F');
      expect(created.role, EventTagRole.normal);
      expect(created.position, 2);
      expect(find.byKey(const Key('tag-name')), findsNothing);
      expect(find.byKey(Key('tag-filter-${created.id}')), findsOneWidget);
    });

    testWidgets('nome vazio não salva', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      await _saveEditor(tester);
      expect(find.text('Dê um nome à etiqueta.'), findsOneWidget);
      expect(await _tags(repo), hasLength(2));
    });

    testWidgets('nome repetido (sem diferenciar maiúsculas) mostra erro e não cria', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      await tester.enterText(find.byKey(const Key('tag-name')), 'aULA');
      await tester.pump();
      expect(find.text('Já existe uma etiqueta com esse nome.'), findsOneWidget);
      await _saveEditor(tester);
      expect(find.text('Já existe uma etiqueta com esse nome.'), findsOneWidget);
      expect(find.byKey(const Key('tag-name')), findsOneWidget); // continua aberto
      expect(await _tags(repo), hasLength(2));
    });

    testWidgets('papel é opcional, mas pode ser escolhido', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      await tester.enterText(find.byKey(const Key('tag-name')), 'Congresso');
      final role = find.byKey(const Key('tag-role-seasonal'));
      await tester.ensureVisible(role);
      await tester.tap(role);
      await tester.pump();
      expect(find.textContaining('época do ano'), findsOneWidget);
      await _saveEditor(tester);
      expect((await _tags(repo)).firstWhere((t) => t.name == 'Congresso').role, EventTagRole.seasonal);
    });
  });

  group('cor livre e prévia', () {
    testWidgets('hex válido define a cor e a prévia a usa', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      await tester.tap(find.byKey(const Key('tag-color-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag-hex')), '#1a2b3c');
      await tester.pump();
      expect(tester.widget<ColoredBox>(find.byKey(const Key('tag-preview-bar'))).color, const Color(0xFF1A2B3C));
      await _saveEditor(tester);
      expect((await _tags(repo)).firstWhere((t) => t.name == 'Estágio').color, '#1A2B3C');
    });

    testWidgets('hex inválido mostra erro e bloqueia o salvar', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      await tester.tap(find.byKey(const Key('tag-color-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag-hex')), '#12G4');
      await tester.pump();
      expect(find.text('Use o formato #RRGGBB, como #3E63DD.'), findsOneWidget);
      await _saveEditor(tester);
      expect(find.byKey(const Key('tag-name')), findsOneWidget); // continua aberto
      expect(await _tags(repo), hasLength(2));

      // Corrigindo o hex, volta a salvar.
      await tester.enterText(find.byKey(const Key('tag-hex')), '#123456');
      await tester.pump();
      expect(find.text('Use o formato #RRGGBB, como #3E63DD.'), findsNothing);
      await _saveEditor(tester);
      expect((await _tags(repo)).firstWhere((t) => t.name == 'Estágio').color, '#123456');
    });

    testWidgets('faixa de matiz e quadrado de saturação/brilho mudam a cor', (tester) async {
      await pumpApp(tester, await _repo(), location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      await tester.tap(find.byKey(const Key('tag-color-custom')));
      await tester.pumpAndSettle();
      String hex() => tester.widget<TextField>(find.byKey(const Key('tag-hex'))).controller!.text;

      // Matiz: o começo da faixa é vermelho.
      final hue = find.byKey(const Key('tag-hue'));
      await tester.ensureVisible(hue);
      await tester.tapAt(tester.getTopLeft(hue) + const Offset(1, 5));
      await tester.pump();
      final red = parseTagHex(hex())!;
      expect(red.r, greaterThan(red.g + 0.3));
      expect(red.r, greaterThan(red.b + 0.3));

      // SV: canto superior direito = cor pura (saturação e brilho máximos); inferior = preto.
      final sv = find.byKey(const Key('tag-sv'));
      await tester.tapAt(tester.getTopRight(sv) + const Offset(-1, 1));
      await tester.pump();
      final pure = parseTagHex(hex())!;
      expect(pure.r, greaterThan(0.98));
      expect(pure.g, lessThan(0.1));
      expect(pure.b, lessThan(0.01));
      await tester.tapAt(tester.getBottomLeft(sv) + const Offset(1, -1));
      await tester.pump();
      final dark = parseTagHex(hex())!;
      expect(dark.r + dark.g + dark.b, lessThan(0.1));
    });

    testWidgets('a prévia acompanha nome e papel', (tester) async {
      await pumpApp(tester, await _repo(), location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromBar(tester);
      Text title() => tester.widget<Text>(find.byKey(const Key('tag-preview-title')));
      expect(title().data, 'Nome da etiqueta');
      expect(title().style?.fontWeight, FontWeight.w600); // papel comum
      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      final main = find.byKey(const Key('tag-role-main'));
      await tester.ensureVisible(main);
      await tester.tap(main);
      await tester.pump();
      expect(title().data, 'Estágio');
      expect(title().style?.fontWeight, FontWeight.w700);
    });
  });

  group('editar e excluir pelo toque longo', () {
    testWidgets('segurar uma etiqueta abre o menu com Editar e Excluir', (tester) async {
      await pumpApp(tester, await _repo(), location: '/agenda');
      await tester.pumpAndSettle();
      await _longPressChip(tester, 't-acad');
      expect(find.byKey(const Key('tag-menu-edit')), findsOneWidget);
      expect(find.byKey(const Key('tag-menu-delete')), findsOneWidget);
      // O toque longo não esconde a etiqueta.
      expect(tester.widget<FilterChip>(find.byKey(const Key('tag-filter-t-acad'))).selected, isTrue);
    });

    testWidgets('Editar abre o editor preenchido e salva as mudanças', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _longPressChip(tester, 't-acad');
      await tester.tap(find.byKey(const Key('tag-menu-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Editar etiqueta'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('tag-name'))).controller!.text, 'Academia');
      await tester.enterText(find.byKey(const Key('tag-name')), 'Treino');
      await tester.tap(find.byKey(const Key('tag-color-0091FF')));
      await tester.pump();
      await _saveEditor(tester);
      final t = (await _tags(repo)).firstWhere((t) => t.id == 't-acad');
      expect((t.name, t.color, t.role, t.position), ('Treino', '#0091FF', EventTagRole.secondary, 1));
      expect(find.descendant(of: find.byKey(const Key('tag-filter-t-acad')), matching: find.text('Treino')),
          findsOneWidget);
    });

    testWidgets('editar mantendo o próprio nome não conta como repetido', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _longPressChip(tester, 't-acad');
      await tester.tap(find.byKey(const Key('tag-menu-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-color-E5484D')));
      await tester.pump();
      expect(find.text('Já existe uma etiqueta com esse nome.'), findsNothing);
      await _saveEditor(tester);
      expect((await _tags(repo)).firstWhere((t) => t.id == 't-acad').color, '#E5484D');
    });

    testWidgets('Excluir pede confirmação; confirmar deixa os eventos sem etiqueta', (tester) async {
      final repo = await _repo(events: [_ev('e1', 'Cálculo', tagId: 't-aula')]);
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _longPressChip(tester, 't-aula');
      await tester.tap(find.byKey(const Key('tag-menu-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ficarão sem etiqueta'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tag-delete-cancel')));
      await tester.pumpAndSettle();
      expect(await _tags(repo), hasLength(2));

      await _longPressChip(tester, 't-aula');
      await tester.tap(find.byKey(const Key('tag-menu-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-delete-confirm')));
      await tester.pumpAndSettle();

      expect((await _tags(repo)).map((t) => t.id), ['t-acad']);
      final e = (await _events(repo)).single;
      expect(e.title, 'Cálculo');
      expect(e.tagId, isNull);
      expect(find.byKey(const Key('tag-filter-t-aula')), findsNothing);
    });
  });

  group('editor de evento', () {
    testWidgets('sem nenhuma etiqueta o seletor aparece com "Sem etiqueta" e "+ Nova"', (tester) async {
      await pumpApp(tester, await _repo(tags: const []), location: '/agenda');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      expect(find.text('Etiqueta'), findsOneWidget);
      expect(find.byKey(const Key('event-tag-none')), findsOneWidget);
      expect(find.byKey(const Key('event-tag-new')), findsOneWidget);
      expect(find.text('+ Nova'), findsOneWidget);
    });

    testWidgets('"+ Nova" cria com cor livre por hex e deixa a etiqueta selecionada no evento', (tester) async {
      final repo = await _repo();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.pumpAndSettle();
      await _openFromEventDialog(tester);
      await tester.enterText(find.byKey(const Key('tag-name')), 'Estágio');
      await tester.tap(find.byKey(const Key('tag-color-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag-hex')), '#1A2B3C');
      await tester.pump();
      await _saveEditor(tester);

      final created = (await _tags(repo)).firstWhere((t) => t.name == 'Estágio');
      expect(created.color, '#1A2B3C');
      // De volta ao evento: a nova etiqueta aparece e já vem marcada.
      expect(find.byKey(const Key('tag-name')), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(Key('event-tag-${created.id}'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-none'))).selected, isFalse);

      await tester.enterText(find.byKey(const Key('event-title')), 'Primeiro dia');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect((await _events(repo)).single.tagId, created.id);
    });

    testWidgets('cancelar o editor de etiqueta mantém a seleção anterior', (tester) async {
      await pumpApp(tester, await _repo(), location: '/agenda');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-tag-t-aula')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('event-tag-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-cancel')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('event-tag-t-aula'))).selected, isTrue);
    });
  });

  group('telas pequenas e fonte grande', () {
    testWidgets('360 dp com fonte 1,3x: fileira, editor com cor livre e editor de evento sem estourar',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, await _repo(), location: '/agenda', size: const Size(360, 740));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _openFromBar(tester);
      await tester.enterText(find.byKey(const Key('tag-name')), 'Uma etiqueta com um nome bem comprido mesmo');
      await tester.tap(find.byKey(const Key('tag-color-custom')));
      await tester.pumpAndSettle();
      final role = find.byKey(const Key('tag-role-seasonal'));
      await tester.ensureVisible(role);
      await tester.tap(role);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('tag-cancel')));
      await tester.pumpAndSettle();

      await _longPressChip(tester, 't-aula');
      expect(find.byKey(const Key('tag-menu-edit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tag-menu-delete')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('tag-delete-cancel')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('event-tag-new')));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('event-tag-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
