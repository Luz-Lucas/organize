import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Visão da agenda no celular (abaixo de 720 dp): mês com lista do dia, ou semana em grade de horas.
enum MobileAgendaView { month, week }

const double kDefaultHourHeight = 48;
const double kMinHourHeight = 32;
const double kMaxHourHeight = 120;

/// Altura da hora na semana do celular: sempre entre [kMinHourHeight] e [kMaxHourHeight].
double clampHourHeight(double h) => h.clamp(kMinHourHeight, kMaxHourHeight).toDouble();

/// Onde ficam a visão escolhida e a altura da hora: por aparelho, não vão para a nuvem.
abstract interface class AgendaViewPrefs {
  Future<String?> loadView();
  Future<void> saveView(String value);
  Future<double?> loadHourHeight();
  Future<void> saveHourHeight(double value);
}

class MemoryAgendaViewPrefs implements AgendaViewPrefs {
  MemoryAgendaViewPrefs({this.view, this.hourHeight});

  String? view;
  double? hourHeight;

  @override
  Future<String?> loadView() async => view;

  @override
  Future<void> saveView(String value) async => view = value;

  @override
  Future<double?> loadHourHeight() async => hourHeight;

  @override
  Future<void> saveHourHeight(double value) async => hourHeight = value;
}

class SharedPreferencesAgendaViewPrefs implements AgendaViewPrefs {
  const SharedPreferencesAgendaViewPrefs();

  static const _viewKey = 'agenda_mobile_view';
  static const _heightKey = 'agenda_hour_height';

  @override
  Future<String?> loadView() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_viewKey);
    } catch (_) {
      return null; // valor de outro tipo ou leitura impossível: fica o padrão
    }
  }

  @override
  Future<void> saveView(String value) async =>
      (await SharedPreferences.getInstance()).setString(_viewKey, value);

  @override
  Future<double?> loadHourHeight() async {
    try {
      return (await SharedPreferences.getInstance()).getDouble(_heightKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveHourHeight(double value) async =>
      (await SharedPreferences.getInstance()).setDouble(_heightKey, value);
}

/// Os testes usam a memória; `main.dart` troca por [SharedPreferencesAgendaViewPrefs].
final agendaViewPrefsProvider = Provider<AgendaViewPrefs>((ref) => MemoryAgendaViewPrefs());

/// Mês ou semana no celular. Nasce em Mês e troca para o valor guardado assim que ele é lido.
class AgendaMobileViewNotifier extends Notifier<MobileAgendaView> {
  bool _chosen = false;

  @override
  MobileAgendaView build() {
    unawaited(_restore());
    return MobileAgendaView.month;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(agendaViewPrefsProvider).loadView();
      if (!_chosen && ref.mounted && saved == MobileAgendaView.week.name) state = MobileAgendaView.week;
    } catch (_) {
      // Sem preferência guardada: fica em Mês.
    }
  }

  void select(MobileAgendaView view) {
    _chosen = true;
    state = view;
    unawaited(ref.read(agendaViewPrefsProvider).saveView(view.name).catchError((Object _) {}));
  }
}

final agendaMobileViewProvider =
    NotifierProvider<AgendaMobileViewNotifier, MobileAgendaView>(AgendaMobileViewNotifier.new);

/// Altura da hora na semana do celular. [preview] acompanha a pinça sem gravar; [commit] grava o valor
/// atual quando os dedos saem da tela.
class AgendaHourHeightNotifier extends Notifier<double> {
  bool _touched = false;

  @override
  double build() {
    unawaited(_restore());
    return kDefaultHourHeight;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(agendaViewPrefsProvider).loadHourHeight();
      if (!_touched && ref.mounted && saved != null && saved.isFinite) state = clampHourHeight(saved);
    } catch (_) {
      // Sem preferência guardada: altura padrão.
    }
  }

  void preview(double height) {
    _touched = true;
    state = clampHourHeight(height);
  }

  void commit() {
    _touched = true;
    unawaited(ref.read(agendaViewPrefsProvider).saveHourHeight(state).catchError((Object _) {}));
  }
}

final agendaHourHeightProvider =
    NotifierProvider<AgendaHourHeightNotifier, double>(AgendaHourHeightNotifier.new);
