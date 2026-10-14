import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/agenda/agenda_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('guarda e devolve os ids escondidos por aparelho (SharedPreferences)', () async {
    const prefs = SharedPreferencesAgendaFilterPrefs();
    expect(await prefs.load(), isEmpty);
    await prefs.save({'a', 'b', kNoTagFilter});
    expect(await prefs.load(), {'a', 'b', kNoTagFilter});
    final raw = await SharedPreferences.getInstance();
    expect(raw.getStringList('agenda_hidden_tags'), unorderedEquals(['a', 'b', kNoTagFilter]));
    await prefs.save({});
    expect(await prefs.load(), isEmpty);
  });

  test('preferência corrompida (tipo errado) vira vazio, sem erro', () async {
    SharedPreferences.setMockInitialValues({'agenda_hidden_tags': 'texto solto'});
    expect(await const SharedPreferencesAgendaFilterPrefs().load(), isEmpty);
  });

  test('a versão em memória guarda o que recebe', () async {
    final prefs = MemoryAgendaFilterPrefs();
    await prefs.save({'x'});
    expect(await prefs.load(), {'x'});
  });
}
