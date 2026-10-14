import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/calendar_event.dart';

/// Id usado no filtro para "Sem etiqueta" (nenhuma etiqueta real tem esse id, que é um uuid).
const kNoTagFilter = '_none';

/// Onde ficam as etiquetas escondidas da agenda: por aparelho, não vão para a nuvem.
abstract interface class AgendaFilterPrefs {
  Future<Set<String>> load();
  Future<void> save(Set<String> hidden);
}

class MemoryAgendaFilterPrefs implements AgendaFilterPrefs {
  Set<String> _hidden = {};

  @override
  Future<Set<String>> load() async => {..._hidden};

  @override
  Future<void> save(Set<String> hidden) async => _hidden = {...hidden};
}

class SharedPreferencesAgendaFilterPrefs implements AgendaFilterPrefs {
  const SharedPreferencesAgendaFilterPrefs();

  static const _key = 'agenda_hidden_tags';

  @override
  Future<Set<String>> load() async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(_key) ?? const <String>[]).toSet();
    } catch (_) {
      return {}; // valor de outro tipo ou leitura impossível: tudo visível
    }
  }

  @override
  Future<void> save(Set<String> hidden) async =>
      (await SharedPreferences.getInstance()).setStringList(_key, hidden.toList()..sort());
}

/// Os testes usam a memória; `main.dart` troca por [SharedPreferencesAgendaFilterPrefs].
final agendaFilterPrefsProvider = Provider<AgendaFilterPrefs>((ref) => MemoryAgendaFilterPrefs());

/// Etiquetas escondidas na agenda (ids, mais [kNoTagFilter]). Guardar o que está *escondido* faz uma
/// etiqueta nova nascer visível.
class AgendaHiddenTagsNotifier extends Notifier<Set<String>> {
  bool _touched = false;

  @override
  Set<String> build() {
    unawaited(_restore());
    return const {};
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(agendaFilterPrefsProvider).load();
      if (!_touched && ref.mounted) state = saved;
    } catch (_) {
      // Sem preferência guardada: tudo visível.
    }
  }

  void toggle(String key) {
    _touched = true;
    final next = {...state};
    if (!next.remove(key)) next.add(key);
    state = next;
    unawaited(ref.read(agendaFilterPrefsProvider).save(next).catchError((Object _) {}));
  }
}

final agendaHiddenTagsProvider =
    NotifierProvider<AgendaHiddenTagsNotifier, Set<String>>(AgendaHiddenTagsNotifier.new);

/// Filtra [events] escondendo os das etiquetas em [hidden]. Evento com etiqueta que não existe mais
/// conta como "Sem etiqueta" (o banco as deixa nulas).
List<CalendarEvent> filterByTag(List<CalendarEvent> events, Set<String> hidden, Set<String> knownTagIds) {
  if (hidden.isEmpty) return events;
  return [
    for (final e in events)
      if (!hidden.contains(e.tagId != null && knownTagIds.contains(e.tagId) ? e.tagId : kNoTagFilter)) e,
  ];
}
