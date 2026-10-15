import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/data/notebook_repository.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';
import 'package:organizacional/notebook/intelligence/transcript.dart';
import 'package:organizacional/notebook/state/notebook_controller.dart';
import 'package:organizacional/notebook/state/notebook_pending_store.dart';
import 'package:organizacional/notebook/ui/notebook_session.dart';

import '../data/notebook_test_support.dart';
import 'controlled_repo.dart';
import '../intelligence/fake_recognizer.dart';

class _NoImages implements NotebookImageStore {
  @override
  Future<String> upload(Uint8List bytes, String ext) async => 'p.$ext';
  @override
  Future<ImageProvider> load(String path) async => throw UnimplementedError();
}

/// Uma linha por página: o texto é o que o reconhecedor devolver para os traços.
Future<PageTranscript> oneLine(PageDoc doc, InkRecognizer r, {bool Function()? isCancelled}) async {
  if (doc.strokes.isEmpty) return PageTranscript.empty;
  final c = await r.recognize(doc.strokes);
  return PageTranscript(text: c.isEmpty ? '' : c.first, lineCount: 1);
}

void main() {
  late MemoryNotebookRepository repo;
  late MemoryNotebookPendingStore pending;
  late List<NotebookController> made;
  late List<bool> pendingFlags;
  late FakeInkRecognizer rec;
  late bool enabled;

  NotebookController make({
    NotebookRepository? useRepo,
    InkRecognizer? recognizer,
    bool noRecognizer = false,
    Future<PageTranscript> Function(PageDoc, InkRecognizer, {bool Function()? isCancelled})? transcriber,
  }) {
    final c = NotebookController(
      noteId: 'n1',
      repo: useRepo ?? repo,
      images: _NoImages(),
      pending: pending,
      onPendingChanged: pendingFlags.add,
      recognizer: noRecognizer ? null : (recognizer ?? rec),
      recognizeEnabled: () => enabled,
      transcriber: transcriber ?? oneLine,
    );
    made.add(c);
    return c;
  }

  setUp(() {
    repo = MemoryNotebookRepository();
    pending = MemoryNotebookPendingStore();
    made = [];
    pendingFlags = [];
    enabled = true;
    rec = FakeInkRecognizer(resolve: (strokes) => ['texto ${strokes.length}']);
  });
  tearDown(() {
    for (final c in made) {
      c.dispose();
    }
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(Duration.zero);
    }
  }

  Future<void> elapse(WidgetTester t, Duration d) async {
    await t.pump(d);
    await settle(t);
  }

  Future<NotebookController> started(WidgetTester t, {NotebookController Function()? build}) async {
    await repo.addPage('n1');
    final c = (build ?? make)();
    unawaited(c.start());
    await settle(t);
    return c;
  }

  String pageId(NotebookController c) => c.currentPages.first.id;
  Future<String> serverText() async => (await repo.listPages('n1')).first.recognizedText;

  testWidgets('3 s sem traços: reconhece em segundo plano e grava o texto no servidor', (t) async {
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1', 's2']));
    await elapse(t, const Duration(milliseconds: 1600)); // debounce: salvou a tinta
    expect(repo.saveCount, 1);
    expect(await serverText(), '');
    expect(rec.calls, isEmpty);
    await elapse(t, const Duration(milliseconds: 1500)); // ~3,1 s desde o último traço
    expect(rec.calls, hasLength(1));
    expect(await serverText(), 'texto 2');
    expect(idsOf((await repo.listPages('n1')).first.data), {'s1', 's2'});
  });

  testWidgets('cada traço novo adia o reconhecimento (3 s depois do último)', (t) async {
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 2));
    c.updatePage(pageId(c), docOf(['s1', 's2']));
    await elapse(t, const Duration(milliseconds: 2500));
    expect(rec.calls, isEmpty, reason: 'só 2,5 s desde o último traço');
    await elapse(t, const Duration(milliseconds: 700));
    expect(rec.calls, hasLength(1));
    expect(rec.calls.single.ids, ['s1', 's2']);
  });

  testWidgets('não reemite páginas nem cria laço: texto gravado uma vez, sem novo reconhecimento', (t) async {
    final c = await started(t);
    var emissions = 0;
    c.pages.listen((_) => emissions++);
    await settle(t);
    final before = emissions;
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 4));
    final afterRecognition = emissions;
    final saves = repo.saveCount;
    final calls = rec.calls.length;
    await elapse(t, const Duration(seconds: 60)); // eco do realtime, timers, tudo
    expect(rec.calls.length, calls, reason: 'o eco do próprio save não reinicia o reconhecimento');
    expect(repo.saveCount, saves, reason: 'nada mais é gravado');
    expect(emissions, afterRecognition);
    expect(afterRecognition - before, lessThanOrEqualTo(1));
    expect(await serverText(), 'texto 1');
    expect(calls, 1);
    expect(saves, 2); // tinta + texto
  });

  testWidgets('transcript é publicado sem reemitir as páginas', (t) async {
    final c = await started(t);
    final seen = <String>[];
    c.transcripts.listen((e) => seen.add('${e.pageId}:${e.transcript.text}'));
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 4));
    expect(seen, ['${pageId(c)}:texto 1']);
    expect(c.transcriptOf(pageId(c))?.text, 'texto 1');
    expect(c.recognizedTextOf(pageId(c)), 'texto 1');
  });

  testWidgets('chave desligada: não reconhece, a tinta salva normalmente', (t) async {
    enabled = false;
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 10));
    expect(rec.calls, isEmpty);
    expect(repo.saveCount, 1);
    expect(await serverText(), '');
  });

  testWidgets('sem reconhecedor (Linux/Windows): não reconhece nem mexe no texto do servidor', (t) async {
    final p = await repo.addPage('n1');
    repo.setRecognizedText(p.id, 'texto do celular');
    final c = make(noRecognizer: true);
    unawaited(c.start());
    await settle(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 10));
    expect(repo.saveCount, 1);
    expect(await serverText(), 'texto do celular');
  });

  testWidgets('NoopInkRecognizer (modelo nunca pronto) também deixa o texto do servidor em paz', (t) async {
    final p = await repo.addPage('n1');
    repo.setRecognizedText(p.id, 'texto do celular');
    final c = make(recognizer: const NoopInkRecognizer());
    unawaited(c.start());
    await settle(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 10));
    expect(await serverText(), 'texto do celular');
    expect(idsOf((await repo.listPages('n1')).first.data), {'s1'});
  });

  testWidgets('modelo ausente: não quebra, não reconhece, a tinta salva', (t) async {
    rec.ready = false;
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 10));
    expect(rec.calls, isEmpty);
    expect(repo.saveCount, 1);
    expect(c.status, SaveStatus.saved);
  });

  testWidgets('falha ao consultar o modelo (canal indisponível) não vira erro solto', (t) async {
    rec.throwOnReady = true;
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 10));
    expect(rec.calls, isEmpty);
    expect(c.status, SaveStatus.saved);
    expect(pendingFlags.last, isFalse);
  });

  testWidgets('página que já veio do servidor com texto não é reconhecida de novo ao abrir', (t) async {
    final p = await repo.addPage('n1');
    await repo.savePage(p.copyWith(data: enc(['a']), recognizedText: 'já tinha', withRecognizedText: true));
    final c = make();
    unawaited(c.start());
    await settle(t);
    await elapse(t, const Duration(seconds: 10));
    expect(rec.calls, isEmpty);
    expect(await serverText(), 'já tinha');
    // "Copiar texto da página" usa o texto do servidor até haver uma transcrição local.
    expect(c.transcriptOf(c.currentPages.single.id), isNull);
    expect(c.recognizedTextOf(c.currentPages.single.id), 'já tinha');
    expect(c.recognizedTextOf('não-existe'), '');
  });

  testWidgets('editar o texto de outra página não altera as demais', (t) async {
    await repo.addPage('n1');
    await repo.addPage('n1');
    final c = make();
    unawaited(c.start());
    await settle(t);
    final second = c.currentPages[1].id;
    c.updatePage(second, docOf(['x']));
    await elapse(t, const Duration(seconds: 5));
    final pages = await repo.listPages('n1');
    expect(pages[0].recognizedText, '');
    expect(pages[1].recognizedText, 'texto 1');
  });

  testWidgets('traço novo durante o reconhecimento: resultado velho é descartado e o novo vale', (t) async {
    rec.gate = Completer<void>();
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 4)); // reconhecimento em andamento (preso)
    expect(rec.calls, hasLength(1));
    c.updatePage(pageId(c), docOf(['s1', 's2', 's3']));
    final gate = rec.gate!;
    rec.gate = null;
    gate.complete();
    await settle(t);
    expect(await serverText(), '', reason: 'texto de tinta que já mudou não é gravado');
    await elapse(t, const Duration(seconds: 4));
    expect(await serverText(), 'texto 3');
  });

  testWidgets('conflito com outro aparelho: vale o texto do documento mesclado, transcrito de novo', (t) async {
    final base = await repo.addPage('n1');
    final ctl = ControlledRepo(repo)..liveRealtime = false;
    final c = make(useRepo: ctl);
    unawaited(c.start());
    await settle(t);
    // O outro aparelho grava antes (o realtime desta tela está atrasado).
    await repo.savePage(base.copyWith(data: enc(['x1']), recognizedText: 'do outro', withRecognizedText: true));
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 12));
    final page = (await repo.listPages('n1')).single;
    expect(idsOf(page.data), {'x1', 's1'});
    expect(page.recognizedText, 'texto 2', reason: 'transcrição da página mesclada (2 traços), não "texto 1" nem "do outro"');
  });

  testWidgets('outro aparelho grava (sem tinta nova) bem na hora do envio do texto: o texto não se perde', (t) async {
    final base = await repo.addPage('n1');
    final ctl = ControlledRepo(repo);
    final c = make(useRepo: ctl);
    unawaited(c.start());
    await settle(t);
    var bumped = false;
    ctl.beforeSave = (page) async {
      if (page.withRecognizedText && !bumped) {
        bumped = true; // o outro aparelho regrava a mesma tinta: versão sobe, nada novo
        final cur = (await repo.listPages('n1')).single;
        await repo.savePage(cur.copyWith(data: page.data));
      }
    };
    c.updatePage(base.id, docOf(['s1']));
    await elapse(t, const Duration(seconds: 12));
    expect(bumped, isTrue);
    expect(await serverText(), 'texto 1');
  });

  testWidgets('reconhecimento sem resultado em página com tinta não apaga o texto que já existia', (t) async {
    final p = await repo.addPage('n1');
    repo.setRecognizedText(p.id, 'texto antigo');
    final failing = FakeInkRecognizer(resolve: (_) => const []);
    final c = make(recognizer: failing);
    unawaited(c.start());
    await settle(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 6));
    expect(failing.calls, hasLength(1));
    expect(await serverText(), 'texto antigo');
  });

  testWidgets('página esvaziada limpa o texto reconhecido', (t) async {
    final p = await repo.addPage('n1');
    await repo.savePage(p.copyWith(data: enc(['a']), recognizedText: 'sobrou', withRecognizedText: true));
    final c = make();
    unawaited(c.start());
    await settle(t);
    c.updatePage(pageId(c), docOf(['a']).without(['a']));
    await elapse(t, const Duration(seconds: 6));
    expect(await serverText(), '');
  });

  testWidgets('erro no reconhecedor não derruba nada e não fica tentando em laço', (t) async {
    rec.throwOnRecognize = true;
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 30));
    expect(rec.calls, hasLength(1));
    expect(c.status, SaveStatus.saved);
    expect(idsOf((await repo.listPages('n1')).first.data), {'s1'});
  });

  testWidgets('recognizeNow (ao sair) reconhece na hora, sem esperar os 3 s', (t) async {
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(milliseconds: 200));
    unawaited(c.recognizeNow());
    await settle(t);
    await elapse(t, const Duration(milliseconds: 200));
    expect(rec.calls, hasLength(1));
    expect(await serverText(), 'texto 1');
  });

  testWidgets('o controller continua "pendente" até o texto chegar ao servidor', (t) async {
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(milliseconds: 1700)); // tinta salva, texto ainda não
    expect(c.status, SaveStatus.saved);
    expect(pendingFlags.last, isTrue, reason: 'senão o provider descarta o controller antes da transcrição');
    await elapse(t, const Duration(seconds: 3));
    expect(await serverText(), 'texto 1');
    expect(pendingFlags.last, isFalse);
  });

  testWidgets('duplicar uma página leva o texto reconhecido junto', (t) async {
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(seconds: 5));
    c.duplicatePage(pageId(c));
    await elapse(t, const Duration(seconds: 6));
    final pages = await repo.listPages('n1');
    expect(pages, hasLength(2));
    expect(pages.map((p) => p.recognizedText), ['texto 1', 'texto 1']);
  });

  testWidgets('texto novo de outro aparelho (mesma tinta) não dispara reconhecimento nem altera a página', (t) async {
    final p = await repo.addPage('n1');
    await repo.savePage(p.copyWith(data: enc(['a'])));
    final c = make();
    unawaited(c.start());
    await settle(t);
    repo.setRecognizedText(p.id, 'texto remoto');
    await elapse(t, const Duration(seconds: 10));
    expect(rec.calls, isEmpty);
    expect(idsOf(encodePage(c.currentPages.first.doc)), {'a'});
  });

  testWidgets('dispose cancela o reconhecimento pendente', (t) async {
    final c = await started(t);
    c.updatePage(pageId(c), docOf(['s1']));
    await elapse(t, const Duration(milliseconds: 1700));
    c.dispose();
    await elapse(t, const Duration(seconds: 10));
    expect(rec.calls, isEmpty);
  });
}
