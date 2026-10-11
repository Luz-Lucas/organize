import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'org_theme.dart';

/// Desenha o motivo decorativo de um tema (listras, grade, anéis…).
///
/// [color] já deve vir com pouca opacidade (use `accent` com alpha 0.10–0.18).
/// Só para cabeçalhos e o topo da Início, nunca atrás de texto longo.
class MotifPainter extends CustomPainter {
  MotifPainter({required this.motif, required this.color});

  /// Um dos ids de `OrgThemeSpec.motif`: `diagonal-stripes`, `wiregrid`,
  /// `leaf-rings`, `orbit-rings`, `ornament-dots`, `dot-grid`, `scanlines`,
  /// `wave-lines`, `brick-texture`, `cross-hatch`. Id desconhecido não pinta.
  final String motif;
  final Color color;

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  Paint get _fill => Paint()..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (motif) {
      case 'diagonal-stripes':
        _diagonals(canvas, size, 9, [135]);
      case 'cross-hatch':
        _diagonals(canvas, size, 7, [45, 135]);
      case 'wiregrid':
        _grid(canvas, size, 12);
      case 'leaf-rings':
        _rings(canvas, size, Offset(size.width * 0.92, size.height * 0.5), 14, dashed: false);
      case 'orbit-rings':
        _rings(canvas, size, Offset(size.width * 0.9, size.height * 0.45), 18, dashed: true);
      case 'ornament-dots':
        _dots(canvas, size, 14, 1.6, stagger: true);
      case 'dot-grid':
        _dots(canvas, size, 10, 1.2);
      case 'scanlines':
        _scanlines(canvas, size, 4);
      case 'wave-lines':
        _rings(canvas, size, Offset(0, size.height), 16, dashed: false, lower: true);
      case 'brick-texture':
        _bricks(canvas, size, 16, 8);
    }
    canvas.restore();
  }

  void _diagonals(Canvas canvas, Size size, double step, List<int> angles) {
    final p = _stroke;
    final span = size.width + size.height;
    for (final angle in angles) {
      for (double d = -size.height; d < span; d += step) {
        if (angle == 135) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
        } else {
          canvas.drawLine(Offset(d, size.height), Offset(d + size.height, 0), p);
        }
      }
    }
  }

  void _grid(Canvas canvas, Size size, double step) {
    final p = _stroke;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _rings(Canvas canvas, Size size, Offset center, double step,
      {required bool dashed, bool lower = false}) {
    final p = _stroke;
    final maxR = math.sqrt(size.width * size.width + size.height * size.height);
    final limit = lower ? maxR : math.min(maxR, size.width * 0.8);
    for (double r = step; r < limit; r += step) {
      final rect = Rect.fromCircle(center: center, radius: r);
      if (dashed) {
        const dash = 0.12, gap = 0.08;
        for (double a = 0; a < math.pi * 2; a += dash + gap) {
          canvas.drawArc(rect, a, dash, false, p);
        }
      } else if (lower) {
        // Ondas: só o quarto de círculo acima/à direita do canto.
        canvas.drawArc(rect, -math.pi / 2, math.pi / 2, false, p);
      } else {
        canvas.drawCircle(center, r, p);
      }
    }
  }

  void _dots(Canvas canvas, Size size, double step, double radius, {bool stagger = false}) {
    final p = _fill;
    var row = 0;
    for (double y = step / 2; y < size.height; y += step, row++) {
      final shift = stagger && row.isOdd ? step / 2 : 0.0;
      for (double x = step / 2 + shift; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), radius, p);
      }
    }
  }

  void _scanlines(Canvas canvas, Size size, double step) {
    final p = _stroke;
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _bricks(Canvas canvas, Size size, double w, double h) {
    final p = _stroke;
    var row = 0;
    for (double y = 0; y < size.height; y += h, row++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      final shift = row.isOdd ? w / 2 : 0.0;
      for (double x = shift; x < size.width; x += w) {
        canvas.drawLine(Offset(x, y), Offset(x, y + h), p);
      }
    }
  }

  @override
  bool shouldRepaint(MotifPainter old) => old.motif != motif || old.color != color;
}

/// Fundo com o motivo do tema atrás de [child], recortado em `radiusLg`.
///
/// Use no topo da Início e em cabeçalhos de página; o conteúdo longo deve
/// ficar fora dele.
class MotifBackground extends StatelessWidget {
  const MotifBackground({super.key, required this.child, this.height = 140});

  final Widget child;

  /// Altura mínima do bloco.
  final double height;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return ClipRRect(
      borderRadius: BorderRadius.circular(org.radiusLg),
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        decoration: BoxDecoration(
          color: org.surfaceRaised,
          border: Border.all(color: org.line),
          borderRadius: BorderRadius.circular(org.radiusLg),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: MotifPainter(
                    motif: org.motif,
                    color: org.accent.withValues(alpha: 0.14),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
