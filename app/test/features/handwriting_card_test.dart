import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/settings/handwriting_card.dart';
import 'package:organizacional/notebook/intelligence/model_manager.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';
import 'package:organizacional/notebook/state/handwriting_providers.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../notebook/intelligence/fake_recognizer.dart';

void main() {
  late FakeInkRecognizer rec;
  late InkDownloadPolicy policy;
  late bool onWifi;

  setUp(() {
    rec = FakeInkRecognizer(ready: false);
    policy = InkDownloadPolicy();
    onWifi = true;
  });

  Future<ProviderContainer> pump(WidgetTester t, {InkRecognizer? recognizer, List<Override> extra = const []}) async {
    t.view.physicalSize = const Size(500, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final overrides = <Override>[
      inkRecognizerProvider.overrideWithValue(recognizer ?? rec),
      inkDownloadPolicyProvider.overrideWithValue(policy),
      inkWifiCheckProvider.overrideWithValue(() async => onWifi),
      ...extra,
    ];
    await t.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildOrgTheme(orgThemeById('violeta'), googleFonts: false),
        home: const Scaffold(body: SingleChildScrollView(child: HandwritingCard())),
      ),
    ));
    await t.pump();
    await t.pump();
    return ProviderScope.containerOf(t.element(find.byType(HandwritingCard)));
  }

  testWidgets('as três chaves aparecem ligadas e mudam as preferências do aparelho', (t) async {
    final c = await pump(t);
    for (final key in ['hw-recognize', 'hw-spell', 'hw-gestures']) {
      expect(t.widget<Switch>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Switch))).value, isTrue,
          reason: key);
    }
    expect(find.text('Reconhecer escrita (busca)'), findsOneWidget);
    expect(find.text('Corretor ortográfico'), findsOneWidget);
    expect(find.text('Gestos de edição'), findsOneWidget);

    await t.tap(find.byKey(const Key('hw-spell')));
    await t.pump();
    expect(c.read(spellCheckEnabledProvider), isFalse);
    expect(c.read(recognizeWritingEnabledProvider), isTrue);
    await t.tap(find.byKey(const Key('hw-gestures')));
    await t.tap(find.byKey(const Key('hw-recognize')));
    await t.pump();
    expect(c.read(editGesturesEnabledProvider), isFalse);
    expect(c.read(recognizeWritingEnabledProvider), isFalse);
  });

  testWidgets('plataforma sem reconhecimento: explica e não mostra o modelo', (t) async {
    await pump(t, recognizer: const NoopInkRecognizer());
    expect(find.byKey(const Key('hw-unsupported')), findsOneWidget);
    expect(find.byKey(const Key('hw-model-download')), findsNothing);
    expect(find.byKey(const Key('hw-model-delete')), findsNothing);
    expect(find.byKey(const Key('hw-recognize')), findsOneWidget, reason: 'as chaves seguem disponíveis');
  });

  testWidgets('modelo ausente: Baixar no Wi-Fi mostra o progresso e termina instalado', (t) async {
    await pump(t);
    expect(find.byKey(const Key('hw-model-status')), findsOneWidget);
    expect(find.text('Não instalado'), findsOneWidget);
    await t.tap(find.byKey(const Key('hw-model-download')));
    await t.pump();
    await t.pump();
    expect(rec.downloads, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
    rec.downloadCtl!.add(0.5);
    await t.pump();
    await t.pump();
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.5);
    rec.ready = true;
    await rec.downloadCtl!.close();
    await t.pump();
    await t.pump();
    expect(find.text('Instalado'), findsOneWidget);
    expect(find.byKey(const Key('hw-model-delete')), findsOneWidget);
    expect(find.byKey(const Key('hw-model-download')), findsNothing);
  });

  testWidgets('sem Wi-Fi pergunta antes de gastar dados móveis; cancelar não baixa', (t) async {
    onWifi = false;
    await pump(t);
    await t.tap(find.byKey(const Key('hw-model-download')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hw-mobile-confirm')), findsOneWidget);
    expect(find.textContaining('dados móveis'), findsWidgets);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(rec.downloads, 0);
    expect(find.text('Não instalado'), findsOneWidget);
  });

  testWidgets('sem Wi-Fi e confirmando: baixa permitindo dados móveis', (t) async {
    onWifi = false;
    await pump(t);
    await t.tap(find.byKey(const Key('hw-model-download')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('hw-mobile-confirm')));
    await t.pump();
    await t.pump();
    expect(rec.downloads, 1);
    expect(policy.allowMobileData, isTrue);
    rec.ready = true;
    await rec.downloadCtl!.close();
    await t.pump();
    await t.pump();
    expect(policy.allowMobileData, isFalse);
    expect(find.text('Instalado'), findsOneWidget);
  });

  testWidgets('modelo instalado: apagar pede confirmação e libera o espaço', (t) async {
    rec.ready = true;
    await pump(t);
    expect(find.text('Instalado'), findsOneWidget);
    await t.tap(find.byKey(const Key('hw-model-delete')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('hw-delete-confirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('hw-delete-confirm')));
    await t.pumpAndSettle();
    expect(rec.deletes, 1);
    expect(find.text('Não instalado'), findsOneWidget);
  });

  testWidgets('falha no download mostra o erro e deixa tentar de novo', (t) async {
    await pump(t);
    await t.tap(find.byKey(const Key('hw-model-download')));
    await t.pump();
    await t.pump();
    rec.downloadCtl!.addError(StateError('sem rede'));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('hw-model-error')), findsOneWidget);
    expect(find.byKey(const Key('hw-model-download')), findsOneWidget);
  });
}
