// Benchmark de uma sessão de escrita realista no Caderno (S Pen a ~240 Hz).
//
// Mede, na thread principal (a única que o `flutter test` enxerga), o custo
// síncrono de cada etapa: eventos de movimento, fim de traço (`onEdit` ->
// `updatePage`), quadros (build + layout + paint), gravação da cópia local
// (`encodePage` + `jsonEncode`), envio ao servidor e eco do realtime
// (`decodePage` + `merge`). Também conta reconstruções de widgets e repinturas
// de camadas por fase.
//
// Rodar:  flutter test test/notebook/perf/writing_session_perf_test.dart
// O que passa de 8 ms por quadro é travamento a 120 Hz (a 60 Hz o limite é 16 ms).
//
// Os números vêm do `flutter test` (Dart JIT em modo debug, no PC): servem para
// comparar ANTES x DEPOIS e achar o que é desproporcional, não para prever o
// tempo exato no tablet.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/data/notebook_page.dart';
import 'package:organizacional/notebook/state/notebook_controller.dart';
import 'package:organizacional/notebook/state/notebook_providers.dart';
import 'package:organizacional/notebook/state/notebook_pending_store.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../../helpers.dart';
import '../core/test_support.dart';
import '../data/fake_image_store.dart';

const double kFrameBudgetMs = 8.0; // 120 Hz

// ---------------------------------------------------------------------------
// Instrumentação
// ---------------------------------------------------------------------------

/// Repositório em memória que mede o que seria feito **no servidor** (merge,
/// versão…) para descontar da thread principal, conta os eventos do realtime
/// entregues ao controller e, como o Supabase, "toca" `notes.updated_at` a
/// cada save.
class InstrumentedRepo extends MemoryNotebookRepository {
  InstrumentedRepo({this.notes, this.touchInterval, this.now});

  final MemoryRepository? notes;

  /// null: toca `notes.updated_at` a cada save (o comportamento antigo do Supabase).
  /// Com valor: no máximo uma vez por intervalo, como o `SupabaseNotebookRepository` agora.
  final Duration? touchInterval;
  final DateTime Function()? now;
  DateTime? _lastTouch;
  final Stopwatch _sw = Stopwatch()..start();

  /// Tempo (µs) gasto dentro do "servidor" (descontado da UI).
  int serverMicros = 0;
  int saves = 0;
  int echoes = 0;
  int touches = 0;

  @override
  Stream<List<NotebookPage>> watchPages(String noteId) =>
      super.watchPages(noteId).map((l) {
        echoes++;
        return l;
      });

  @override
  Future<NotebookPage> savePage(NotebookPage page) async {
    final t0 = _sw.elapsedMicroseconds;
    final r = await super.savePage(page);
    serverMicros += _sw.elapsedMicroseconds - t0;
    saves++;
    final n = notes;
    final t = now?.call();
    final due = touchInterval == null || _lastTouch == null || t!.difference(_lastTouch!) >= touchInterval!;
    if (n != null && due) {
      _lastTouch = t;
      final all = await n.watchNotes().first;
      final note = all.where((x) => x.id == page.noteId).firstOrNull;
      if (note != null) {
        touches++;
        await n.upsertNote(Note(
          id: note.id,
          title: note.title,
          kind: note.kind,
          updatedAt: DateTime.now(),
        ));
      }
    }
    return r;
  }
}

/// Modela a codificação como o app a faz: montar o JSON (rápido, reaproveita o JSON
/// dos traços) conta na thread principal; a compressão (utf8 + gzip + base64) roda
/// em outro isolate no app, então o tempo dela é **descontado** aqui. (Num teste com
/// relógio falso um isolate de verdade nunca completaria.) O custo de despachar o
/// isolate (~0,5 ms, medido à parte) não entra.
class OffThreadEncoder {
  final Stopwatch _sw = Stopwatch()..start();
  int excludedMicros = 0;
  int calls = 0;

  Future<String> encode(PageDoc doc) async {
    calls++;
    final json = pageJson(doc);
    if (json.length <= pageInlineLimit) return compressPageJson(json);
    final t0 = _sw.elapsedMicroseconds;
    final out = compressPageJson(json);
    excludedMicros += _sw.elapsedMicroseconds - t0;
    return out;
  }
}

/// Armazenamento local que conta gravações. O `jsonEncode` do JSON grande roda em
/// outro isolate no app (`SharedPreferencesNotebookPendingStore`), então o tempo
/// dele é descontado aqui, como o do "servidor".
class InstrumentedStore extends MemoryNotebookPendingStore {
  int saves = 0;
  int clears = 0;
  int cacheSaves = 0;
  int excludedMicros = 0;
  final Stopwatch _sw = Stopwatch()..start();

  @override
  Future<void> save(String noteId, Map<String, Object?> json) {
    saves++;
    final t0 = _sw.elapsedMicroseconds;
    final f = super.save(noteId, json);
    excludedMicros += _sw.elapsedMicroseconds - t0;
    return f;
  }

  @override
  Future<void> clear(String noteId) {
    clears++;
    return super.clear(noteId);
  }

  @override
  Future<void> savePagesCache(String noteId, Map<String, Object?> json) {
    cacheSaves++;
    return super.savePagesCache(noteId, json);
  }
}

/// Sessão que repassa ao controller real e conta/mede.
class SpySession implements NotebookSession {
  SpySession(this.inner);
  final NotebookController inner;
  int updates = 0;
  int updateMicros = 0;
  int pageEmissions = 0;
  final Stopwatch _sw = Stopwatch()..start();

  @override
  Stream<List<NotebookPageState>> get pages => inner.pages.map((l) {
        pageEmissions++;
        return l;
      });

  @override
  SaveStatus get status => inner.status;
  @override
  Stream<SaveStatus> get statusChanges => inner.statusChanges;
  @override
  NotebookImageStore get images => inner.images;

  @override
  void updatePage(String id, PageDoc doc) {
    final t0 = _sw.elapsedMicroseconds;
    inner.updatePage(id, doc);
    updateMicros += _sw.elapsedMicroseconds - t0;
    updates++;
  }

  @override
  void addPage({PageBackground background = PageBackground.lined, PageDoc? initial}) =>
      inner.addPage(background: background, initial: initial);
  @override
  void deletePage(String id) => inner.deletePage(id);
  @override
  void duplicatePage(String id) => inner.duplicatePage(id);
  @override
  void setBackground(String id, PageBackground background) => inner.setBackground(id, background);
}

class Series {
  final List<int> micros = [];
  void add(int us) => micros.add(us);
  int get n => micros.length;
  double get meanMs => n == 0 ? 0 : micros.reduce((a, b) => a + b) / n / 1000;
  double pMs(double p) {
    if (n == 0) return 0;
    final s = [...micros]..sort();
    return s[math.min(s.length - 1, (s.length * p).floor())] / 1000;
  }

  double get maxMs => n == 0 ? 0 : micros.reduce(math.max) / 1000;
  int get over => micros.where((u) => u / 1000 > kFrameBudgetMs).length;

  String line(String label) =>
      '${label.padRight(34)} n=${n.toString().padLeft(5)}  média=${meanMs.toStringAsFixed(2).padLeft(7)}ms  '
      'p95=${pMs(0.95).toStringAsFixed(2).padLeft(7)}ms  máx=${maxMs.toStringAsFixed(2).padLeft(7)}ms  '
      '>${kFrameBudgetMs.toStringAsFixed(0)}ms: $over';
}

class Counters {
  /// fase -> tipo de widget -> reconstruções
  final Map<String, Map<String, int>> rebuilds = {};

  /// fase -> pintor -> repinturas
  final Map<String, Map<String, int>> paints = {};
  String phase = 'idle';

  void install() {
    debugOnRebuildDirtyWidget = (e, _) {
      final m = rebuilds.putIfAbsent(phase, () => {});
      final k = e.widget.runtimeType.toString();
      m[k] = (m[k] ?? 0) + 1;
    };
    debugOnProfilePaint = (ro) {
      if (ro is RenderCustomPaint) {
        final k = (ro.painter ?? ro.foregroundPainter).runtimeType.toString();
        final m = paints.putIfAbsent(phase, () => {});
        m[k] = (m[k] ?? 0) + 1;
      }
    };
  }

  void uninstall() {
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
  }

  int totalRebuilds(String phase) => (rebuilds[phase] ?? {}).values.fold(0, (a, b) => a + b);

  String summary(String phase, int units, String unitName) {
    final r = rebuilds[phase] ?? {};
    final p = paints[phase] ?? {};
    final top = (r.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(8);
    final sb = StringBuffer();
    sb.writeln(
      '  fase "$phase": ${totalRebuilds(phase)} reconstruções de widgets em $units $unitName '
      '(${(totalRebuilds(phase) / math.max(units, 1)).toStringAsFixed(1)}/$unitName)',
    );
    sb.writeln('    mais reconstruídos: ${top.map((e) => '${e.key}×${e.value}').join(', ')}');
    final screens = RegExp(r'(Screen|Route|Shell|Tree|Toolbar|Thumbnail|Tile)$');
    final w = [for (final e in r.entries) if (screens.hasMatch(e.key)) '${e.key}×${e.value}'];
    if (w.isNotEmpty) sb.writeln('    telas: ${w.join(', ')}');
    final tp = (p.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(8);
    sb.writeln('    repinturas de CustomPaint: ${tp.map((e) => '${e.key}×${e.value}').join(', ')}');
    return sb.toString();
  }
}

// ---------------------------------------------------------------------------
// Caneta sintética
// ---------------------------------------------------------------------------

class Pen {
  Pen(this.tester, this.id);
  final WidgetTester tester;
  final int id;
  Offset _at = Offset.zero;
  bool _added = false;

  void _send(PointerEvent e) => tester.binding.handlePointerEvent(e);

  void down(Offset at) {
    if (!_added) {
      _added = true;
      _send(PointerAddedEvent(pointer: id, kind: PointerDeviceKind.stylus, position: at));
    }
    _at = at;
    _send(PointerDownEvent(
      pointer: id,
      kind: PointerDeviceKind.stylus,
      position: at,
      buttons: kPrimaryButton,
      pressure: 0.4,
      pressureMin: 0,
      pressureMax: 1,
    ));
  }

  void move(Offset to, double pressure) {
    _send(PointerMoveEvent(
      pointer: id,
      kind: PointerDeviceKind.stylus,
      position: to,
      delta: to - _at,
      buttons: kPrimaryButton,
      pressure: pressure,
      pressureMin: 0,
      pressureMax: 1,
    ));
    _at = to;
  }

  void up() {
    _send(PointerUpEvent(pointer: id, kind: PointerDeviceKind.stylus, position: _at));
  }
}

/// Pontos (em unidades de página) de uma "letra" de [n] pontos, passos de 1–3 un.
List<Offset> letterPoints(int letter, int n, Offset origin, math.Random r) {
  final pts = <Offset>[];
  var heading = letter * 1.1;
  var x = origin.dx, y = origin.dy;
  for (var i = 0; i < n; i++) {
    pts.add(Offset(x, y));
    heading += math.sin(i * 0.3 + letter) * 0.35 + (r.nextDouble() - 0.5) * 0.1;
    final step = 1.0 + 2.0 * (0.5 + 0.5 * math.sin(i * 0.17));
    x += math.cos(heading) * step;
    y += math.sin(heading) * step;
  }
  return pts;
}

// ---------------------------------------------------------------------------
// Preparação
// ---------------------------------------------------------------------------

PageDoc docWith(int strokes, int seed) {
  final r = math.Random(seed);
  return PageDoc.empty.withStrokes([for (var i = 0; i < strokes; i++) handwritingStroke(newInkId(), r)]);
}

Future<String> seedNotebook(InstrumentedRepo repo, String noteId, int strokes) async {
  final p = await repo.addPage(noteId);
  if (strokes > 0) {
    await repo.savePage(p.copyWith(data: encodePage(docWith(strokes, 7))));
  }
  repo.saves = 0;
  repo.serverMicros = 0;
  repo.echoes = 0;
  repo.touches = 0;
  repo.touchedNoteIds.clear();
  return p.id;
}

final _theme = buildOrgTheme(orgThemes.first, googleFonts: false);

/// Roteiro: [words] vezes "Lucas", cada letra um traço de 40 a 120 pontos.
/// Eventos a ~240 Hz (4,17 ms), um quadro a cada 2 eventos (120 Hz).
/// Entre palavras há uma pausa de [wordGapMs]; uma pausa longa no meio deixa
/// o salvamento (1,5 s) e o eco do realtime acontecerem.
class SessionResult {
  final Series moveEvent = Series();
  final Series downEvent = Series();
  final Series upEvent = Series();
  final Series updateOnly = Series();
  final Series frameDuringStroke = Series();
  final Series frameAfterUp = Series();
  final Series frameIdle = Series();
  final Series frameWithPersist = Series();
  final Series frameWithFlush = Series();
  final Series frameWithEcho = Series();
  final Series frameAny = Series();
  int strokes = 0;
  int moves = 0;
}

Future<SessionResult> writeSession(
  WidgetTester tester, {
  required Counters counters,
  required InstrumentedRepo repo,
  required InstrumentedStore store,
  required SpySession spy,
  OffThreadEncoder? offThread,
  int words = 6,
  int longPauseAfterWord = 3,
  Finder? pageFinder,
}) async {
  final res = SessionResult();
  final pen = Pen(tester, 7001);
  final sw = Stopwatch()..start();
  final rect = tester.getRect(pageFinder ?? find.byKey(const ValueKey('nb-page-0')));
  Offset g(Offset u) => rect.topLeft + Offset(u.dx / pageWidth * rect.width, u.dy / pageHeight * rect.height);
  final rnd = math.Random(3);

  Future<void> frame(Series target, {String? phase}) async {
    if (phase != null) counters.phase = phase;
    final saves0 = store.saves, flush0 = repo.saves, echo0 = repo.echoes;
    int excluded() => repo.serverMicros + (offThread == null ? 0 : store.excludedMicros + offThread.excludedMicros);
    final ex0 = excluded();
    final t0 = sw.elapsedMicroseconds;
    await tester.pump(const Duration(microseconds: 8333));
    final cost = sw.elapsedMicroseconds - t0 - (excluded() - ex0);
    target.add(cost);
    res.frameAny.add(cost);
    if (store.saves > saves0) res.frameWithPersist.add(cost);
    if (repo.saves > flush0) res.frameWithFlush.add(cost);
    if (repo.echoes > echo0) res.frameWithEcho.add(cost);
  }

  Future<void> idle(int ms) async {
    counters.phase = 'idle';
    var left = ms;
    while (left > 0) {
      await frame(res.frameIdle);
      left -= 8;
    }
  }

  var letterIdx = 0;
  for (var w = 0; w < words; w++) {
    var x = 100.0 + (w % 3) * 280.0;
    final y = 200.0 + (w ~/ 3) * 90.0 + w * 3;
    for (var l = 0; l < 5; l++) {
      final n = 40 + ((letterIdx * 37) % 81); // 40..120 pontos
      letterIdx++;
      final pts = letterPoints(l, n, Offset(x, y), rnd);
      x += 45;
      counters.phase = 'traço';
      var sw0 = sw.elapsedMicroseconds;
      pen.down(g(pts.first));
      res.downEvent.add(sw.elapsedMicroseconds - sw0);
      for (var i = 1; i < pts.length; i++) {
        sw0 = sw.elapsedMicroseconds;
        pen.move(g(pts[i]), 0.3 + 0.4 * math.sin(i * 0.2).abs());
        res.moveEvent.add(sw.elapsedMicroseconds - sw0);
        res.moves++;
        if (i.isOdd) await frame(res.frameDuringStroke, phase: 'traço');
      }
      counters.phase = 'fim';
      sw0 = sw.elapsedMicroseconds;
      final u0 = spy.updateMicros;
      pen.up();
      res.upEvent.add(sw.elapsedMicroseconds - sw0);
      res.updateOnly.add(spy.updateMicros - u0);
      res.strokes++;
      await frame(res.frameAfterUp, phase: 'fim');
      await frame(res.frameAfterUp, phase: 'fim');
      await idle(60); // caneta no ar entre letras
    }
    await idle(w == longPauseAfterWord ? 2200 : 380);
  }
  await idle(3200); // deixa salvar e ecoar
  return res;
}

void report(String title, SessionResult r, Counters c, InstrumentedRepo repo, InstrumentedStore store, SpySession spy) {
  final b = StringBuffer()
    ..writeln('')
    ..writeln('=== $title ===')
    ..writeln(r.moveEvent.line('evento de movimento (handler)'))
    ..writeln(r.downEvent.line('caneta encosta (handler)'))
    ..writeln(r.upEvent.line('caneta levanta (handler+onEdit)'))
    ..writeln(r.updateOnly.line('  └ só updatePage do controller'))
    ..writeln(r.frameDuringStroke.line('quadro durante o traço'))
    ..writeln(r.frameAfterUp.line('quadro logo após levantar'))
    ..writeln(r.frameIdle.line('quadro parado/pausa'))
    ..writeln(r.frameWithPersist.line('quadro que gravou cópia local'))
    ..writeln(r.frameWithFlush.line('quadro que enviou ao servidor'))
    ..writeln(r.frameWithEcho.line('quadro que recebeu eco realtime'))
    ..writeln(r.frameAny.line('TODOS os quadros'))
    ..writeln(
      '  traços=${r.strokes} eventos=${r.moves} gravações locais=${store.saves} '
      'saves no servidor=${repo.saves} ecos=${repo.echoes} toques em notes.updated_at=${repo.touches} '
      'emissões de pages=${spy.pageEmissions}',
    )
    ..write(c.summary('traço', r.moves, 'evento'))
    ..write(c.summary('fim', r.strokes, 'traço'))
    ..write(c.summary('idle', r.strokes, 'traço'));
  // ignore: avoid_print
  print(b);
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

void main() {
  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
  });

  // Custo bruto de cada etapa por tamanho de página (referência).
  test('referência: encode / decode / merge por tamanho de página', () {
    final b = StringBuffer('\n=== custo bruto por etapa (thread única) ===\n');
    for (final n in [50, 500, 2000]) {
      final doc = docWith(n, 1);
      final sw = Stopwatch()..start();
      final enc = encodePage(doc);
      final tEnc = sw.elapsedMicroseconds / 1000;
      sw.reset();
      final back = decodePage(enc);
      final tDec = sw.elapsedMicroseconds / 1000;
      sw.reset();
      final merged = doc.merge(back);
      final tMerge = sw.elapsedMicroseconds / 1000;
      sw.reset();
      final eq = merged == doc;
      final tEq = sw.elapsedMicroseconds / 1000;
      b.writeln(
        '$n traços: encode=${tEnc.toStringAsFixed(1)}ms decode=${tDec.toStringAsFixed(1)}ms '
        'merge=${tMerge.toStringAsFixed(1)}ms ==(merged,doc)=${tEq.toStringAsFixed(1)}ms eq=$eq '
        'texto=${(enc.length / 1024).toStringAsFixed(0)}KB',
      );
    }
    // ignore: avoid_print
    print(b);
  });

  for (final n in [50, 500, 2000]) {
    testWidgets('sessão de escrita sobre NotebookScreen real: página com $n traços', (tester) async {
      tester.view.physicalSize = const Size(800, 1280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = InstrumentedRepo();
      final store = InstrumentedStore();
      await seedNotebook(repo, 'n1', n);
      final offThread = OffThreadEncoder();
      final controller = NotebookController(
        noteId: 'n1',
        repo: repo,
        images: FakeNotebookImageStore(),
        pending: store,
        encoder: offThread.encode,
      );
      addTearDown(controller.dispose);
      final spy = SpySession(controller);
      unawaited(controller.start());
      await tester.pumpWidget(MaterialApp(
        theme: _theme,
        home: NotebookScreen(noteId: 'n1', session: spy, title: 'Caderno'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('nb-page-0')), findsOneWidget);
      // aquece (JIT) com um traço e zera os contadores
      store.saves = 0;
      repo.saves = 0;
      repo.echoes = 0;

      final counters = Counters()..install();
      final r = await writeSession(tester, counters: counters, repo: repo, store: store, spy: spy, offThread: offThread);
      counters.uninstall();
      report('NotebookScreen + NotebookController, página com $n traços', r, counters, repo, store, spy);
      // ignore: avoid_print
      print('  codificações pedidas ao encoder=${offThread.calls}; compressão fora da thread principal=${(offThread.excludedMicros / 1000).toStringAsFixed(0)}ms (descontada acima)');
      // a tinta escrita chegou ao servidor
      await tester.pump(const Duration(seconds: 12));
      final saved = decodePage((await repo.listPages('n1')).single.data);
      expect(saved.strokes.length, n + r.strokes);
    }, timeout: const Timeout(Duration(minutes: 8)));
  }

  testWidgets('app completo: Notas por baixo da rota /caderno (notes.updated_at tocado a cada save)', (tester) async {
    final notes = MemoryRepository();
    await notes.upsertNote(const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook));
    for (var i = 0; i < 25; i++) {
      await notes.upsertNote(Note(id: 'x$i', title: 'Nota $i', body: 'texto ' * 50));
    }
    final repo = InstrumentedRepo(
      notes: notes,
      touchInterval: const Duration(seconds: 60),
      now: () => tester.binding.clock.now(),
    );
    final store = InstrumentedStore();
    final offThread = OffThreadEncoder();
    await seedNotebook(repo, 'c1', 50);
    await pumpApp(
      tester,
      notes,
      notebookRepo: repo,
      size: const Size(800, 1280),
      location: '/notas',
      overrides: [
        notebookPendingStoreProvider.overrideWithValue(store),
        notebookPageEncoderProvider.overrideWithValue(offThread.encode),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('tree-note-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notebook-screen')), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('notebook-screen'))));
    final controller = container.read(notebookControllerProvider('c1'));
    final spy = SpySession(controller);
    store.saves = 0;
    repo.saves = 0;
    repo.echoes = 0;
    repo.touches = 0;
    final counters = Counters()..install();
    final r = await writeSession(tester, counters: counters, repo: repo, store: store, spy: spy, offThread: offThread);
    counters.uninstall();
    report('App completo (Notas por baixo), caderno com 50 traços', r, counters, repo, store, spy);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
