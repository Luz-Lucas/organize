import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/ui/org_widgets.dart';

import '../helpers.dart';

void main() {
  testWidgets('Ajustes no celular: temas em duas colunas que preenchem a largura (360 dp)', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: const Size(360, 800));
    final a = tester.getRect(find.byKey(ValueKey('theme-${themeIds[0]}')));
    final b = tester.getRect(find.byKey(ValueKey('theme-${themeIds[1]}')));
    final c = tester.getRect(find.byKey(ValueKey('theme-${themeIds[2]}')));
    expect(a.top, b.top); // lado a lado
    expect(c.top, greaterThan(a.top)); // a terceira desce
    expect((a.width - b.width).abs(), lessThan(0.01));
    expect(a.width, closeTo((360 - 16 * 2 - 8 * 2 - 12) / 2, 0.5));
    expect(a.width, lessThan(212));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ajustes no computador mantém cartões de 212 dp', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: const Size(1000, 1400));
    expect(tester.getSize(find.byKey(ValueKey('theme-${themeIds[0]}'))).width, 212);
  });

  testWidgets('cabeçalho: margem de 16 no celular e 24 no computador', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/tarefas', size: const Size(400, 800));
    var left = tester.getTopLeft(find.text('Tarefas').first).dx;
    expect(left, 16);
    await pumpApp(tester, MemoryRepository(), location: '/tarefas');
    expect(find.byType(PageHeader), findsOneWidget);
    left = tester.getTopLeft(find.text('Tarefas').first).dx;
    expect(left, greaterThanOrEqualTo(24));
  });

  testWidgets('excluir evento: Desfazer traz o evento de volta', (tester) async {
    final repo = MemoryRepository();
    final event = CalendarEvent(
      id: 'e1',
      title: 'Física',
      startsAt: DateTime(2026, 9, 30, 10),
      endsAt: DateTime(2026, 9, 30, 11, 40),
    );
    await repo.upsertEvent(event);
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.text('Física'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-event-e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    final from = DateTime(2026, 9, 1);
    expect(await repo.watchEvents(from: from).first, isEmpty);
    expect(find.text('Evento excluído'), findsOneWidget);

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(await repo.watchEvents(from: from).first, [event]);
  });

  testWidgets('título de evento longo na lista do celular limita a 3 linhas', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Seminário de pesquisa em sistemas distribuídos e computação em nuvem com convidados externos e debate aberto',
      startsAt: defaultNow,
      endsAt: defaultNow.add(const Duration(hours: 1)),
    ));
    await pumpApp(tester, repo, location: '/agenda', size: const Size(360, 760));
    final title = tester.widget<Text>(find.textContaining('Seminário de pesquisa'));
    expect(title.maxLines, 3);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('novo evento: campo de título capitaliza a primeira letra', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/agenda');
    await tester.tap(find.byKey(const Key('new-event')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('event-title'))).textCapitalization,
        TextCapitalization.sentences);
  });
}
