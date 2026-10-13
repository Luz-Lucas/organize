import 'dart:math' as math;
import 'dart:ui' hide TextBox;

/// Distância do ponto [p] ao segmento [a]–[b].
double distPointSegment(Offset p, Offset a, Offset b) =>
    math.sqrt(sqDistPointSegment(p, a, b));

double sqDistPointSegment(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final len2 = dx * dx + dy * dy;
  var t = 0.0;
  if (len2 > 0) {
    t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2).clamp(0.0, 1.0);
  }
  final cx = a.dx + t * dx - p.dx, cy = a.dy + t * dy - p.dy;
  return cx * cx + cy * cy;
}

double _cross(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
  final d1 = _cross(c, d, a), d2 = _cross(c, d, b);
  final d3 = _cross(a, b, c), d4 = _cross(a, b, d);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Menor distância entre os segmentos [a]–[b] e [c]–[d].
double distSegmentSegment(Offset a, Offset b, Offset c, Offset d) {
  if (_segmentsIntersect(a, b, c, d)) return 0;
  return math.min(
    math.min(distPointSegment(a, c, d), distPointSegment(b, c, d)),
    math.min(distPointSegment(c, a, b), distPointSegment(d, a, b)),
  );
}

(double, double)? _clipLinear(
  double lo,
  double hi,
  double v0,
  double dv,
  double min,
  double max,
) {
  if (dv.abs() < 1e-12) {
    return v0 >= min && v0 <= max ? (lo, hi) : null;
  }
  var t1 = (min - v0) / dv, t2 = (max - v0) / dv;
  if (t1 > t2) {
    final s = t1;
    t1 = t2;
    t2 = s;
  }
  final l = math.max(lo, t1), h = math.min(hi, t2);
  return l <= h ? (l, h) : null;
}

(double, double)? _lineDisk(Offset a, Offset d, Offset c, double r) {
  final ax = a.dx - c.dx, ay = a.dy - c.dy;
  final qa = d.dx * d.dx + d.dy * d.dy;
  final qc = ax * ax + ay * ay - r * r;
  if (qa < 1e-18) {
    return qc <= 0 ? (double.negativeInfinity, double.infinity) : null;
  }
  final qb = 2 * (d.dx * ax + d.dy * ay);
  final disc = qb * qb - 4 * qa * qc;
  if (disc < 0) return null;
  final s = math.sqrt(disc);
  return ((-qb - s) / (2 * qa), (-qb + s) / (2 * qa));
}

/// Intervalo `[t0, t1] ⊂ [0, 1]` do segmento [a]→[b] (`P(t) = a + t(b−a)`) que
/// fica a no máximo [r] do segmento [e0]–[e1] (a "cápsula" da borracha), ou
/// `null` se não encosta. A cápsula é convexa, então o resultado é um único
/// intervalo exato.
(double, double)? segmentCapsuleInterval(
  Offset a,
  Offset b,
  Offset e0,
  Offset e1,
  double r,
) {
  final d = b - a;
  double? lo, hi;
  void take((double, double)? i) {
    if (i == null) return;
    lo = lo == null ? i.$1 : math.min(lo!, i.$1);
    hi = hi == null ? i.$2 : math.max(hi!, i.$2);
  }

  take(_lineDisk(a, d, e0, r));
  final ex = e1.dx - e0.dx, ey = e1.dy - e0.dy;
  final len = math.sqrt(ex * ex + ey * ey);
  if (len > 1e-12) {
    take(_lineDisk(a, d, e1, r));
    final ux = ex / len, uy = ey / len;
    final ax = a.dx - e0.dx, ay = a.dy - e0.dy;
    var iv = _clipLinear(
      double.negativeInfinity,
      double.infinity,
      ax * ux + ay * uy,
      d.dx * ux + d.dy * uy,
      0,
      len,
    );
    if (iv != null) {
      iv = _clipLinear(
        iv.$1,
        iv.$2,
        -ax * uy + ay * ux,
        -d.dx * uy + d.dy * ux,
        -r,
        r,
      );
    }
    take(iv);
  }
  if (lo == null) return null;
  final l = math.max(0.0, lo!), h = math.min(1.0, hi!);
  return l <= h ? (l, h) : null;
}

/// Teste par-ímpar (o polígono é fechado implicitamente).
bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Distância do ponto [p] ao retângulo (0 se estiver dentro).
double distPointRect(Offset p, Rect r) {
  final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
  final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}
