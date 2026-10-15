import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Raio maior (px lógicos) a partir do qual um toque é tratado como palma
/// quando "Desenhar com o dedo" está ligado. Dedo: ~6–16; palma: > 30.
const double kPalmRadiusMajor = 28;

/// Quanto tempo a caneta continua "ativa" depois de levantada/afastada.
const Duration kPenHold = Duration(milliseconds: 1500);

/// Estado **global** da caneta (vale para todas as páginas): ativa enquanto
/// encosta no papel, enquanto paira sobre a tela (hover) e por [kPenHold]
/// depois de levantar. Serve para rejeitar a palma: enquanto a caneta está
/// ativa, toque de um dedo é ignorado; dois dedos ainda rolam/dão zoom.
///
/// Também cuida da prioridade: quando a caneta encosta, toques em andamento
/// (ex.: a palma já rolando a página) são cancelados.
///
/// Os eventos chegam por [attach] (rota global do `PointerRouter`, que também
/// enxerga o hover fora das páginas) e por [note] (chamado pelas páginas, que
/// recebem o evento antes da rota global).
class PenActivity {
  PenActivity({Duration Function()? now, void Function(int pointer)? cancelTouch})
    : _now = now ?? _wallClock,
      _cancelTouch = cancelTouch ?? _cancelOnBinding;

  /// Instância usada quando não há [PenActivityScope] nem `InteractiveViewer`
  /// (a tela) acima da página.
  static final PenActivity shared = PenActivity();

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _wallClock() => _stopwatch.elapsed;
  static void _cancelOnBinding(int pointer) => GestureBinding.instance.cancelPointer(pointer);

  /// Uma instância por tela: a chave é o `TransformationController` do
  /// `InteractiveViewer` que envolve as páginas.
  static final Expando<PenActivity> _perViewer = Expando<PenActivity>('PenActivity');

  final Duration Function() _now;
  final void Function(int pointer) _cancelTouch;
  final Set<int> _stylusDown = {};
  final Set<int> _touchDown = {};
  Duration? _lastPenEvent;
  PointerEvent? _lastNoted;
  int _attached = 0;

  /// Último evento visto (kind, botões, pressão) — para o modo `debugInput`.
  /// Só é preenchido quando [debugEnabled] (evita montar texto a 240 eventos/s).
  final ValueNotifier<String> lastEvent = ValueNotifier<String>('—');
  bool debugEnabled = false;

  static bool isPen(PointerDeviceKind k) =>
      k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  /// A caneta está encostando, pairando ou acabou de sair (últimos [kPenHold]).
  bool get isActive {
    if (_stylusDown.isNotEmpty) return true;
    final t = _lastPenEvent;
    return t != null && _now() - t < kPenHold;
  }

  /// Quantos toques estão na tela agora.
  int get touchCount => _touchDown.length;

  void reset() {
    _stylusDown.clear();
    _touchDown.clear();
    _lastPenEvent = null;
    _lastNoted = null;
  }

  /// Registra [e]. Pode ser chamado mais de uma vez para o mesmo evento.
  void note(PointerEvent e) {
    if (identical(e, _lastNoted)) return;
    _lastNoted = e;
    final kind = e.kind;
    if (isPen(kind)) {
      _lastPenEvent = _now();
      if (e is PointerDownEvent) {
        final first = _stylusDown.isEmpty;
        _stylusDown.add(e.pointer);
        if (first) {
          // A caneta tem prioridade: cancela os toques em andamento.
          for (final t in _touchDown.toList()) {
            _cancelTouch(t);
          }
        }
      } else if (e is PointerUpEvent || e is PointerCancelEvent || e is PointerRemovedEvent) {
        _stylusDown.remove(e.pointer);
      }
    } else if (kind == PointerDeviceKind.touch) {
      if (e is PointerDownEvent) {
        _touchDown.add(e.pointer);
      } else if (e is PointerUpEvent || e is PointerCancelEvent || e is PointerRemovedEvent) {
        _touchDown.remove(e.pointer);
      }
    }
    if (debugEnabled) lastEvent.value = describe(e);
  }

  /// "kind=stylus buttons=2 pressure=0.43" (pressão normalizada 0–1).
  static String describe(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    final p = range > 0 ? (e.pressure - e.pressureMin) / range : e.pressure;
    return 'kind=${e.kind.name} buttons=${e.buttons} pressure=${p.toStringAsFixed(2)} '
        '(raw ${e.pressure.toStringAsFixed(2)}/${e.pressureMax.toStringAsFixed(2)})';
  }

  void _route(PointerEvent e) => note(e);

  /// Passa a ouvir todos os eventos de ponteiro do app (contagem de usos).
  void attach() {
    if (_attached++ == 0) GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  void detach() {
    if (_attached > 0 && --_attached == 0) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
      reset();
    }
  }

  /// A instância que vale para [context]: o [PenActivityScope] mais próximo; senão
  /// a da tela (pelo controller do `InteractiveViewer` acima); senão [shared].
  static PenActivity of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<PenActivityScope>();
    if (scope != null) return scope.activity;
    final viewer = context.findAncestorWidgetOfExactType<InteractiveViewer>();
    final key = viewer?.transformationController;
    if (key != null) return _perViewer[key] ??= PenActivity();
    return shared;
  }
}

/// Fornece uma [PenActivity] às páginas abaixo (útil na tela e nos testes).
class PenActivityScope extends InheritedWidget {
  const PenActivityScope({super.key, required this.activity, required super.child});

  final PenActivity activity;

  @override
  bool updateShouldNotify(PenActivityScope old) => !identical(old.activity, activity);
}
