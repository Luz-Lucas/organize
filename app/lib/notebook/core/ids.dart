import 'dart:math' as math;

int _lastMs = 0;
int _seq = 0;
math.Random? _rng;

/// Id novo, único e **estritamente crescente** neste processo; entre
/// aparelhos, cresce com o relógio. Ordenar ids = ordem de criação (é o que
/// dá a ordem de empilhamento canônica depois de um `merge`).
///
/// Formato: 9 chars de milissegundos em base 36 + 3 de sequência + 5
/// aleatórios (17 chars).
String newInkId() {
  var ms = DateTime.now().millisecondsSinceEpoch;
  if (ms <= _lastMs) {
    // Relógio parado ou voltou: continua da última marca.
    ms = _lastMs;
    _seq++;
    if (_seq >= 46656) {
      ms++;
      _seq = 0;
    }
  } else {
    _seq = 0;
  }
  _lastMs = ms;
  final rng = _rng ??= math.Random.secure();
  final rand = StringBuffer();
  for (var i = 0; i < 5; i++) {
    rand.write(rng.nextInt(36).toRadixString(36));
  }
  return '${ms.toRadixString(36).padLeft(9, '0')}'
      '${_seq.toRadixString(36).padLeft(3, '0')}'
      '$rand';
}
