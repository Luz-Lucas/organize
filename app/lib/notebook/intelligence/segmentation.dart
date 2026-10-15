/// Segmentação da tinta em linhas e palavras (Dart puro, determinística: a
/// mesma entrada dá sempre a mesma saída, não importa a ordem em que o documento
/// guarda os traços, porque tudo é ordenado pelo id).
///
/// Passos:
///  1. Candidatos: traços de caneta/lápis (nada de marca-texto) pequenos o
///     bastante para serem escrita — mancha de palma, círculos e desenhos
///     grandes ficam de fora — e que não sejam "réguas" (sublinhado longo e fino).
///  2. Enfeites: pingo de i, barra de t, acento e cedilha (traços bem menores,
///     empilhados em cima de uma letra) saem da varredura e ficam para o passo 4.
///  3. Os traços "de corpo" são varridos da esquerda para a direita e cada um
///     entra na linha cuja reta prevista (regressão do centro dos traços dela)
///     passa mais perto, dentro de uma tolerância proporcional à altura-x. Assim
///     linhas inclinadas de 3–10° não se misturam com as vizinhas, e
///     ascendentes/descendentes não "vazam" para a linha de baixo.
///  4. Os enfeites grudam na linha da letra que enfeitam (ou, sem letra, na linha
///     cuja baseline os deixa entre -0,5 e 2,3 alturas-x acima dela).
///  5. Em cada linha: altura-x (percentil 35 das alturas dos traços de corpo),
///     baseline por regressão robusta das bases (descendentes são descartados
///     como atípicos) e palavras separadas por lacuna horizontal de tinta
///     > 0,6× a altura-x.
library;

import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';
import 'ink_types.dart';

/// Traço mais alto que isto (unidades de página) não é escrita: palma, círculo,
/// moldura, desenho. Uma letra de forma de 1,5 cm tem ~70.
const double kMaxTextStrokeHeight = 110;

/// Traço mais largo que isto não é escrita (uma palavra cursiva num traço só
/// raramente passa de 1/3 da página).
const double kMaxTextStrokeWidth = 320;

/// Lacuna entre palavras = esta fração da altura-x da linha.
const double kWordGapFactor = 0.6;

/// Inclinação máxima aceita para uma baseline (≈ 19°).
const double _maxSlope = 0.35;

final Expando<double> _xhOf = Expando<double>('xHeight');

/// Altura-x estimada da linha (a mesma usada na segmentação). Para linhas
/// montadas por fora de [segmentLines], estima de novo a partir de [doc].
double lineXHeight(PageDoc doc, InkLine line) {
  final cached = _xhOf[line];
  if (cached != null) return cached;
  final hs = <double>[];
  for (final id in line.strokeIds) {
    final s = doc.strokeById(id);
    if (s != null) hs.add(_pointBox(s).height);
  }
  return _xHeightFrom(hs, fallback: math.max(6.0, line.bounds.height / 2.2));
}

/// y da baseline da [line] na posição [x].
double lineBaselineAt(InkLine line, double x) =>
    line.baselineY + math.tan(line.angle) * (x - line.bounds.left);

/// Retângulo dos pontos do traço, sem a meia espessura.
Rect _pointBox(Stroke s) => s.bounds.deflate(s.width / 2);

double _xHeightFrom(List<double> heights, {required double fallback}) {
  if (heights.isEmpty) return fallback;
  final sorted = [...heights]..sort();
  final median = sorted[sorted.length ~/ 2];
  // descarta pingos, barras e acentos (muito menores que a mediana)
  final body = [for (final h in sorted) if (h >= 0.5 * median) h];
  if (body.isEmpty) return fallback;
  final v = body[((body.length - 1) * 0.35).floor()];
  return math.max(v, 1.0);
}

class _C {
  _C(this.stroke, this.order, Rect b)
    : l = b.left,
      r = b.right,
      t = b.top,
      b = b.bottom,
      cx = (b.left + b.right) / 2,
      cy = (b.top + b.bottom) / 2;

  final Stroke stroke;
  final int order; // posição em doc.strokes
  final double l, r, t, b, cx, cy;

  /// Traço maior sobre o qual este (acento, pingo) está empilhado, se houver.
  _C? base;

  /// Linha em que o traço acabou entrando.
  _Cluster? cluster;
  double get w => r - l;
  double get h => b - t;
}

class _Cluster {
  _Cluster(this.index, this.pageXh, _C first) {
    add(first);
  }

  final int index;
  final double pageXh;

  /// Traços de corpo (entram na regressão e na média de altura).
  final List<_C> members = [];

  /// Traços pequenos grudados (pingos, barras, acentos, pontuação).
  final List<_C> extras = [];
  double right = -double.infinity;
  double reachX = -double.infinity; // right + maxGap (poda da varredura)
  double lastCx = 0, lastCy = 0;
  double sumH = 0;
  double meanH = 0;
  int stamp = 0; // marca de consulta do índice espacial
  double reachBase = 0; // alcance vertical da rejeição barata (varredura)
  // regressão cy ~ cx dos traços de corpo
  double n = 0, sx = 0, sy = 0, sxx = 0, sxy = 0;
  double minCx = double.infinity, maxCx = -double.infinity;
  _C? last;

  /// Altura de referência da linha para tolerâncias: com poucos traços, a média
  /// deles limitada a 1,2× a altura-x da página (um 'L' ou 'l' alto como
  /// primeiro traço dobrava a tolerância e a linha engolia a vizinha); depois,
  /// a altura-x robusta (percentil 35) dos próprios traços.
  double unit(double pageXh) {
    if (members.length < 3) {
      return math.min(meanH, 1.2 * pageXh);
    }
    // recalcula com poucos traços a cada novo e, depois, só quando a linha
    // cresceu 25 % (ordenar as alturas a cada traço custava caro)
    if (_unitAt < 0 || members.length >= _unitAt + math.max(1, _unitAt ~/ 4)) {
      // (limitada a 1,6× a da página: "lillian" só tem letras altas e o
      // percentil 35 dava duas alturas-x)
      _unit = math.min(
        _xHeightFrom([for (final m in members) m.h], fallback: pageXh),
        1.6 * pageXh,
      );
      _unitAt = members.length;
    }
    return _unit;
  }

  double _unit = 0;
  int _unitAt = -1;

  Rect? _box;
  _Fit? _fit;

  /// Altura-x e baseline estimadas só com os traços de corpo (calculada na
  /// primeira vez que alguém pede, depois que a varredura terminou).
  _Fit get fit => _fit ??= _fitBody(members);

  List<_C> get everyone => extras.isEmpty ? members : [...members, ...extras];

  /// Caixa de todos os traços (em cache; invalidada quando entra um novo).
  Rect get box => _box ??= () {
    var l = double.infinity, r = -double.infinity, t = double.infinity, b = -double.infinity;
    for (final list in [members, extras]) {
      for (final m in list) {
        l = math.min(l, m.l);
        r = math.max(r, m.r);
        t = math.min(t, m.t);
        b = math.max(b, m.b);
      }
    }
    return Rect.fromLTRB(l, t, r, b);
  }();

  /// Traço pequeno: entra na linha, fora da regressão e da média.
  void addSmall(_C c) {
    extras.add(c);
    c.cluster = this;
    _box = null;
  }

  void add(_C c) {
    members.add(c);
    c.cluster = this;
    _box = null;
    right = math.max(right, c.r);
    sumH += c.h;
    lastCx = c.cx;
    lastCy = c.cy;
    n++;
    sx += c.cx;
    sy += c.cy;
    sxx += c.cx * c.cx;
    sxy += c.cx * c.cy;
    minCx = math.min(minCx, c.cx);
    maxCx = math.max(maxCx, c.cx);
    last = c;
    meanH = sumH / members.length;
    reachBase = 0.9 * math.max(pageXh, meanH) + 2 * meanH;
    // lacuna máxima dentro da linha: larga para linhas já estabelecidas (um
    // ∧ abre até 260 de espaço e a linha continua uma só), curta enquanto a
    // linha tem poucos traços (evita juntar rabiscos soltos)
    reachX = right + (n >= 4 ? math.max(12 * meanH, 300.0) : math.max(5 * meanH, 40.0));
  }

  double predict(double x) {
    if (n >= 4 && (maxCx - minCx) >= 3 * math.max(meanH, 4.0)) {
      final den = n * sxx - sx * sx;
      if (den.abs() > 1e-9) {
        final slope = ((n * sxy - sx * sy) / den).clamp(-_maxSlope, _maxSlope);
        final mx = sx / n, my = sy / n;
        return my + slope * (x - mx);
      }
    }
    return n >= 4 ? sy / n : last!.cy;
  }

  /// Folga extra para a previsão enquanto a inclinação da linha ainda é
  /// desconhecida (poucos traços ou trecho curto): até 10° de inclinação
  /// (tan ≈ 0,18) a partir do centro do que já se viu.
  double slack(double x, double unit) {
    if (n >= 4 && (maxCx - minCx) >= 3 * math.max(meanH, 4.0)) return 0;
    // (satura a 4 alturas-x de distância: longe dali o palpite não vale mais)
    return 0.18 * math.min((x - sx / n).abs(), 4 * unit);
  }
}

/// Agrupa os traços de [doc] (ou só os de [only]) em linhas e palavras.
/// Linhas de cima para baixo; palavras da esquerda para a direita.
List<InkLine> segmentLines(PageDoc doc, {Set<String>? only}) {
  // 1. candidatos --------------------------------------------------------
  // Ordem canônica = ordem dos ids (criação), para que o resultado não dependa
  // da ordem em que o documento guarda os traços.
  final src = <Stroke>[
    for (final s in doc.strokes)
      if (s.tool != PenTool.highlighter && (only == null || only.contains(s.id))) s,
  ];
  var sorted = true;
  for (var i = 1; i < src.length && sorted; i++) {
    if (src[i - 1].id.compareTo(src[i].id) > 0) sorted = false;
  }
  if (!sorted) src.sort((a, b) => a.id.compareTo(b.id));
  final cands = <_C>[];
  for (var i = 0; i < src.length; i++) {
    final s = src[i];
    final b = _pointBox(s);
    if (b.height > kMaxTextStrokeHeight || b.width > kMaxTextStrokeWidth) continue;
    cands.add(_C(s, i, b));
  }
  if (cands.isEmpty) return const [];

  final hs = [for (final c in cands) c.h]..sort();
  final ref = math.max(hs[((hs.length - 1) * 0.6).floor()], 2.0);

  final body = <_C>[];
  final tiny = <_C>[];
  for (final c in cands) {
    if (c.h < 0.3 * ref && c.w > math.max(4 * ref, 60.0)) continue; // régua
    (c.h < 0.25 * ref ? tiny : body).add(c);
  }
  if (body.isEmpty) {
    body.addAll(tiny);
    tiny.clear();
  }
  if (body.isEmpty) return const [];

  // 2. varredura da esquerda para a direita -----------------------------
  body.sort((a, b) {
    final d = a.cx.compareTo(b.cx);
    return d != 0 ? d : a.order.compareTo(b.order);
  });
  // Acentos e pingos ficam de fora da varredura: um traço bem menor que outro,
  // empilhado em cima dele, é enfeite da letra.
  final deferred = <_C>[];
  final sweepBody = <_C>[];
  _splitStacked(body, tiny, ref, sweepBody, deferred);
  if (sweepBody.isEmpty) {
    sweepBody.addAll(deferred);
    deferred.clear();
  }
  final pageXh = _xHeightFrom([for (final c in sweepBody) c.h], fallback: ref);
  var all = <_Cluster>[];
  _sweep(sweepBody, pageXh, all, deferred);

  // 3. pingos, barras, acentos e pontuação -------------------------------
  final maxDist = 1.5 * ref;
  final index = _ClusterIndex(all, 2.5 * maxDist);
  for (final c in tiny) {
    // (pequeno demais para ser escrita sozinho: sem dono, é descartado)
    (c.base?.cluster ?? _attachSmall(c, index, maxDist, fallbackToNearest: true))?.addSmall(c);
  }
  final leftovers = <_C>[];
  for (final c in deferred) {
    final k = c.base?.cluster ?? _attachSmall(c, index, maxDist, fallbackToNearest: true);
    if (k == null) {
      leftovers.add(c);
    } else {
      k.addSmall(c);
    }
  }
  if (leftovers.isNotEmpty) {
    // texto miúdo numa página de letras grandes (ou o contrário): não achou
    // dono entre as linhas, então forma as suas próprias
    leftovers.sort((a, b) {
      final d = a.cx.compareTo(b.cx);
      return d != 0 ? d : a.order.compareTo(b.order);
    });
    _sweep(leftovers, _xHeightFrom([for (final c in leftovers) c.h], fallback: ref), all, null);
  }

  // 4. clusters-órfãos (um acento ou pingo que ficou longe demais da reta da
  // linha e virou "linha" de 1–3 traços pequenos) vão para a linha grande
  // que fica logo abaixo/ao lado deles.
  final hosts = [for (final k in all) if (k.members.length >= 4) k];
  if (hosts.isNotEmpty && hosts.length < all.length) {
    final hostIndex = _ClusterIndex(hosts, 2.5 * maxDist);
    final merged = <_Cluster>{};
    for (final o in all) {
      if (o.members.length > 3 || o.extras.isNotEmpty) continue;
      final targets = <_Cluster>[];
      var ok = true;
      for (final c in o.members) {
        final t = _attachSmall(
          c,
          hostIndex,
          maxDist,
          fallbackToNearest: false,
          bigger: o.meanH * 1.7,
        );
        if (t == null) {
          ok = false;
          break;
        }
        targets.add(t);
      }
      if (!ok) continue;
      for (var i = 0; i < o.members.length; i++) {
        targets[i].addSmall(o.members[i]);
      }
      merged.add(o);
    }
    if (merged.isNotEmpty) {
      all = [for (final k in all) if (!merged.contains(k)) k];
    }
  }

  // 5. linhas, baseline, palavras ---------------------------------------
  final lines = <_Built>[];
  for (final k in all) {
    lines.add(_build(k));
  }
  lines.sort((a, b) {
    final d = a.sortY.compareTo(b.sortY);
    if (d != 0) return d;
    final e = a.line.bounds.left.compareTo(b.line.bounds.left);
    return e != 0 ? e : a.firstOrder.compareTo(b.firstOrder);
  });
  return [for (final b in lines) b.line];
}

/// Separa em [stacked] os traços que são enfeite de outro (acento, pingo de i): ao menos 1,6× menores que um vizinho, com ≥ 60 % da largura
/// dentro da dele, logo acima dele; o vizinho vira `base` do enfeite.
/// O resto vai para [rest], na mesma ordem de [body]. Os [tiny] (miúdos demais
/// para serem escrita) só ganham a `base`, quando têm.
void _splitStacked(
  List<_C> body,
  List<_C> tiny,
  double ref,
  List<_C> rest,
  List<_C> stacked,
) {
  const cellW = 64.0, cellH = 32.0;
  int key(int ix, int iy) => ix * 8192 + (iy + 1024);
  final grid = <int, List<_C>>{};
  for (final c in body) {
    (grid[key((c.cx / cellW).floor(), (c.cy / cellH).floor())] ??= <_C>[]).add(c);
  }

  _C? findBase(_C c) {
    // (enfeite não é haste: um 'i' ou 'l' curto e fino sobre uma letra grande da
    // linha de baixo não é acento dela)
    if (c.h > 2.0 * c.w + 3) return null;
    final ix0 = (c.l / cellW).floor() - 2, ix1 = (c.r / cellW).floor() + 2;
    final iy0 = ((c.t - 1.0 * ref) / cellH).floor(), iy1 = ((c.b + 1.0 * ref) / cellH).floor();
    _C? best;
    var bestD = double.infinity;
    for (var ix = ix0; ix <= ix1; ix++) {
      for (var iy = iy0; iy <= iy1; iy++) {
        final list = grid[key(ix, iy)];
        if (list == null) continue;
        for (final m in list) {
          if (identical(m, c) || m.h < 1.6 * c.h) continue;
          // (numa linha inclinada o pingo cai ao lado da haste: folga de 0,25 por
          // unidade de distância vertical, que cobre até ~14° de inclinação)
          final slop = 0.25 * (m.cy - c.cy).abs();
          final ml = m.l - slop, mr = m.r + slop;
          final overlap = math.min(c.r, mr) - math.max(c.l, ml);
          if (overlap < 0.6 * c.w - 1e-9 || (c.w < 1 && (c.cx < ml || c.cx > mr))) continue;
          if (c.w > 1.5 * m.w + 4) continue;
          // (só "em cima": pingo e acento ficam acima da letra; a cedilha, que fica
          // embaixo, cai na regra da baseline)
          if (c.b > m.t + 0.3 * m.h || m.t - c.b > math.min(0.6 * m.h, 0.65 * ref)) continue;
          final d = m.t - c.b;
          if (d < bestD) {
            bestD = d;
            best = m;
          }
        }
      }
    }
    return best;
  }

  for (final c in tiny) {
    c.base = findBase(c);
  }
  for (final c in body) {
    if (c.h < 0.6 * ref) {
      final m = findBase(c);
      if (m != null) {
        c.base = m;
        stacked.add(c);
        continue;
      }
    }
    rest.add(c);
  }
}

/// Varredura da esquerda para a direita (os de [body] já vêm ordenados por cx):
/// cada traço entra na linha cuja reta prevista passa mais perto do seu centro
/// (tolerância proporcional à altura-x da linha); sem nenhuma, abre uma linha
/// nova. Com [deferred] != null, traços bem menores que a altura-x da linha
/// onde cairiam (ou que a da página, se não cairem em nenhuma) não entram na
/// varredura: acento, pingo e barra são colocados depois, pela posição em
/// relação à baseline.
void _sweep(List<_C> body, double pageXh, List<_Cluster> all, List<_C>? deferred) {
  var active = <_Cluster>[];
  var step = 0;
  for (final c in body) {
    // (poda as linhas que não alcançam mais o traço; a cada 16 traços basta)
    if ((++step & 15) == 0) {
      final minX = c.cx - kMaxTextStrokeWidth / 2;
      active = [
        for (final k in active)
          if (k.reachX >= minX) k,
      ];
    }
    _Cluster? best;
    var bestDy = double.infinity;
    final cx = c.cx, cy = c.cy, ch = c.h;
    for (var i = 0; i < active.length; i++) {
      final k = active[i];
      if (c.l > k.reachX) continue; // longe demais, à direita da linha
      // rejeição barata (sem regressão): longe demais do último traço da linha
      if ((cy - k.lastCy).abs() > k.reachBase + 0.53 * (cx - k.lastCx).abs()) continue;
      // uma "linha" de coisas miúdas (acento que ficou sem dono) não engole letras
      if (ch > 2.6 * k.meanH) continue;
      final dy = (cy - k.predict(cx)).abs();
      final unit = k.unit(pageXh);
      // (traço alto – 'l', 'p' – tem o centro deslocado até meia altura-x)
      final tol = 0.9 * unit + k.slack(cx, unit) + 0.5 * math.max(0.0, ch - unit);
      if (dy <= tol && dy / tol < bestDy) {
        best = k;
        bestDy = dy / tol;
      }
    }
    if (deferred != null && best == null && ch < 0.6 * pageXh) {
      deferred.add(c);
      continue;
    }
    if (best == null) {
      best = _Cluster(all.length, pageXh, c);
      all.add(best);
      active.add(best);
    } else {
      best.add(c);
    }
  }
}

int _queryStamp = 0;

/// Índice espacial simples (colunas de 64 unidades) das caixas das linhas,
/// para achar as candidatas a receber um traço pequeno sem varrer todas.
class _ClusterIndex {
  _ClusterIndex(List<_Cluster> clusters, double pad) {
    for (final k in clusters) {
      final b = k.box;
      final c0 = ((b.left - pad) / _cell).floor();
      final c1 = ((b.right + pad) / _cell).floor();
      for (var col = c0; col <= c1; col++) {
        (_cols[col] ??= <_Cluster>[]).add(k);
      }
    }
  }

  static const double _cell = 64;
  final Map<int, List<_Cluster>> _cols = {};

  /// Linhas cuja caixa (com folga) alcança as colunas de [c], sem repetição, na
  /// ordem das colunas.
  List<_Cluster> near(_C c) {
    final stamp = ++_queryStamp;
    final out = <_Cluster>[];
    final c0 = (c.l / _cell).floor(), c1 = (c.r / _cell).floor();
    for (var col = c0; col <= c1; col++) {
      final list = _cols[col];
      if (list == null) continue;
      for (final k in list) {
        if (k.stamp == stamp) continue;
        k.stamp = stamp;
        out.add(k);
      }
    }
    return out;
  }
}

/// Linha onde o traço pequeno [c] se encaixa: entre as linhas cuja caixa fica a
/// menos de [maxDist] do traço, a mais próxima cuja baseline deixa o traço
/// entre -0,5 e 2,3 alturas-x acima dela (pingos, barras e acentos; vírgula e
/// cedilha um pouco abaixo). Isso evita que o acento de uma linha vá parar na
/// descendente da linha de cima. Sem nenhuma assim: a mais próxima, se
/// [fallbackToNearest]. Com [bigger]: só linhas de altura média >= [bigger].
_Cluster? _attachSmall(
  _C c,
  _ClusterIndex index,
  double maxDist, {
  required bool fallbackToNearest,
  double bigger = 0,
}) {
  _Cluster? best, nearest;
  var bestD = double.infinity, nearestD = double.infinity;
  for (final k in index.near(c)) {
    if (bigger > 0 && k.meanH < bigger) continue;
    final box = k.box;
    final dx = math.max(0.0, math.max(box.left - c.r, c.l - box.right));
    final dy = math.max(0.0, math.max(box.top - c.b, c.t - box.bottom));
    final d2 = dx * dx + dy * dy;
    if (d2 > maxDist * maxDist) continue;
    if (d2 < nearestD) {
      nearestD = d2;
      nearest = k;
    }
    final f = k.fit;
    final up = (f.baselineAt(c.cx) - c.b) / f.xh;
    if (up >= -0.5 && up <= 2.3) {
      // (caixas de linhas coladas se sobrepõem: desempata pelo centro da linha)
      final dyc = c.cy - (f.baselineAt(c.cx) - 0.5 * f.xh);
      final score = d2 + 0.25 * dyc * dyc;
      if (score < bestD) {
        bestD = score;
        best = k;
      }
    }
  }
  return best ?? (fallbackToNearest ? nearest : null);
}

class _Built {
  _Built(this.line, this.sortY, this.firstOrder);
  final InkLine line;
  final double sortY;
  final int firstOrder;
}

_Built _build(_Cluster k) {
  if (k.members.length == 1 && k.extras.isEmpty) {
    // (caso comum numa página de rabiscos soltos: sem ordenar nem agrupar)
    final m = k.members.first;
    final vb = m.stroke.bounds;
    final line = InkLine(
      strokeIds: [m.stroke.id],
      bounds: vb,
      baselineY: m.b,
      angle: 0,
      words: [InkWord(strokeIds: [m.stroke.id], bounds: vb)],
    );
    _xhOf[line] = math.max(m.h, 1.0);
    return _Built(line, m.b, m.order);
  }
  final members = [...k.everyone]..sort((a, b) => a.order.compareTo(b.order));

  // caixa visível (com meia espessura) da linha
  Rect vis(_C c) => c.stroke.bounds;
  var bounds = vis(members.first);
  for (final m in members) {
    bounds = bounds.expandToInclude(vis(m));
  }

  final fit = k.fit;
  final xh = fit.xh;
  final slope = fit.slope;
  final baselineAtLeft = fit.baselineAt(bounds.left);

  // palavras
  // (lacuna entre a tinta de verdade, com a espessura da caneta)
  final byLeft = [...members]
    ..sort((a, b) {
      final d = a.stroke.bounds.left.compareTo(b.stroke.bounds.left);
      return d != 0 ? d : a.order.compareTo(b.order);
    });
  final words = <InkWord>[];
  var cur = <_C>[];
  var curRight = -double.infinity;
  final thr = kWordGapFactor * xh;
  void flush() {
    if (cur.isEmpty) return;
    cur.sort((a, b) => a.order.compareTo(b.order));
    var wb = vis(cur.first);
    for (final c in cur) {
      wb = wb.expandToInclude(vis(c));
    }
    words.add(InkWord(strokeIds: [for (final c in cur) c.stroke.id], bounds: wb));
    cur = <_C>[];
  }

  for (final c in byLeft) {
    final vb = c.stroke.bounds;
    if (cur.isNotEmpty && vb.left - curRight > thr) {
      flush();
      curRight = -double.infinity;
    }
    cur.add(c);
    curRight = math.max(curRight, vb.right);
  }
  flush();

  final line = InkLine(
    strokeIds: [for (final m in members) m.stroke.id],
    bounds: bounds,
    baselineY: baselineAtLeft,
    angle: math.atan(slope),
    words: words,
  );
  _xhOf[line] = xh;
  final midX = (bounds.left + bounds.right) / 2;
  return _Built(line, baselineAtLeft + slope * (midX - bounds.left), members.first.order);
}

/// Altura-x e baseline de uma linha (reta `y = base + slope·x`).
class _Fit {
  _Fit(this.xh, this.slope, this.base);
  final double xh, slope, base;
  double baselineAt(double x) => base + slope * x;
}

_Fit _fitBody(List<_C> body) {
  if (body.length == 1) {
    final m = body.first;
    return _Fit(math.max(m.h, 1.0), 0, m.b);
  }
  // altura-x (os pequenos que tenham entrado já são descartados pelo estimador)
  final xh = _xHeightFrom(
    [for (final m in body) m.h],
    fallback: math.max(4.0, body.first.h),
  );
  // baseline: regressão robusta das bases dos traços de corpo
  final pts = <(double, double)>[
    for (final m in body)
      if (m.h >= 0.5 * xh) (m.cx, m.b),
  ];
  var slope = 0.0;
  double base;
  var minX = double.infinity, maxX = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.$1);
    maxX = math.max(maxX, p.$1);
  }
  if (pts.length >= 5 && maxX - minX >= 5 * xh) {
    slope = _robustSlope(pts, 0.2 * xh).clamp(-_maxSlope, _maxSlope);
    // reta com a inclinação robusta e o intercepto = mediana dos resíduos
    final res = [for (final p in pts) p.$2 - slope * p.$1]..sort();
    base = res[res.length ~/ 2];
  } else {
    final bs = [for (final p in pts) p.$2]..sort();
    base = bs.isEmpty ? body.map((m) => m.b).reduce(math.max) : bs[bs.length ~/ 2];
  }
  return _Fit(xh, slope, base);
}

/// Inclinação de `y = a·x + b` por mínimos quadrados com rejeição de atípicos
/// (descendentes, pingos): refaz o ajuste ficando só com resíduos pequenos.
double _robustSlope(List<(double, double)> pts, double minTol) {
  var use = pts;
  var a = 0.0, b = 0.0;
  for (var iter = 0; iter < 4; iter++) {
    final n = use.length;
    if (n < 2) break;
    var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (final p in use) {
      sx += p.$1;
      sy += p.$2;
      sxx += p.$1 * p.$1;
      sxy += p.$1 * p.$2;
    }
    final den = n * sxx - sx * sx;
    if (den.abs() < 1e-9) break;
    a = (n * sxy - sx * sy) / den;
    b = (sy - a * sx) / n;
    final res = [for (final p in pts) (p.$2 - (a * p.$1 + b)).abs()]..sort();
    final mad = res[res.length ~/ 2];
    final tol = math.max(minTol, 2.5 * 1.4826 * mad);
    use = [
      for (final p in pts)
        if ((p.$2 - (a * p.$1 + b)).abs() <= tol) p,
    ];
  }
  return a;
}
