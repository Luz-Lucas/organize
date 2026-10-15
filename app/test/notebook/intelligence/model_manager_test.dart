import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/intelligence/model_manager.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';

import 'fake_recognizer.dart';

void main() {
  late FakeInkRecognizer rec;
  late InkDownloadPolicy policy;
  late bool onWifi;
  late ProviderContainer c;
  late List<InkModelState> states;

  ProviderContainer build({InkRecognizer? recognizer}) {
    final container = ProviderContainer(overrides: [
      inkRecognizerProvider.overrideWithValue(recognizer ?? rec),
      inkDownloadPolicyProvider.overrideWithValue(policy),
      inkWifiCheckProvider.overrideWithValue(() async => onWifi),
    ]);
    addTearDown(container.dispose);
    states = [];
    container.listen(inkModelManagerProvider, (_, s) => states.add(s), fireImmediately: true);
    return container;
  }

  setUp(() {
    rec = FakeInkRecognizer(ready: false);
    policy = InkDownloadPolicy();
    onWifi = true;
    c = build();
  });

  InkModelManager manager() => c.read(inkModelManagerProvider.notifier);
  InkModelState state() => c.read(inkModelManagerProvider);

  test('começa verificando e vira "ausente" quando o modelo não está no aparelho', () async {
    expect(states.first.status, InkModelStatus.checking);
    await pumpEventQueue();
    expect(state().status, InkModelStatus.missing);
  });

  test('modelo já baixado: pronto', () async {
    rec.ready = true;
    c = build();
    await pumpEventQueue();
    expect(state().status, InkModelStatus.ready);
  });

  test('plataforma sem reconhecimento (Noop): não suportado', () async {
    c = build(recognizer: const NoopInkRecognizer());
    await pumpEventQueue();
    expect(state().status, InkModelStatus.unsupported);
    expect(await manager().download(), InkDownloadOutcome.unsupported);
  });

  test('baixar no Wi-Fi: baixando (sem progresso conhecido) e depois pronto', () async {
    await pumpEventQueue();
    final done = manager().download();
    await pumpEventQueue();
    expect(state().status, InkModelStatus.downloading);
    expect(state().progress, isNull);
    rec.ready = true; // o ML Kit terminou
    await rec.downloadCtl!.close();
    expect(await done, InkDownloadOutcome.finished);
    expect(state().status, InkModelStatus.ready);
    expect(rec.downloads, 1);
  });

  test('progresso emitido pelo reconhecedor aparece no estado', () async {
    await pumpEventQueue();
    final done = manager().download();
    await pumpEventQueue();
    rec.downloadCtl!.add(0.4);
    await pumpEventQueue();
    expect(state().progress, 0.4);
    rec.ready = true;
    await rec.downloadCtl!.close();
    await done;
  });

  test('sem Wi-Fi: não baixa e pede confirmação; confirmando, baixa com dados móveis', () async {
    onWifi = false;
    await pumpEventQueue();
    expect(await manager().download(), InkDownloadOutcome.needsWifi);
    expect(rec.downloads, 0);
    expect(state().status, InkModelStatus.missing);

    final done = manager().download(allowMobileData: true);
    await pumpEventQueue();
    expect(rec.downloads, 1);
    expect(policy.allowMobileData, isTrue);
    rec.ready = true;
    await rec.downloadCtl!.close();
    await done;
    expect(policy.allowMobileData, isFalse, reason: 'a permissão vale para um download só');
    expect(state().status, InkModelStatus.ready);
  });

  test('falha no download: erro com mensagem em português; dá para tentar de novo', () async {
    await pumpEventQueue();
    final done = manager().download();
    await pumpEventQueue();
    rec.downloadCtl!.addError(StateError('sem rede'));
    expect(await done, InkDownloadOutcome.failed);
    expect(state().status, InkModelStatus.error);
    expect(state().error, contains('baixar'));
    expect(policy.allowMobileData, isFalse);

    final again = manager().download();
    await pumpEventQueue();
    expect(rec.downloads, 2);
    rec.ready = true;
    await rec.downloadCtl!.close();
    await again;
    expect(state().status, InkModelStatus.ready);
  });

  test('pedir de novo durante o download não baixa duas vezes', () async {
    await pumpEventQueue();
    final first = manager().download();
    await pumpEventQueue();
    expect(await manager().download(), InkDownloadOutcome.alreadyRunning);
    expect(rec.downloads, 1);
    rec.ready = true;
    await rec.downloadCtl!.close();
    await first;
  });

  test('apagar: remove o modelo e volta a "ausente"', () async {
    rec.ready = true;
    c = build();
    await pumpEventQueue();
    expect(state().status, InkModelStatus.ready);
    await manager().delete();
    expect(rec.deletes, 1);
    expect(state().status, InkModelStatus.missing);
  });

  test('refresh relê o estado do aparelho', () async {
    await pumpEventQueue();
    rec.ready = true;
    await manager().refresh();
    expect(state().status, InkModelStatus.ready);
  });
}
