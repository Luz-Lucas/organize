import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/ui/motif_painter.dart';
import 'package:organizacional/ui/org_theme.dart';
import 'package:organizacional/ui/org_widgets.dart';

void main() {
  test('10 temas, ids na ordem, desconhecido vira violeta', () {
    expect(orgThemes.map((t) => t.id), themeIds);
    expect(orgThemeById('neon').id, 'violeta');
    expect(orgThemeById('violeta').surface, const Color(0xFF160F1E));
    expect(orgThemeById('bronze').accent, const Color(0xFFB8692F));
    expect(orgThemeById('indigo').name, 'Índigo');
  });

  test('mapeamento Material segue as regras dos PDFs', () {
    for (final s in orgThemes) {
      final t = buildOrgTheme(s, googleFonts: false);
      expect(t.brightness, Brightness.dark);
      expect(t.colorScheme.primary, s.accentDeep);
      expect(t.colorScheme.onPrimary, s.onAccent);
      expect(t.colorScheme.surface, s.surface);
      expect(t.colorScheme.onSurface, s.ink);
      expect(t.colorScheme.onPrimaryContainer, s.accentText);
      expect(t.colorScheme.tertiary, s.accent);
      expect(t.extension<OrgTokens>()!.spec.id, s.id);
    }
  });

  test('cada motivo pinta sem exceção', () {
    for (final s in orgThemes) {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      MotifPainter(motif: s.motif, color: s.accent.withValues(alpha: 0.14))
          .paint(canvas, const Size(200, 100));
      recorder.endRecording();
    }
    // Motivo desconhecido não pinta nem falha.
    MotifPainter(motif: 'nada', color: const Color(0xFFFFFFFF))
        .paint(Canvas(PictureRecorder()), const Size(10, 10));
  });

  testWidgets('widgets compartilhados leem os tokens do tema', (tester) async {
    final spec = orgThemeById('coral');
    await tester.pumpWidget(MaterialApp(
      theme: buildOrgTheme(spec, googleFonts: false),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Text(context.org.id),
              const PageHeader(title: 'Título', subtitle: 'sub', actions: [Icon(Icons.add)]),
              const OrgCard(child: Text('dentro')),
              const OrgBadge('Alta', tone: OrgBadgeTone.danger),
              const MotifBackground(child: Text('motivo')),
              const SectionHeader('Seção'),
              const EmptyHint('Vazio'),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('coral'), findsOneWidget);
    for (final t in ['Título', 'sub', 'dentro', 'Alta', 'motivo', 'Seção', 'Vazio']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });
}
