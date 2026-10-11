import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/features/agenda/event_dialog.dart';
import 'package:organizacional/ui/org_theme.dart';

Future<void> _open(
  WidgetTester tester, {
  required DateTime start,
  required DateTime end,
  CalendarEvent? existing,
}) async {
  await initializeDateFormatting('pt_BR');
  await tester.pumpWidget(MaterialApp(
    theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<CalendarEvent>(
          context: context,
          builder: (_) => EventDialog(initialStart: start, initialEnd: end, spaces: const [], existing: existing),
        ),
        child: const Text('abrir'),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('22:00 → 02:00 no mesmo dia salva com término no dia seguinte', (tester) async {
    CalendarEvent? saved;
    await initializeDateFormatting('pt_BR');
    await tester.pumpWidget(MaterialApp(
      theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => saved = await showDialog<CalendarEvent>(
            context: context,
            builder: (_) => EventDialog(
              initialStart: DateTime(2026, 10, 10, 22),
              // Mesmo dia, hora menor: o diálogo resolve para o dia seguinte.
              initialEnd: DateTime(2026, 10, 10, 2),
              spaces: const [],
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Termina no dia seguinte'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('event-title')), 'Festa');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved!.startsAt, DateTime(2026, 10, 10, 22));
    expect(saved!.endsAt, DateTime(2026, 10, 11, 2));
  });

  testWidgets('23:30 → 00:15 (mesmo dia) salva com término no dia seguinte', (tester) async {
    CalendarEvent? saved;
    await initializeDateFormatting('pt_BR');
    await tester.pumpWidget(MaterialApp(
      theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => saved = await showDialog<CalendarEvent>(
            context: context,
            builder: (_) => EventDialog(
              initialStart: DateTime(2026, 10, 10, 23, 30),
              initialEnd: DateTime(2026, 10, 10, 0, 15),
              spaces: const [],
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Termina no dia seguinte'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('event-title')), 'Plantão');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved!.startsAt, DateTime(2026, 10, 10, 23, 30));
    expect(saved!.endsAt, DateTime(2026, 10, 11, 0, 15));
  });

  testWidgets('fim igual ao início continua bloqueado', (tester) async {
    await _open(tester, start: DateTime(2026, 10, 10, 9), end: DateTime(2026, 10, 10, 9));
    await tester.enterText(find.byKey(const Key('event-title')), 'X');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('O fim precisa ser depois do início.'), findsOneWidget);
    expect(find.text('Novo evento'), findsOneWidget);
  });

  testWidgets('campo de dia de término mostra o dia escolhido', (tester) async {
    await _open(tester, start: DateTime(2026, 10, 10, 22), end: DateTime(2026, 10, 12, 8));
    expect(find.descendant(of: find.byKey(const Key('event-end-day')), matching: find.textContaining('12 de out')),
        findsOneWidget);
  });

  testWidgets('edição preserva id, origem e id externo', (tester) async {
    final old = CalendarEvent(
      id: 'abc',
      title: 'Aula',
      startsAt: DateTime(2026, 10, 10, 8),
      endsAt: DateTime(2026, 10, 10, 9),
      source: 'ics',
      externalId: 'ext-1',
    );
    CalendarEvent? saved;
    await initializeDateFormatting('pt_BR');
    await tester.pumpWidget(MaterialApp(
      theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => saved = await showDialog<CalendarEvent>(
            context: context,
            builder: (_) => EventDialog(
                initialStart: old.startsAt, initialEnd: old.endsAt, spaces: const [], existing: old),
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(saved!.id, 'abc');
    expect(saved!.source, 'ics');
    expect(saved!.externalId, 'ext-1');
  });
}
